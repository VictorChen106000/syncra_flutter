import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../data/models/job.dart';
import '../models/resume_json.dart';

/// Sends a structured [ResumeJson] + job description to Claude and returns
/// a tailored [ResumeJson] (same shape, rewritten bullets, reordered skills).
class ResumeTailorService {
  ResumeTailorService({
    String? apiKey,
    http.Client? client,
    this.model = 'claude-haiku-4-5-20251001',
  })  : _apiKey = apiKey ?? const String.fromEnvironment('ANTHROPIC_API_KEY'),
        _client = client ?? http.Client();

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _version = '2023-06-01';

  /// Per-request retry budget for transient API failures (429 / 5xx / 529).
  /// Four attempts → three backoff retries (~1s/2s/4s) before failing, so an
  /// "Overloaded" blip doesn't surface as a failed resume tailor.
  static const _maxApiAttempts = 4;

  static const _system = '''
You are Syncra's resume tailor. You receive a candidate's structured resume
(JSON) and a target job description. Return a tailored version of the SAME
JSON object — identical schema and keys — with the following changes only:

- experience[].bullets and projects[].bullets: rewrite to emphasize keywords
  from the job. Keep the same factual claims — never invent new experience,
  metrics, or roles.
- summary: rewrite (or add if missing) one sentence aligning the candidate
  with the target role.
- skill_groups[].items: reorder so the most relevant-to-this-job skills come
  first within each group. Do NOT add skills the candidate doesn't have, and
  do NOT remove a group.

PRESERVE THE WHOLE RESUME. Every section and every entry present in the input
MUST be present in the output — including education, projects, certifications,
and all skill groups. Never delete, drop, empty, or omit a section to "trim"
the resume. Removing the candidate's real content is the worst possible
outcome.

Do NOT change: header, company names, role titles, dates, education,
project facts, links, certifications.

Return ONLY the tailored JSON object. No prose, no markdown fences.''';

  final String _apiKey;
  final http.Client _client;
  final String model;

  bool get hasApiKey => _apiKey.isNotEmpty;

  /// Tailors [resume] for [job]. Throws on API failure. Returns `null` if
  /// no API key is configured.
  Future<ResumeJson?> tailor({
    required ResumeJson resume,
    required Job job,
  }) async {
    if (!hasApiKey) return null;

    final userPrompt = '''
TARGET JOB
----------
Title: ${job.title}
Company: ${job.company}
Location: ${job.location}

Description:
${job.why}

CANDIDATE RESUME (JSON)
-----------------------
${const JsonEncoder.withIndent('  ').convert(resume.toJson())}

Return the tailored resume JSON now.''';

    final text = await _callClaude(userPrompt, strict: false);
    try {
      return _parseJsonResponse(text);
    } on ResumeTailorException {
      // The model returned malformed JSON — retry once with a stricter
      // instruction before surfacing the failure.
      debugPrint('resume tailor JSON malformed — retrying once (strict)');
      final retry = await _callClaude(userPrompt, strict: true);
      return _parseJsonResponse(retry);
    }
  }

  /// Single Anthropic call returning the concatenated text content. When
  /// [strict] is set, prepends an instruction emphasizing raw-JSON-only
  /// output — used for the one retry after a malformed-JSON response.
  Future<String> _callClaude(String userPrompt, {required bool strict}) async {
    final content = strict
        ? 'Your previous response was not valid JSON. Return ONLY the raw '
            'tailored JSON object — no markdown fences, no commentary.\n\n'
            '$userPrompt'
        : userPrompt;

    final body = jsonEncode({
      'model': model,
      'max_tokens': 2048,
      'system': _system,
      'messages': [
        {'role': 'user', 'content': content},
      ],
    });

    final response = await _postWithRetry(body);

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final blocks = decoded['content'] as List? ?? const [];
    final text = blocks
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => (b['text'] as String?) ?? '')
        .join('\n')
        .trim();

    if (text.isEmpty) {
      throw const ResumeTailorException('Anthropic returned no content.');
    }
    return text;
  }

  /// POSTs [body] to Anthropic, retrying transient failures (429 / 5xx /
  /// 529 "Overloaded" / timeouts) up to [_maxApiAttempts] times with ~1s/2s/4s
  /// backoff. A 200 returns immediately; permanent errors (auth, bad request)
  /// fail without retrying.
  Future<http.Response> _postWithRetry(String body) async {
    Object lastError =
        const ResumeTailorException('Anthropic request failed.');
    for (var attempt = 1; attempt <= _maxApiAttempts; attempt++) {
      try {
        final response = await _client
            .post(
              Uri.parse(_endpoint),
              headers: {
                'content-type': 'application/json',
                'x-api-key': _apiKey,
                'anthropic-version': _version,
                'anthropic-dangerous-direct-browser-access': 'true',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) return response;

        final error = ResumeTailorException(
          _extractError(response.body, response.statusCode),
        );
        if (!_isRetryableStatus(response.statusCode) ||
            attempt == _maxApiAttempts) {
          throw error;
        }
        lastError = error;
        await Future<void>.delayed(
          _backoffDelay(attempt, response.headers['retry-after']),
        );
      } on TimeoutException {
        if (attempt == _maxApiAttempts) {
          throw const ResumeTailorException(
            'Anthropic request timed out. Please try again.',
          );
        }
        await Future<void>.delayed(_backoffDelay(attempt, null));
      }
    }
    throw lastError;
  }

  /// Transient HTTP statuses worth retrying: 429 rate-limit and any 5xx
  /// server error (529 "Overloaded" included).
  static bool _isRetryableStatus(int code) =>
      code == 429 || (code >= 500 && code < 600);

  /// Exponential backoff — ~1s, 2s, 4s between attempts. Honors a server
  /// `Retry-After` header (in seconds) when present.
  Duration _backoffDelay(int attempt, String? retryAfterHeader) {
    final retryAfter = int.tryParse(retryAfterHeader ?? '');
    if (retryAfter != null && retryAfter > 0) {
      return Duration(seconds: retryAfter.clamp(1, 30));
    }
    return Duration(milliseconds: 500 * (1 << attempt));
  }

  ResumeJson _parseJsonResponse(String raw) {
    final cleaned = _stripFences(raw);
    try {
      final map = jsonDecode(cleaned) as Map<String, dynamic>;
      return ResumeJson.fromJson(map);
    } catch (e) {
      debugPrint('Could not parse Claude tailor JSON: $e\nRaw: $raw');
      throw const ResumeTailorException(
        'Resume tailor returned invalid JSON.',
      );
    }
  }

  String _stripFences(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    final firstNewline = trimmed.indexOf('\n');
    final body = firstNewline == -1
        ? trimmed.substring(3)
        : trimmed.substring(firstNewline + 1);
    final end = body.lastIndexOf('```');
    return end == -1 ? body.trim() : body.substring(0, end).trim();
  }

  String _extractError(String body, int status) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      return error?['message']?.toString() ?? 'HTTP $status';
    } catch (_) {
      return 'HTTP $status';
    }
  }

  void dispose() => _client.close();
}

class ResumeTailorException implements Exception {
  const ResumeTailorException(this.message);
  final String message;
  @override
  String toString() => 'ResumeTailorException: $message';
}

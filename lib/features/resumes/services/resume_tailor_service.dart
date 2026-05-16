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

  static const _system = '''
You are Syncra's resume tailor. You receive a candidate's structured resume
(JSON) and a target job description. Return a tailored version of the same
JSON, with the following changes only:

- experience[].bullets: rewrite to emphasize keywords from the job. Keep
  the same factual claims — never invent new experience, metrics, or roles.
- summary: rewrite (or add if missing) one sentence aligning the candidate
  with the target role.
- skills: reorder so the most relevant-to-this-job skills come first. Do
  NOT add skills the candidate doesn't already have.

Do NOT change: header, company names, role titles, dates, education,
project facts, links.

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

    final payload = {
      'model': model,
      'max_tokens': 2048,
      'system': _system,
      'messages': [
        {'role': 'user', 'content': userPrompt}
      ],
    };

    final response = await _client
        .post(
          Uri.parse(_endpoint),
          headers: {
            'content-type': 'application/json',
            'x-api-key': _apiKey,
            'anthropic-version': _version,
            'anthropic-dangerous-direct-browser-access': 'true',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      throw ResumeTailorException(
        _extractError(response.body, response.statusCode),
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content = decoded['content'] as List? ?? const [];
    final text = content
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => (b['text'] as String?) ?? '')
        .join('\n')
        .trim();

    if (text.isEmpty) {
      throw const ResumeTailorException('Anthropic returned no content.');
    }

    return _parseJsonResponse(text);
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

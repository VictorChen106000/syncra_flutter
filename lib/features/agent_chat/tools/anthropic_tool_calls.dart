import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../data/models/job.dart';

/// Lightweight Anthropic wrapper used by tool handlers for paraphrasing
/// tasks (tailor_resume, draft_email). Distinct from `AnthropicService`
/// (job-matching) and `AnthropicChatService` (chat loop) so each callsite
/// owns its own prompt + response shape without coupling.
///
/// Reads the same `--dart-define=ANTHROPIC_API_KEY=...` as the others.
class AnthropicParaphraseService {
  AnthropicParaphraseService({
    String? apiKey,
    http.Client? client,
    this.model = 'claude-haiku-4-5-20251001',
  })  : _apiKey = apiKey ?? const String.fromEnvironment('ANTHROPIC_API_KEY'),
        _client = client ?? http.Client();

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _version = '2023-06-01';

  /// Per-request retry budget for transient API failures (429 / 5xx / 529).
  /// Four attempts → three backoff retries (~1s/2s/4s) before failing, so an
  /// "Overloaded" blip doesn't surface as a failed tool call.
  static const _maxApiAttempts = 4;

  final String _apiKey;
  final http.Client _client;
  final String model;

  bool get hasApiKey => _apiKey.isNotEmpty;

  /// Returns PR-style proposed edits for a target job.
  ///
  /// Shape:
  /// {
  ///   "proposed_edits": [
  ///     {
  ///       "target_path": "experience[0].bullets[2]",
  ///       "original_text": "...",
  ///       "proposed_text": "...",
  ///       "reason": "..."
  ///     }
  ///   ]
  /// }
  Future<Map<String, dynamic>> tailorResume({
    required Map<String, dynamic> resumeJson,
    required Job job,
  }) async {
    final userPrompt = '''
  Resume (JSON):
  ${const JsonEncoder.withIndent('  ').convert(resumeJson)}

  Target job:
  - title: ${job.title}
  - company: ${job.company}
  - location: ${job.location}
  - description: ${job.why}

  Return ONLY a JSON object with this exact shape:
  {
    "proposed_edits": [
      {
        "target_path": "experience[0].bullets[2]",
        "original_text": "exact text copied verbatim from the resume",
        "proposed_text": "rewritten text",
        "reason": "one sentence explaining why this helps for this job"
      }
    ]
  }
  ''';

    final response = await _call(
      system: tailorSystemPrompt,
      user: userPrompt,
      maxTokens: 1200,
    );

    try {
      return _parseProposedEdits(response);
    } catch (e) {
      // The model returned malformed JSON — retry once with a stricter
      // instruction before surfacing the failure.
      debugPrint('tailorResume edits malformed — retrying once (strict)');
      final retry = await _call(
        system: tailorSystemPrompt,
        user: 'Your previous response was not valid JSON. Return ONLY the '
            'raw JSON object — no markdown fences, no commentary.\n\n'
            '$userPrompt',
        maxTokens: 1200,
      );
      try {
        return _parseProposedEdits(retry);
      } catch (e) {
        debugPrint('tailorResume retry still malformed: $e\nRaw: $retry');
        throw Exception('Could not parse proposed resume edits JSON.');
      }
    }
  }

  /// Strips fences, decodes, and validates the `proposed_edits` array shape.
  /// Throws on malformed JSON or a missing array so the caller can retry.
  Map<String, dynamic> _parseProposedEdits(String response) {
    final decoded = jsonDecode(_stripFences(response)) as Map<String, dynamic>;
    final rawEdits = decoded['proposed_edits'];
    if (rawEdits is! List) {
      throw const FormatException('Missing proposed_edits array.');
    }
    return {'proposed_edits': rawEdits};
  }

  /// Returns `{ subject, body }`.
  Future<Map<String, dynamic>> draftColdEmail({
    required Map<String, dynamic> resumeJson,
    required Job job,
    String? recipientName,
    String tone = 'warm',
  }) async {
    final response = await _call(
      system: _emailSystem,
      user: '''
Candidate (ResumeJSON):
${const JsonEncoder.withIndent('  ').convert(resumeJson)}

Target job:
- title: ${job.title}
- company: ${job.company}
- description: ${job.why}

Recipient: ${recipientName ?? 'the hiring team at ${job.company}'}
Tone: $tone

Return ONLY a JSON object: {"subject": "...", "body": "..."}.''',
      maxTokens: 600,
    );
    final cleaned = _stripFences(response);
    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('draftColdEmail parse failed: $e\nRaw: $response');
      throw Exception('Could not parse email draft JSON.');
    }
  }

  Future<String> _call({
    required String system,
    required String user,
    required int maxTokens,
  }) async {
    final body = jsonEncode({
      'model': model,
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': user},
      ],
    });

    final response = await _postWithRetry(body);

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content = (decoded['content'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => (b['text'] as String?) ?? '')
        .join('\n')
        .trim();
    if (content.isEmpty) {
      throw Exception('Anthropic returned no text.');
    }
    return content;
  }

  /// POSTs [body] to Anthropic, retrying transient failures (429 / 5xx /
  /// 529 "Overloaded" / timeouts) up to [_maxApiAttempts] times with ~1s/2s/4s
  /// backoff. A 200 returns immediately; permanent errors (auth, bad request)
  /// fail without retrying.
  Future<http.Response> _postWithRetry(String body) async {
    Object lastError = Exception('Anthropic request failed.');
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

        final error =
            Exception(_extractError(response.body, response.statusCode));
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
          throw Exception('Anthropic request timed out. Please try again.');
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

  String _stripFences(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    final firstNewline = trimmed.indexOf('\n');
    final stripped = firstNewline == -1
        ? trimmed.substring(3)
        : trimmed.substring(firstNewline + 1);
    final end = stripped.lastIndexOf('```');
    return end == -1 ? stripped.trim() : stripped.substring(0, end).trim();
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

/// System prompt for `tailor_resume`. Public so prompt-contract regression
/// tests can assert the verbatim / no-full-rewrite guardrails stay in place.
  static const tailorSystemPrompt = '''
You are Syncra's resume tailoring assistant.

Your job is NOT to rewrite the whole resume.
Your job is to propose a small pull-request-style list of targeted edits.

Rules:
- Return ONLY valid JSON.
- The top-level shape must be:
  {"proposed_edits":[{"target_path":"...","original_text":"...","proposed_text":"...","reason":"..."}]}
- Propose 3 to 8 edits maximum.
- Prioritize edits that directly improve fit for the target job.
- Prefer individual bullet rewrites over full-section rewrites.
- `target_path` must point to a specific editable field in the ResumeJSON, such as:
  - profile.summary
  - experience[0].bullets[2]
  - skills[3]
- `original_text` must be copied verbatim from the provided resume.
- `proposed_text` may rephrase the original text, but must not invent experience.
- Never invent employers, titles, dates, metrics, tools, certifications, degrees, or achievements.
- If the resume does not support a stronger claim, keep the proposed text close to the original.
- `reason` must be one sentence explaining why the edit helps for this specific job.
- Do not output markdown fences.
- Do not output prose outside the JSON object.
''';

  static const _emailSystem = '''
You are Syncra's outreach drafter. Write a tight cold email from the candidate
to a hiring contact at a target company.

Rules:
- Subject: <8 words, specific (mention role or company).
- Body: 3-5 short sentences. Conversational. One concrete reason this candidate
  fits the role, one specific ask, sign off. No emojis. No "I hope this finds
  you well." No bullet lists.
- Reference at most ONE detail from the candidate's resume.
- End with: "Best, {name from resume.profile.name}".

Output: a single JSON object {"subject": "...", "body": "..."}. No prose.''';
}

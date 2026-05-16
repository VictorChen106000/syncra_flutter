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

  final String _apiKey;
  final http.Client _client;
  final String model;

  bool get hasApiKey => _apiKey.isNotEmpty;

  /// Returns a tailored `ResumeJSON` with the same shape as the input.
  /// Only `summary`, `experience[].bullets`, and `skills` order may change.
  Future<Map<String, dynamic>> tailorResume({
    required Map<String, dynamic> resumeJson,
    required Job job,
  }) async {
    final response = await _call(
      system: _tailorSystem,
      user: '''
Resume (JSON):
${const JsonEncoder.withIndent('  ').convert(resumeJson)}

Target job:
- title: ${job.title}
- company: ${job.company}
- location: ${job.location}
- description: ${job.why}

Return ONLY the tailored ResumeJSON, no prose.''',
      maxTokens: 1200,
    );
    final cleaned = _stripFences(response);
    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('tailorResume parse failed: $e\nRaw: $response');
      throw Exception('Could not parse tailored resume JSON.');
    }
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
    final response = await _client
        .post(
          Uri.parse(_endpoint),
          headers: {
            'content-type': 'application/json',
            'x-api-key': _apiKey,
            'anthropic-version': _version,
            'anthropic-dangerous-direct-browser-access': 'true',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': maxTokens,
            'system': system,
            'messages': [
              {'role': 'user', 'content': user},
            ],
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      throw Exception(_extractError(response.body, response.statusCode));
    }
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

  static const _tailorSystem = '''
You are Syncra's resume tailor. Given a ResumeJSON and a target job, return
a tailored ResumeJSON with the SAME SHAPE as the input.

Rules:
- Keep all keys and structure identical to the input.
- Rewrite `profile.summary` to lead with traits the job description emphasizes.
- Reorder `skills` so the matching ones appear first.
- For `experience[]` (if present), rewrite `bullets` to surface keywords from
  the job — but NEVER invent experience, NEVER fabricate companies, dates, or
  outcomes. If a bullet has nothing to lean on, leave it close to original.
- Do not add new sections. Do not output any prose or markdown fences.

Output: a single JSON object matching the input ResumeJSON schema.''';

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

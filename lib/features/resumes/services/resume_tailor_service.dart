import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../data/models/job.dart';
import '../../../data/services/anthropic_client.dart';
import '../models/resume_json.dart';

/// Sends a structured [ResumeJson] + job description to Claude and returns
/// a tailored [ResumeJson] (same shape, rewritten bullets, reordered skills).
///
/// Transport lives in the shared [AnthropicClient]; the response is constrained
/// to [ResumeJson.outputSchema] via structured outputs, so the tailored resume
/// always comes back as valid JSON of the same shape — no markdown fences and
/// no malformed-JSON retry.
class ResumeTailorService {
  ResumeTailorService({
    AnthropicClient? client,
    this.model = 'claude-haiku-4-5-20251001',
  }) : _client = client ?? AnthropicClient();

  final AnthropicClient _client;
  final String model;

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
project facts, links, certifications.''';

  bool get hasApiKey => _client.hasApiKey;

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

    final response = await _client.createMessage({
      'model': model,
      // Headroom for a full resume; structured outputs makes a truncation a
      // hard failure (invalid JSON), so give the model room to finish.
      'max_tokens': 4096,
      'system': _system,
      'output_config': {
        'format': {'type': 'json_schema', 'schema': ResumeJson.outputSchema},
      },
      'messages': [
        {'role': 'user', 'content': userPrompt},
      ],
    });

    final text = AnthropicClient.textOf(response);
    if (text.isEmpty) {
      throw const ResumeTailorException('Anthropic returned no content.');
    }
    return _parseJsonResponse(text);
  }

  ResumeJson _parseJsonResponse(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ResumeJson.fromJson(map);
    } catch (e) {
      // Structured outputs guarantees schema-valid JSON on a normal stop;
      // this only fires on a refusal or a max_tokens truncation.
      debugPrint('Could not parse Claude tailor JSON: $e\nRaw: $raw');
      throw const ResumeTailorException(
        'Resume tailor returned invalid JSON.',
      );
    }
  }

  void dispose() => _client.dispose();
}

class ResumeTailorException implements Exception {
  const ResumeTailorException(this.message);
  final String message;
  @override
  String toString() => 'ResumeTailorException: $message';
}

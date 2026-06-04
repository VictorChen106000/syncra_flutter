import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../data/services/anthropic_client.dart';
import '../models/resume_json.dart';

/// Calls Claude to convert raw PDF text into a structured [ResumeJson].
/// Lazy by design — only invoked the first time an agent feature needs
/// structured data. Result is cached back to Firestore by the caller.
///
/// Transport lives in the shared [AnthropicClient]; the response is constrained
/// to [ResumeJson.outputSchema] via structured outputs. If the model or
/// transport still returns malformed JSON, the parser retries once with a
/// stricter prompt before surfacing an actionable parse error.
class ResumeParserService {
  ResumeParserService({
    AnthropicClient? client,
    // Parsing a full resume into structured JSON without dropping a section or
    // merging coursework bullets is precise instruction-following — Haiku
    // routinely slips here. Sonnet is the floor for this, and the result is
    // cached, so the stronger parse is paid for once per resume.
    this.model = 'claude-sonnet-4-6',
  }) : _client = client ?? AnthropicClient();

  final AnthropicClient _client;
  final String model;

  static const _system = '''
You are a resume parser. Convert the user's raw resume text into a single
JSON object matching the provided schema (header, summary, experience,
education, projects, certifications, skill_groups).

Rules:
- Capture EVERY section the resume contains. Never drop content. If text
  doesn't fit experience/education/projects, it almost always belongs in
  `certifications` (certificates, scholarships, awards, language tests like
  IELTS/TOEFL) — put it there rather than discarding it.
- Preserve the original wording of bullets — do not paraphrase or condense.
- If a field is missing in the resume, omit it (don't invent placeholders).
- Use "Present" for ongoing roles' `end` field.
- education[].bullets: each sub-point under a degree (special programs, honors,
  relevant coursework) is its own bullet — do not merge them into `details`.
- header: split contact links by kind — GitHub URLs go in `github`, a
  personal/portfolio site in `website`, an X/Twitter handle in `twitter`,
  LinkedIn in `linkedin`.
- skill_groups: keep the resume's own categories (e.g. "Languages",
  "Tools & Frameworks"). If skills are listed flat with no categories, infer
  sensible groups for the candidate's field — for engineers usually
  "Languages" and "Tools & Frameworks"; for non-technical roles a single
  "Skills" or "Tools" group is fine. Deduplicate items, preserve original
  casing.
''';

  bool get hasApiKey => _client.hasApiKey;

  /// Parses [rawText] into a [ResumeJson]. Throws on transport/API failure.
  /// Returns `null` when no API key is configured — caller should fall
  /// back gracefully.
  Future<ResumeJson?> parse(String rawText) async {
    if (!hasApiKey) return null;
    final cleanText = rawText.trim();
    if (cleanText.isEmpty) {
      throw const ResumeParseException(
        "Couldn't read any text from the PDF. It may be a scanned image.",
      );
    }

    final response = await _client.createMessage(_buildParsePayload(cleanText));
    final text = AnthropicClient.textOf(response);
    if (text.isEmpty) {
      throw const ResumeParseException('Anthropic returned no content.');
    }

    try {
      return _parseJsonResponse(text);
    } on ResumeParseException {
      debugPrint('Resume parser returned invalid JSON — retrying once.');
    }

    final retryResponse = await _client.createMessage(
      _buildParsePayload(cleanText, strictRetry: true),
    );
    final retryText = AnthropicClient.textOf(retryResponse);
    if (retryText.isEmpty) {
      throw const ResumeParseException('Anthropic returned no content.');
    }

    return _parseJsonResponse(retryText);
  }

  Map<String, dynamic> _buildParsePayload(
    String rawText, {
    bool strictRetry = false,
  }) {
    final userPrompt = strictRetry
        ? 'Your previous response was not valid ResumeJSON. Return ONLY the '
              'raw JSON object matching the schema. Do not use markdown fences '
              'or commentary.\n\nParse this resume text:\n\n$rawText'
        : 'Parse this resume text:\n\n$rawText';

    return {
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
    };
  }

  ResumeJson _parseJsonResponse(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ResumeJson.fromJson(map);
    } catch (e) {
      // Structured outputs guarantees schema-valid JSON on a normal stop;
      // this only fires on a refusal or a max_tokens truncation.
      debugPrint('Could not parse Claude resume JSON: $e\nRaw: $raw');
      throw const ResumeParseException('Resume parser returned invalid JSON.');
    }
  }

  void dispose() => _client.dispose();
}

class ResumeParseException implements Exception {
  const ResumeParseException(this.message);
  final String message;
  @override
  String toString() => 'ResumeParseException: $message';
}

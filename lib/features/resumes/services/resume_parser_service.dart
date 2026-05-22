import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/resume_json.dart';

/// Calls Claude to convert raw PDF text into a structured [ResumeJson].
/// Lazy by design — only invoked the first time an agent feature needs
/// structured data. Result is cached back to Firestore by the caller.
class ResumeParserService {
  ResumeParserService({
    String? apiKey,
    http.Client? client,
    this.model = 'claude-haiku-4-5-20251001',
  })  : _apiKey = apiKey ?? const String.fromEnvironment('ANTHROPIC_API_KEY'),
        _client = client ?? http.Client();

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _version = '2023-06-01';

  static const _system = '''
You are a resume parser. Convert the user's raw resume text into a single
JSON object matching this schema:

{
  "header": {
    "name": string,
    "email": string?, "phone": string?, "location": string?,
    "linkedin": string?, "website": string?
  },
  "summary": string?,
  "experience": [
    { "company": string, "role": string, "start": string, "end": string?,
      "location": string?, "bullets": string[] }
  ],
  "education": [
    { "school": string, "degree": string, "start": string?, "end": string?,
      "details": string? }
  ],
  "skills": string[],
  "projects": [
    { "name": string, "description": string?, "bullets": string[], "link": string? }
  ]
}

Rules:
- Return ONLY the JSON object. No prose, no markdown fences, no commentary.
- Preserve the original wording of bullets — do not paraphrase or condense.
- If a field is missing in the resume, omit it (don't invent placeholders).
- Use "Present" for ongoing roles' `end` field.
- Skills: deduplicate, preserve original casing.
''';

  final String _apiKey;
  final http.Client _client;
  final String model;

  bool get hasApiKey => _apiKey.isNotEmpty;

  /// Parses [rawText] into a [ResumeJson]. Throws on transport/API failure.
  /// Returns `null` when no API key is configured — caller should fall
  /// back gracefully.
  Future<ResumeJson?> parse(String rawText) async {
    if (!hasApiKey) return null;
    if (rawText.trim().isEmpty) {
      throw const ResumeParseException(
        "Couldn't read any text from the PDF. It may be a scanned image.",
      );
    }

    final text = await _callClaude(rawText, strict: false);
    try {
      return _parseJsonResponse(text);
    } on ResumeParseException {
      // The model returned malformed JSON — retry once with a stricter
      // instruction before surfacing the failure.
      debugPrint('resume parse JSON malformed — retrying once (strict)');
      final retry = await _callClaude(rawText, strict: true);
      return _parseJsonResponse(retry);
    }
  }

  /// Single Anthropic call returning the concatenated text content. When
  /// [strict] is set, prepends an instruction emphasizing raw-JSON-only
  /// output — used for the one retry after a malformed-JSON response.
  Future<String> _callClaude(String rawText, {required bool strict}) async {
    final userText = strict
        ? 'Your previous response was not valid JSON. Return ONLY the raw '
            'JSON object — no markdown fences, no commentary, no text before '
            'or after it.\n\nParse this resume text:\n\n$rawText'
        : 'Parse this resume text:\n\n$rawText';

    final payload = {
      'model': model,
      'max_tokens': 2048,
      'system': _system,
      'messages': [
        {'role': 'user', 'content': userText},
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
      throw ResumeParseException(_extractError(response.body, response.statusCode));
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
      throw const ResumeParseException('Anthropic returned no content.');
    }
    return text;
  }

  ResumeJson _parseJsonResponse(String raw) {
    final cleaned = _stripFences(raw);
    try {
      final map = jsonDecode(cleaned) as Map<String, dynamic>;
      return ResumeJson.fromJson(map);
    } catch (e) {
      debugPrint('Could not parse Claude resume JSON: $e\nRaw: $raw');
      throw const ResumeParseException('Resume parser returned invalid JSON.');
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

class ResumeParseException implements Exception {
  const ResumeParseException(this.message);
  final String message;
  @override
  String toString() => 'ResumeParseException: $message';
}

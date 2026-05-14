import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../data/models/job.dart';

/// Result from a single matcher call: category + score + 1-sentence
/// justification + missing skills list. Mirrors the backend Haiku
/// matcher's tool-use schema described in `backend/README.md`.
class MatcherResult {
  const MatcherResult({
    required this.jobId,
    required this.category,
    required this.matchScore,
    required this.justification,
    required this.missingSkills,
  });

  final String jobId;
  final JobCategory category;
  final int matchScore;
  final String justification;
  final List<String> missingSkills;
}

class AnthropicException implements Exception {
  AnthropicException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AnthropicException($statusCode): $message';
}

/// Thin HTTP client for Anthropic's Messages API.
///
/// Reads the API key from `--dart-define=ANTHROPIC_API_KEY=sk-ant-…`.
/// Returns `null` from [scoreJobs] when no key is configured so the caller
/// can fall back to mock-only behavior.
///
/// Security note: in production, route this through your backend so the
/// key never ships to the client. This client-side path is for the
/// school-project demo only.
class AnthropicService {
  AnthropicService({
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

  /// Asks Claude to score each candidate job against the given resume.
  ///
  /// Returns a list aligned with `jobs` (one [MatcherResult] per input job).
  /// Returns `null` when no API key is set — caller should fall back to
  /// mock data.
  Future<List<MatcherResult>?> scoreJobs({
    required Map<String, dynamic> resume,
    required List<Job> jobs,
  }) async {
    if (!hasApiKey) return null;
    if (jobs.isEmpty) return [];

    final payload = {
      'model': model,
      'max_tokens': 1024,
      'system': _systemPrompt,
      'messages': [
        {
          'role': 'user',
          'content': _buildUserPrompt(resume: resume, jobs: jobs),
        },
      ],
    };

    final response = await _client
        .post(
          Uri.parse(_endpoint),
          headers: {
            'content-type': 'application/json',
            'x-api-key': _apiKey,
            'anthropic-version': _version,
            // Required for direct browser calls (web). Harmless elsewhere.
            'anthropic-dangerous-direct-browser-access': 'true',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw AnthropicException(
        _extractError(response.body),
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content = decoded['content'] as List?;
    if (content == null || content.isEmpty) {
      throw AnthropicException('Anthropic returned no content.');
    }

    final textBlock = content
        .whereType<Map<String, dynamic>>()
        .firstWhere((b) => b['type'] == 'text', orElse: () => const {});
    final text = textBlock['text'] as String? ?? '';
    return _parseMatcherJson(text, jobs);
  }

  static const String _systemPrompt = '''
You are Syncra's job matcher. Score each candidate job against the user's resume.

For every job, respond with:
- category: one of "ready" (90%+ fit, no major gaps), "input_needed" (strong but missing a specific skill or signal), or "exploration" (interesting stretch / strategic pivot worth exploring).
- match_score: integer 0-100. Used only for sort order, never shown to the user.
- justification: ONE short sentence in second person, written like a teammate explaining the call.
- missing_skills: array of strings if category is "input_needed" or there are clear gaps, else empty.

Reply with ONLY a single JSON object of the shape:
{"results": [{"job_id": "...", "category": "...", "match_score": 0, "justification": "...", "missing_skills": []}, ...]}

No prose, no markdown fences, no extra keys.
''';

  String _buildUserPrompt({
    required Map<String, dynamic> resume,
    required List<Job> jobs,
  }) {
    final resumeJson = const JsonEncoder.withIndent('  ').convert(resume);
    final jobLines = jobs.map((j) {
      return '- id: ${j.id}\n  title: ${j.title}\n  company: ${j.company}\n  location: ${j.location}\n  salary: ${j.salary}\n  required_skills: ${j.skills.join(', ')}';
    }).join('\n');

    return '''
Resume (JSON):
$resumeJson

Candidate jobs:
$jobLines

Score every job. Return the JSON object described in the system prompt.''';
  }

  List<MatcherResult> _parseMatcherJson(String text, List<Job> jobs) {
    final cleaned = _stripMarkdownFences(text);
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Failed to parse Anthropic JSON: $e\nRaw: $text');
      throw AnthropicException('Could not parse matcher response.');
    }

    final raw = parsed['results'] as List? ?? const [];
    final byId = {for (final j in jobs) j.id: j};
    final results = <MatcherResult>[];

    for (final item in raw.whereType<Map<String, dynamic>>()) {
      final id = item['job_id']?.toString() ?? '';
      if (!byId.containsKey(id)) continue;
      results.add(
        MatcherResult(
          jobId: id,
          category: _categoryFrom(item['category']?.toString()),
          matchScore: (item['match_score'] as num?)?.toInt() ?? 0,
          justification: (item['justification'] as String?)?.trim() ?? '',
          missingSkills: (item['missing_skills'] as List? ?? [])
              .map((e) => e.toString())
              .toList(),
        ),
      );
    }

    return results;
  }

  String _stripMarkdownFences(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('```')) {
      final firstNewline = trimmed.indexOf('\n');
      final stripped = firstNewline == -1
          ? trimmed.substring(3)
          : trimmed.substring(firstNewline + 1);
      final end = stripped.lastIndexOf('```');
      return end == -1 ? stripped.trim() : stripped.substring(0, end).trim();
    }
    return trimmed;
  }

  JobCategory _categoryFrom(String? value) {
    switch (value) {
      case 'ready':
        return JobCategory.ready;
      case 'input_needed':
        return JobCategory.inputNeeded;
      case 'exploration':
        return JobCategory.exploration;
      default:
        return JobCategory.exploration;
    }
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      return error?['message']?.toString() ?? body;
    } catch (_) {
      return body;
    }
  }

  void dispose() {
    _client.close();
  }
}

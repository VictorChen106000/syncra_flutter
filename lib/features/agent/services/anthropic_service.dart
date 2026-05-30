import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../data/models/job.dart';
import '../../../data/services/anthropic_client.dart';

export '../../../data/services/anthropic_client.dart' show AnthropicException;

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

/// Scores candidate jobs against a resume via Anthropic's Messages API.
///
/// Transport (auth, retries, error handling) lives in the shared
/// [AnthropicClient]; this service owns the matcher prompt and the structured
/// output schema. Returns `null` from [scoreJobs] when no key is configured so
/// the caller can fall back to mock-only behavior.
class AnthropicService {
  AnthropicService({
    AnthropicClient? client,
    this.model = 'claude-haiku-4-5-20251001',
  }) : _client = client ?? AnthropicClient(timeout: const Duration(seconds: 30));

  final AnthropicClient _client;
  final String model;

  bool get hasApiKey => _client.hasApiKey;

  /// Structured-output schema: a `results` array of per-job scores. Enforced
  /// via `output_config.format`, so the model can only return valid,
  /// parseable JSON of exactly this shape — no prose, no markdown fences.
  static const Map<String, dynamic> _outputSchema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['results'],
    'properties': {
      'results': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'job_id',
            'category',
            'match_score',
            'justification',
            'missing_skills',
          ],
          'properties': {
            'job_id': {'type': 'string'},
            'category': {
              'type': 'string',
              'enum': ['ready', 'input_needed', 'exploration'],
            },
            'match_score': {'type': 'integer'},
            'justification': {'type': 'string'},
            'missing_skills': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
        },
      },
    },
  };

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

    final response = await _client.createMessage({
      'model': model,
      'max_tokens': 1024,
      'system': _systemPrompt,
      'output_config': {
        'format': {'type': 'json_schema', 'schema': _outputSchema},
      },
      'messages': [
        {
          'role': 'user',
          'content': _buildUserPrompt(resume: resume, jobs: jobs),
        },
      ],
    });

    final text = AnthropicClient.textOf(response);
    if (text.isEmpty) {
      throw AnthropicException('Anthropic returned no content.');
    }
    return _parseMatcherJson(text, jobs);
  }

  static const String _systemPrompt = '''
You are Syncra's job matcher. Score each candidate job against the user's resume.

For every job, return:
- category: one of "ready" (90%+ fit, no major gaps), "input_needed" (strong but missing a specific skill or signal), or "exploration" (interesting stretch / strategic pivot worth exploring).
- match_score: integer 0-100. Used only for sort order, never shown to the user.
- justification: ONE short sentence in second person, written like a teammate explaining the call.
- missing_skills: array of strings if category is "input_needed" or there are clear gaps, else empty.

Return one result object per candidate job, carrying that job's job_id verbatim.
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

Score every job and return the results array.''';
  }

  List<MatcherResult> _parseMatcherJson(String text, List<Job> jobs) {
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(text) as Map<String, dynamic>;
    } catch (e) {
      // Structured outputs guarantees schema-valid JSON on a normal stop;
      // this only fires on a refusal or a max_tokens truncation.
      debugPrint('Failed to parse matcher JSON: $e\nRaw: $text');
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

  void dispose() => _client.dispose();
}

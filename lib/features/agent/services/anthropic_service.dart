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
    required this.matchedSkills,
    required this.missingSkills,
    this.needsReview = false,
  });

  final String jobId;
  final JobCategory category;
  final int matchScore;
  final String justification;
  final List<String> matchedSkills;
  final List<String> missingSkills;

  /// True when scoring fell back (the model's reply couldn't be parsed or the
  /// request failed). The job still surfaces, just labelled "Needs review"
  /// instead of vanishing behind a system error.
  final bool needsReview;

  /// The only match signal ever shown to the user — purely qualitative, never
  /// a number. [matchScore] stays internal for sort/legacy only.
  String get matchLabel {
    if (needsReview) return 'Needs review';
    return switch (category) {
      JobCategory.ready => 'Strong match',
      JobCategory.inputNeeded => 'Partial match',
      JobCategory.exploration => 'Possible match',
    };
  }
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
  }) : _apiKey = apiKey ?? const String.fromEnvironment('ANTHROPIC_API_KEY'),
       _client = client ?? http.Client();

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _version = '2023-06-01';

  /// Per-request retry budget for transient API failures (429 / 5xx / 529).
  /// Four attempts → three backoff retries (~1s/2s/4s) before failing, so an
  /// "Overloaded" blip doesn't surface as a failed job-match pass.
  static const _maxApiAttempts = 4;

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

    // 2048 (up from 1024): with several jobs each needing a category +
    // justification + missing-skills array, 1024 tokens truncated the JSON
    // mid-array — the root cause of "Could not parse matcher response".
    final body = jsonEncode({
      'model': model,
      'max_tokens': 2048,
      'system': _systemPrompt,
      'messages': [
        {
          'role': 'user',
          'content': _buildUserPrompt(resume: resume, jobs: jobs),
        },
      ],
    });

    // Scoring must never surface as a hard failure to the user. Any error
    // (network, truncation, unparseable reply) degrades to a "Needs review"
    // result per job so the jobs still appear and the chat reads like a
    // normal answer, not a red system error.
    try {
      final response = await _postWithRetry(body);

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final content = decoded['content'] as List?;
      if (content == null || content.isEmpty) {
        return _needsReviewFallback(jobs);
      }

      final textBlock = content.whereType<Map<String, dynamic>>().firstWhere(
        (b) => b['type'] == 'text',
        orElse: () => const {},
      );
      final text = textBlock['text'] as String? ?? '';
      return _parseMatcherJson(text, jobs);
    } catch (e) {
      debugPrint('scoreJobs failed → needs-review fallback: $e');
      return _needsReviewFallback(jobs);
    }
  }

  /// POSTs [body] to Anthropic, retrying transient failures (429 / 5xx /
  /// 529 "Overloaded" / timeouts) up to [_maxApiAttempts] times with ~1s/2s/4s
  /// backoff. A 200 returns immediately; permanent errors (auth, bad request)
  /// fail without retrying.
  Future<http.Response> _postWithRetry(String body) async {
    Object lastError = AnthropicException('Anthropic request failed.');
    for (var attempt = 1; attempt <= _maxApiAttempts; attempt++) {
      try {
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
              body: body,
            )
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) return response;

        final error = AnthropicException(
          _extractError(response.body),
          statusCode: response.statusCode,
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
          throw AnthropicException(
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

  static const String _systemPrompt = '''
You are Syncra's job matcher. Score each candidate job against the user's resume.

For every job, respond with:
- category: one of "ready" (90%+ fit, no major gaps), "input_needed" (strong but missing a specific skill or signal), or "exploration" (interesting stretch / strategic pivot worth exploring).
- match_score: integer 0-100. Used only for sort order, never shown to the user.
- justification: ONE short sentence in second person, written like a teammate explaining the call. Mention the strongest resume/job overlap, not generic praise.
- matched_skills: 1-4 concrete skills, experiences, tools, or domain signals from the resume that connect to this job. Use an empty array only when there is no clear overlap.
- missing_skills: array of strings if category is "input_needed" or there are clear gaps, else empty.

Reply with ONLY a single JSON object of the shape:
{"results": [{"job_id": "...", "category": "...", "match_score": 0, "justification": "...", "matched_skills": [], "missing_skills": []}, ...]}

No prose, no markdown fences, no extra keys.
''';

  String _buildUserPrompt({
    required Map<String, dynamic> resume,
    required List<Job> jobs,
  }) {
    final resumeJson = const JsonEncoder.withIndent('  ').convert(resume);
    final jobLines = jobs
        .map((j) {
          final requiredSkills = j.skills
              .map((skill) => skill.trim())
              .where((skill) => skill.isNotEmpty)
              .join(', ');
          final description = j.why.trim();
          return '- id: ${j.id}\n'
              '  title: ${j.title}\n'
              '  company: ${j.company}\n'
              '  location: ${j.location}\n'
              '  salary: ${j.salary}\n'
              '  required_skills: ${requiredSkills.isEmpty ? 'Not specified' : requiredSkills}\n'
              '  description: ${description.isEmpty ? 'Not provided' : description}';
        })
        .join('\n');

    return '''
  Resume (JSON):
  $resumeJson

  Candidate jobs:
  $jobLines

  Score every job. Return the JSON object described in the system prompt.''';
  }

  List<MatcherResult> _parseMatcherJson(String text, List<Job> jobs) {
    final parsed = _extractJsonObject(text);
    if (parsed == null) {
      debugPrint(
        'matcher: unparseable reply → needs-review fallback\nRaw: $text',
      );
      return _needsReviewFallback(jobs);
    }

    final raw = parsed['results'] as List? ?? const [];
    final byId = {for (final j in jobs) j.id: j};
    final results = <MatcherResult>[];
    final seen = <String>{};

    for (final item in raw.whereType<Map<String, dynamic>>()) {
      final id = item['job_id']?.toString() ?? '';
      if (!byId.containsKey(id) || seen.contains(id)) continue;
      seen.add(id);
      results.add(
        MatcherResult(
          jobId: id,
          category: _categoryFrom(item['category']?.toString()),
          matchScore: (item['match_score'] as num?)?.toInt() ?? 0,
          justification: (item['justification'] as String?)?.trim() ?? '',
          matchedSkills: _stringList(item['matched_skills']),
          missingSkills: _stringList(item['missing_skills']),
        ),
      );
    }

    // Any job the model dropped comes back as "Needs review" rather than
    // silently disappearing from the results table.
    for (final job in jobs) {
      if (!seen.contains(job.id)) results.add(_needsReviewResult(job));
    }

    if (results.isEmpty) return _needsReviewFallback(jobs);
    return results;
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  /// Every job, labelled "Needs review" — the graceful degrade when scoring
  /// can't run or the reply can't be parsed. Keeps the jobs visible instead
  /// of replacing the whole result with a system error.
  List<MatcherResult> _needsReviewFallback(List<Job> jobs) =>
      jobs.map(_needsReviewResult).toList();

  MatcherResult _needsReviewResult(Job job) => MatcherResult(
    jobId: job.id,
    category: JobCategory.inputNeeded,
    matchScore: 0,
    justification:
        "Couldn't score this one automatically — worth a quick review.",
    matchedSkills: const [],
    missingSkills: const [],
    needsReview: true,
  );

  /// Best-effort decode of the matcher's reply into a JSON object. Strips
  /// markdown fences first; if a straight decode fails (stray prose or a
  /// trailing truncation) it retries on the substring between the first `{`
  /// and the last `}`. Returns null only when nothing parseable remains.
  Map<String, dynamic>? _extractJsonObject(String text) {
    final cleaned = _stripMarkdownFences(text);
    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      // fall through to substring extraction
    }
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    try {
      return jsonDecode(cleaned.substring(start, end + 1))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
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

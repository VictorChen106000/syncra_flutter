import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/job.dart';
import 'syncra_proxy.dart';

/// Live job search via JSearch (RapidAPI).
///
/// Ported from the backend's `app/jobs/sources.py`: fetch → normalize →
/// dedupe → upsert into the global `jobs/` collection → return [Job]s.
///
/// Requests go through the [SyncraProxy] Cloud Function, which holds the
/// RapidAPI key server-side and authenticates the caller by Firebase ID token,
/// so no key ships in the client. [hasApiKey] reports whether the real backend
/// should be used (false only with `--dart-define=SYNCRA_USE_MOCKS=true`) so
/// callers can fall back to the seeded `jobs/` collection offline.
class JSearchService {
  JSearchService({
    String? apiKey,
    http.Client? client,
    FirebaseFirestore? firestore,
  }) : _apiKey = apiKey ?? const String.fromEnvironment('RAPIDAPI_KEY'),
       _client = client ?? http.Client(),
       _db = firestore ?? FirebaseFirestore.instance;

  /// Legacy direct key — never sent (the proxy injects the real key). Kept only
  /// so a dart-define key still flips [hasApiKey].
  final String _apiKey;
  final http.Client _client;
  final FirebaseFirestore _db;

  /// JSearch's free tier is 200 requests/month — cache aggressively so dev
  /// and the demo stay well under quota.
  static const Duration _cacheTtl = Duration(hours: 1);

  /// JSearch returns 10KB+ descriptions; we only need a preview.
  static const int _maxDescriptionChars = 240;

  static const Duration _httpTimeout = Duration(seconds: 15);

  final Map<String, _CacheEntry> _cache = {};

  bool get hasApiKey => SyncraProxy.enabled || _apiKey.isNotEmpty;

  /// Searches JSearch, upserts results into `jobs/`, and returns the [Job]s.
  ///
  /// Repeated calls with the same `(query, location, limit)` within
  /// [_cacheTtl] are served from memory and never hit RapidAPI.
  ///
  /// Throws [JSearchException] on a missing key or a network/API failure so
  /// the caller can decide whether to surface the error or fall back.
  Future<List<Job>> search({
    required String query,
    String? location,
    int limit = 10,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];
    if (!hasApiKey) {
      throw JSearchException('RAPIDAPI_KEY not configured.');
    }
    final cappedLimit = limit.clamp(1, 25);

    final key = _cacheKey(cleanQuery, location, cappedLimit);
    final cached = _cache[key];
    if (cached != null && !cached.isStale) {
      debugPrint('JSearchService: cache hit for "$cleanQuery"');
      return cached.jobs;
    }

    final rawJobs = await _fetch(cleanQuery, location, cappedLimit);

    // Dedupe by deterministic id — JSearch occasionally returns the same
    // posting twice with different apply links.
    final seen = <String>{};
    final jobs = <Job>[];
    for (final raw in rawJobs) {
      final job = _jsearchToJob(raw);
      if (job == null || !seen.add(job.id)) continue;
      jobs.add(job);
    }

    await _upsert(jobs);
    _cache[key] = _CacheEntry(jobs);
    debugPrint('JSearchService: fetched ${jobs.length} jobs for "$cleanQuery"');
    return jobs;
  }

  Future<List<Map<String, dynamic>>> _fetch(
    String query,
    String? location,
    int limit,
  ) async {
    // Location is no longer folded into the query text ("... in Remote" was an
    // unnatural phrase that collapsed JSearch relevance to a handful of hits).
    // A remote location maps to JSearch's dedicated `remote_jobs_only` flag;
    // any other location is left to the catalogue fallback's local filtering.
    final loc = location?.trim().toLowerCase() ?? '';
    final remoteOnly = loc.contains('remote');
    final uri = SyncraProxy.jsearch.replace(
      queryParameters: {
        'query': query,
        'page': '1',
        'num_pages': '2',
        'date_posted': 'month',
        if (remoteOnly) 'remote_jobs_only': 'true',
      },
    );

    final http.Response response;
    try {
      final headers = await SyncraProxy.authHeaders();
      response = await _client.get(uri, headers: headers).timeout(_httpTimeout);
    } catch (e) {
      throw JSearchException('JSearch request failed: $e');
    }

    if (response.statusCode != 200) {
      throw JSearchException(
        'JSearch returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw JSearchException('Could not parse the JSearch response.');
    }

    final data = (body['data'] as List?) ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .take(limit)
        .toList(growable: false);
  }

  /// Maps one raw JSearch record to our [Job]. Returns null when it lacks
  /// the fields we need to dedupe or display it.
  Job? _jsearchToJob(Map<String, dynamic> raw) {
    final title = (raw['job_title'] as String?)?.trim() ?? '';
    final company = (raw['employer_name'] as String?)?.trim() ?? '';
    final sourceUrl =
        ((raw['job_apply_link'] ?? raw['job_google_link']) as String?)
            ?.trim() ??
        '';
    if (title.isEmpty || company.isEmpty || sourceUrl.isEmpty) return null;

    return Job(
      id: _jobIdFor(title, company, sourceUrl),
      title: title,
      company: company,
      location: _location(raw),
      salary: _salary(raw),
      category: JobCategory.exploration,
      matchScore: 0,
      agentAction: '',
      agentJustification: '',
      skills: const [],
      missingSkills: const [],
      why: _description(raw),
      employerWebsite: (raw['employer_website'] as String?)?.trim() ?? '',
    );
  }

  String _location(Map<String, dynamic> raw) {
    final parts = [raw['job_city'], raw['job_state'], raw['job_country']]
        .whereType<String>()
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final joined = parts.join(', ');
    if (raw['job_is_remote'] == true) {
      return joined.isEmpty ? 'Remote' : 'Remote — $joined';
    }
    return joined;
  }

  String _salary(Map<String, dynamic> raw) {
    final min = (raw['job_min_salary'] as num?)?.round();
    final max = (raw['job_max_salary'] as num?)?.round();
    if (min == null || max == null) return '';
    final range = '\$${_thousands(min)}-\$${_thousands(max)}';
    final period = (raw['job_salary_period'] as String?)?.toLowerCase();
    return (period == null || period.isEmpty) ? range : '$range/$period';
  }

  String _thousands(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _description(Map<String, dynamic> raw) {
    final desc = (raw['job_description'] as String?)?.trim() ?? '';
    if (desc.length <= _maxDescriptionChars) return desc;
    return '${desc.substring(0, _maxDescriptionChars)}…';
  }

  /// Deterministic id so the same posting re-discovered later collapses
  /// onto one Firestore doc instead of duplicating. Mirrors the backend's
  /// `_job_id_for()` scheme.
  String _jobIdFor(String title, String company, String sourceUrl) {
    final raw =
        '${title.toLowerCase().trim()}|'
        '${company.toLowerCase().trim()}|'
        '${sourceUrl.toLowerCase().trim()}';
    final digest = sha256.convert(utf8.encode(raw)).toString();
    return 'job_${digest.substring(0, 20)}';
  }

  String _cacheKey(String query, String? location, int limit) {
    final raw =
        '${query.toLowerCase()}|'
        '${(location ?? '').toLowerCase().trim()}|$limit';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 16);
  }

  /// Upserts each job into the global `jobs/` collection with `merge: true`
  /// so a re-discovery refreshes the posting without clobbering any
  /// agent-written fields. Failures here never fail the search itself —
  /// the upsert is just cache-warming.
  Future<void> _upsert(List<Job> jobs) async {
    if (jobs.isEmpty) return;
    try {
      final batch = _db.batch();
      for (final job in jobs) {
        batch.set(_db.collection('jobs').doc(job.id), {
          'title': job.title,
          'company': job.company,
          'location': job.location,
          'salary': job.salary,
          'description': job.why,
          'employer_website': job.employerWebsite,
          'source': 'jsearch',
          'discovered_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (e) {
      debugPrint('JSearchService: jobs/ upsert failed (ignored): $e');
    }
  }

  void dispose() => _client.close();
}

class _CacheEntry {
  _CacheEntry(this.jobs) : fetchedAt = DateTime.now();

  final List<Job> jobs;
  final DateTime fetchedAt;

  bool get isStale =>
      DateTime.now().difference(fetchedAt) > JSearchService._cacheTtl;
}

/// Raised when a JSearch request cannot be completed.
class JSearchException implements Exception {
  JSearchException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'JSearchException($statusCode): $message';
}

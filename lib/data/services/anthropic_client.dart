import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'syncra_proxy.dart';

/// Thrown when an Anthropic Messages API request fails — a non-200 status that
/// isn't retryable, or a transient failure that exhausted its retry budget.
class AnthropicException implements Exception {
  AnthropicException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AnthropicException($statusCode): $message';
}

/// Shared transport for the Anthropic Messages API.
///
/// Owns the endpoint, version header, API-key resolution, and the
/// retry/backoff loop, so the feature services (job matcher, agent chat,
/// resume parser, resume tailor) only build request payloads and parse
/// responses instead of each re-implementing HTTP plumbing.
///
/// Requests are routed through the [SyncraProxy] Cloud Function, which holds
/// the real key server-side and authenticates the caller by Firebase ID token,
/// so no API key ships in the client. [hasApiKey] reports whether the real
/// backend should be used (false only with `--dart-define=SYNCRA_USE_MOCKS=true`)
/// so callers can fall back to mock-only behavior offline.
class AnthropicClient {
  AnthropicClient({
    String? apiKey,
    http.Client? client,
    this.maxAttempts = 4,
    this.timeout = const Duration(seconds: 45),
  })  : _apiKey = apiKey ?? const String.fromEnvironment('ANTHROPIC_API_KEY'),
        _client = client ?? http.Client();

  /// Legacy direct key. Kept only so tests can flag a configured client and so
  /// a dart-define key still flips [hasApiKey]; it is never sent — the proxy
  /// injects the real key server-side.
  final String _apiKey;
  final http.Client _client;

  /// Per-request retry budget for transient API failures (429 / 5xx / 529 /
  /// timeouts). Four attempts → three backoff retries (~1s/2s/4s) before
  /// failing, so an "Overloaded" blip doesn't surface as a failed turn.
  final int maxAttempts;

  /// Per-attempt request timeout.
  final Duration timeout;

  bool get hasApiKey => SyncraProxy.enabled || _apiKey.isNotEmpty;

  /// POSTs [payload] to the Messages API and returns the decoded JSON body on
  /// 200. Transient failures (429 rate-limit, 529 "Overloaded", 5xx, timeouts)
  /// are retried with exponential backoff (honoring a `Retry-After` header);
  /// permanent errors (auth, bad request) throw immediately. Throws
  /// [AnthropicException] when all attempts fail.
  Future<Map<String, dynamic>> createMessage(
    Map<String, dynamic> payload,
  ) async {
    final body = jsonEncode(payload);
    // Auth header (Firebase ID token) fetched once per request; valid ~1h, so
    // it outlives the few-second retry budget below.
    final headers = await SyncraProxy.jsonHeaders();
    Object lastError = AnthropicException('Anthropic request failed.');

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _client
            .post(SyncraProxy.anthropic, headers: headers, body: body)
            .timeout(timeout);

        if (response.statusCode == 200) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }

        final error = AnthropicException(
          _extractError(response.body, response.statusCode),
          statusCode: response.statusCode,
        );
        if (!_isRetryableStatus(response.statusCode) ||
            attempt == maxAttempts) {
          throw error;
        }
        lastError = error;
        await Future<void>.delayed(
          _backoffDelay(attempt, response.headers['retry-after']),
        );
      } on TimeoutException {
        if (attempt == maxAttempts) {
          throw AnthropicException(
            'Anthropic request timed out. Please try again.',
          );
        }
        await Future<void>.delayed(_backoffDelay(attempt, null));
      }
    }
    throw lastError;
  }

  /// Concatenates every `text` block in a Messages API [response] body. With
  /// structured outputs the first text block is the complete JSON payload;
  /// without it, multiple text blocks are joined with newlines.
  static String textOf(Map<String, dynamic> response) {
    final content = response['content'] as List? ?? const [];
    return content
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => (b['text'] as String?) ?? '')
        .join('\n')
        .trim();
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

  static String _extractError(String body, int status) {
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

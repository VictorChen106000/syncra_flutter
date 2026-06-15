import 'package:firebase_auth/firebase_auth.dart';

/// Central config for routing third-party API calls (Anthropic, JSearch)
/// through Firebase Cloud Functions instead of calling them directly with a
/// key compiled into the client.
///
/// The function URLs below are **public endpoints, not secrets** — they are
/// protected by Firebase Auth. Every request carries the signed-in user's
/// Firebase ID token; the function verifies it and only then injects the real
/// provider key (held in Cloud Secret Manager) server-side. So these URLs can
/// safely live in source, and there is nothing to paste at run time.
///
/// Deploy steps live in `functions/README.md`. After deploy, just `flutter run`
/// — no `--dart-define` keys required.
class SyncraProxy {
  SyncraProxy._();

  /// Base URL for the deployed Cloud Functions. Defaults to the HTTPS function
  /// host for project `syncra-signlogin` in `us-central1`. Override with
  /// `--dart-define=SYNCRA_PROXY_BASE=https://<region>-<project>.cloudfunctions.net`
  /// only if you deploy to a different project or region.
  static const base = String.fromEnvironment(
    'SYNCRA_PROXY_BASE',
    defaultValue: 'https://us-central1-syncra-signlogin.cloudfunctions.net',
  );

  /// Offline/mock escape hatch: `--dart-define=SYNCRA_USE_MOCKS=true` makes
  /// every service report "no backend" so callers fall back to mock data
  /// without hitting the network or the proxy.
  static const useMocks = bool.fromEnvironment('SYNCRA_USE_MOCKS');

  /// True when services should hit the real backend (the proxy) rather than
  /// fall back to mocks.
  static bool get enabled => !useMocks;

  /// Proxy for `POST https://api.anthropic.com/v1/messages`.
  static Uri get anthropic => Uri.parse('$base/anthropicProxy');

  /// Proxy for `GET https://jsearch.p.rapidapi.com/search`.
  static Uri get jsearch => Uri.parse('$base/jsearchProxy');

  /// The current user's Firebase ID token, sent as a Bearer token so the
  /// function can authenticate the caller. Null when nobody is signed in.
  static Future<String?> idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  /// Authorization header for a proxied request. Throws [SyncraProxyAuthError]
  /// when no user is signed in, since the function rejects unauthenticated
  /// calls — surfacing it here gives a clearer message than a raw 401.
  static Future<Map<String, String>> authHeaders() async {
    final token = await idToken();
    if (token == null) {
      throw SyncraProxyAuthError();
    }
    return {'authorization': 'Bearer $token'};
  }

  /// [authHeaders] plus a JSON content-type, for POST bodies.
  static Future<Map<String, String>> jsonHeaders() async {
    return {'content-type': 'application/json', ...await authHeaders()};
  }
}

/// Thrown when a proxied call is attempted with no signed-in Firebase user.
class SyncraProxyAuthError implements Exception {
  @override
  String toString() =>
      'SyncraProxyAuthError: not signed in — cannot reach the Syncra backend.';
}

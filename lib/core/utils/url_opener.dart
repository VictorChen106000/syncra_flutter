import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens external links (job apply links, Google listings, company websites)
/// in an in-app browser. Centralised so every caller validates the URL the
/// same way and never throws into the UI — callers show a snackbar on `false`.
class UrlOpener {
  const UrlOpener._();

  /// Launches [rawUrl] in an in-app browser view (SFSafariViewController on
  /// iOS / Custom Tabs on Android) so the app stays in the foreground instead
  /// of being backgrounded by an external browser. Returns `false` — never
  /// throws — when the URL is empty, not a parseable `http`/`https` link, or
  /// the platform refuses to open it, so the caller can surface a snackbar
  /// instead of crashing.
  static Future<bool> open(String rawUrl) async {
    final uri = _parseHttpUrl(rawUrl);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      debugPrint('UrlOpener: failed to open "$rawUrl" ($e)');
      return false;
    }
  }

  /// True when [rawUrl] is a well-formed `http`/`https` link we'd be willing to
  /// open. Lets the UI decide whether to render/enable a link affordance.
  static bool canOpen(String rawUrl) => _parseHttpUrl(rawUrl) != null;

  static Uri? _parseHttpUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    return uri;
  }
}

import '../models/recipient_resolution.dart';

/// Safe shell for future official-site recipient discovery.
///
/// The Flutter client deliberately does not scrape websites, LinkedIn, social
/// media, or private profiles. A Firebase callable function can later implement
/// the actual discovery and return a [RecipientResolution]; until then the app
/// simply falls through to the confirmed cache or low-confidence domain guess.
class CompanyContactDiscoveryService {
  const CompanyContactDiscoveryService();

  Future<RecipientResolution?> resolve({
    required String company,
    String? website,
    String? applyLink,
  }) async {
    return null;
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../data/services/syncra_proxy.dart';
import '../models/recipient_resolution.dart';

typedef CompanyContactHeadersProvider = Future<Map<String, String>> Function();

class CompanyContactDiscoveryService {
  const CompanyContactDiscoveryService({
    http.Client? client,
    CompanyContactHeadersProvider? headersProvider,
    Uri? endpoint,
  }) : _client = client,
       _headersProvider = headersProvider,
       _endpoint = endpoint;

  final http.Client? _client;
  final CompanyContactHeadersProvider? _headersProvider;
  final Uri? _endpoint;

  Future<RecipientResolution?> resolve({
    required String company,
    String? website,
    String? applyLink,
  }) async {
    final cleanCompany = company.trim();
    final cleanWebsite = website?.trim();
    final cleanApplyLink = applyLink?.trim();

    if (cleanCompany.isEmpty &&
        (cleanWebsite == null || cleanWebsite.isEmpty) &&
        (cleanApplyLink == null || cleanApplyLink.isEmpty)) {
      return null;
    }

    final client = _client ?? http.Client();

    try {
      final headersProvider = _headersProvider ?? SyncraProxy.jsonHeaders;
      final headers = await headersProvider();

      final response = await client
          .post(
            _endpoint ?? SyncraProxy.companyContactDiscovery,
            headers: headers,
            body: jsonEncode({
              'company': cleanCompany,
              if (cleanWebsite != null && cleanWebsite.isNotEmpty)
                'website': cleanWebsite,
              if (cleanApplyLink != null && cleanApplyLink.isNotEmpty)
                'applyLink': cleanApplyLink,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        debugPrint(
          'CompanyContactDiscoveryService failed: HTTP ${response.statusCode}',
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final resolution = RecipientResolution.fromJson(decoded);
      if (!resolution.hasEmail) return null;
      return resolution;
    } catch (e) {
      debugPrint('CompanyContactDiscoveryService failed: $e');
      return null;
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }
}

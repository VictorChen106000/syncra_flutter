import 'package:flutter/foundation.dart';

@immutable
class DemoReadiness {
  DemoReadiness({required Iterable<DemoReadinessItem> items})
    : items = List.unmodifiable(items);

  final List<DemoReadinessItem> items;

  bool get isReady => items.every((item) => item.isReady);

  int get readyCount => items.where((item) => item.isReady).length;

  int get totalCount => items.length;
}

@immutable
class DemoReadinessItem {
  const DemoReadinessItem({
    required this.label,
    required this.isReady,
    required this.detail,
  });

  final String label;
  final bool isReady;
  final String detail;
}

DemoReadiness evaluateDemoReadiness({
  String anthropicApiKey = const String.fromEnvironment('ANTHROPIC_API_KEY'),
  String rapidApiKey = const String.fromEnvironment('RAPIDAPI_KEY'),
}) {
  final hasAnthropic = anthropicApiKey.trim().isNotEmpty;
  final hasRapidApi = rapidApiKey.trim().isNotEmpty;

  return DemoReadiness(
    items: [
      DemoReadinessItem(
        label: 'Anthropic API',
        isReady: hasAnthropic,
        detail: hasAnthropic
            ? 'Claude agent calls are enabled.'
            : 'Missing ANTHROPIC_API_KEY.',
      ),
      DemoReadinessItem(
        label: 'JSearch API',
        isReady: hasRapidApi,
        detail: hasRapidApi
            ? 'Live job search is enabled.'
            : 'Missing RAPIDAPI_KEY.',
      ),
    ],
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/core/dev/demo_readiness.dart';

void main() {
  group('Demo readiness', () {
    test('marks missing API keys as not ready', () {
      final readiness = evaluateDemoReadiness(
        anthropicApiKey: '',
        rapidApiKey: '',
      );

      expect(readiness.isReady, isFalse);
      expect(readiness.readyCount, 0);
      expect(readiness.totalCount, 2);
      expect(
        readiness.items.map((item) => item.detail),
        containsAll(['Missing ANTHROPIC_API_KEY.', 'Missing RAPIDAPI_KEY.']),
      );
    });

    test('marks both API keys as ready when present', () {
      final readiness = evaluateDemoReadiness(
        anthropicApiKey: 'sk-ant-test',
        rapidApiKey: 'rapid-test',
      );

      expect(readiness.isReady, isTrue);
      expect(readiness.readyCount, 2);
      expect(readiness.items.every((item) => item.isReady), isTrue);
    });

    test('trims whitespace-only API keys', () {
      final readiness = evaluateDemoReadiness(
        anthropicApiKey: '   ',
        rapidApiKey: '\n\t',
      );

      expect(readiness.isReady, isFalse);
      expect(readiness.readyCount, 0);
    });
  });
}

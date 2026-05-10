import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/shared/widgets/app_bottom_nav.dart';

void main() {
  testWidgets('bottom nav active tabs fit narrow phone widths', (tester) async {
    for (final activeTab in BottomNavTab.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: AppBottomNav(activeTab: activeTab),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    }
  });
}

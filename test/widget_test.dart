import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/app.dart';

void main() {
  testWidgets('Syncra app starts on login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SyncraApp());

    expect(find.text('Continue as Guest'), findsOneWidget);
  });
}
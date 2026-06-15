import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/email/models/recipient_resolution.dart';
import 'package:syncra/features/email/presentation/email_review_page.dart';

void main() {
  testWidgets('email review UI shows guessed warning', (tester) async {
    await _openReview(
      tester,
      recipient: 'careers@linear.app',
      mode: EmailReviewMode.send,
      resolution: RecipientResolution.guessed(
        email: 'careers@linear.app',
        domain: 'linear.app',
      ),
    );

    expect(find.text('Guessed address'), findsOneWidget);
    expect(
      find.textContaining('Syncra could not fully verify this recipient.'),
      findsOneWidget,
    );

    expect(
      find.textContaining('replace the recipient manually.'),
      findsOneWidget,
    );
  });

  testWidgets('low-confidence send requires confirmation checkbox', (
    tester,
  ) async {
    await _openReview(
      tester,
      recipient: 'careers@linear.app',
      mode: EmailReviewMode.send,
      resolution: RecipientResolution.guessed(
        email: 'careers@linear.app',
        domain: 'linear.app',
      ),
    );

    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Send email'), findsNothing);
    expect(_primaryInkWell(tester, 'Send now').onTap, isNull);
    expect(
      find.text('I reviewed this recipient and want to send anyway.'),
      findsWidgets,
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(_primaryInkWell(tester, 'Send now').onTap, isNotNull);
  });

  testWidgets('none recipient disables send until user enters an email', (
    tester,
  ) async {
    await _openReview(
      tester,
      recipient: '',
      mode: EmailReviewMode.send,
      resolution: RecipientResolution.none(domain: 'linear.app'),
    );

    expect(find.text('No public email found'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Send email'), findsNothing);
    expect(_primaryInkWell(tester, 'Send now').onTap, isNull);

    await tester.enterText(find.byType(TextField).first, 'talent@linear.app');
    await tester.pump();

    expect(find.text('Confirmed contact'), findsOneWidget);
    expect(_primaryInkWell(tester, 'Send now').onTap, isNotNull);
  });
}

Future<void> _openReview(
  WidgetTester tester, {
  required String recipient,
  required EmailReviewMode mode,
  required RecipientResolution resolution,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              EmailReviewPage.show(
                context,
                recipient: recipient,
                subject: 'Application',
                body: 'Hi team, I would like to apply.',
                mode: mode,
                contactDomain: resolution.domain,
                recipientResolution: resolution,
              );
            },
            child: const Text('Open review'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open review'));
  await tester.pumpAndSettle();
}

InkWell _primaryInkWell(WidgetTester tester, String label) {
  final finder = find.ancestor(
    of: find.text(label),
    matching: find.byType(InkWell),
  );
  return tester.widgetList<InkWell>(finder).last;
}

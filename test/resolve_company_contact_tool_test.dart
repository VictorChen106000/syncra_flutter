import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/agent_chat/tools/builtin_tools.dart';
import 'package:syncra/features/email/models/recipient_resolution.dart';

void main() {
  // App ships with a demo-inbox override; this test checks real resolution.

  test(
    'resolve_company_contact tool helper returns recipient metadata',
    () async {
      final result = await resolveCompanyContactToolResult(
        'Linear',
        website: 'https://linear.app',
      );

      expect(result.isError, isFalse);
      final data = result.data as Map<String, dynamic>;
      expect(data['email'], 'careers@linear.app');
      expect(data['domain'], 'linear.app');
      expect(data['confidence'], RecipientConfidence.low.name);
      expect(data['source'], RecipientSource.guessedPattern.name);
      expect(data['canAutoSend'], isFalse);
      expect(data['requiresUserConfirmation'], isTrue);
    },
  );
}

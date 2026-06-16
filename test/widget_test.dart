import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/core/constants/app_strings.dart';
import 'package:syncra/features/auth/presentation/login_page.dart';
import 'package:syncra/features/auth/state/auth_notifier.dart';

/// A no-Firebase [AuthNotifier]: returns a fixed signed-out state and never
/// subscribes to `FirebaseAuth`, so [LoginPage] can be pumped without calling
/// `Firebase.initializeApp()`. The full app boots on the splash route and
/// redirects via the router, which needs live Firebase — out of scope for a
/// widget unit test, so we exercise the login UI directly instead.
class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState();
}

void main() {
  testWidgets('LoginPage shows the sign-in options', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith(_FakeAuthNotifier.new)],
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pump();

    expect(find.text(AppStrings.continueWithGoogle), findsOneWidget);
    expect(find.text('Continue with Email'), findsOneWidget);
    // Guest mode was removed — everyone signs in.
    expect(find.text('Continue as Guest'), findsNothing);
  });
}

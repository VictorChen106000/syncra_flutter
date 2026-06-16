// Verifies the Profile page surfaces Agent Autonomy as the single user-facing
// autonomy control and no longer renders a separate "Bounded Auto-Apply"
// settings section. Each option keeps only its title inline; the description
// lives behind an ⓘ button that opens a popup. Bounded Auto-Apply stays the
// internal safety backend (its model + `shouldAutoSendOutreach` are unchanged
// and covered by auto_send_outreach_test.dart / auto_apply_settings_test.dart).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:syncra/core/theme/app_theme.dart';
import 'package:syncra/data/firestore/resumes_repository.dart';
import 'package:syncra/data/firestore/user_repository.dart';
import 'package:syncra/features/auth/state/auth_notifier.dart';
import 'package:syncra/features/auth/state/user_profile_notifier.dart';
import 'package:syncra/features/profile/presentation/profile_page.dart';
import 'package:syncra/features/resumes/state/resume_notifier.dart';
import 'package:syncra/shared/widgets/section_title.dart';

// Enough of the Firebase types to construct the repositories without
// Firebase.initializeApp(); the guest auth path never actually reads from them.
class _FakeFirestore extends Fake implements FirebaseFirestore {}

class _FakeStorage extends Fake implements FirebaseStorage {}

// Overriding build() returns a signed-out state directly, so no
// FirebaseAuth.instance and the profile / resume / career-memory streams all
// short-circuit on the null user.
class _SignedOutAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState();
}

Future<void> _pumpProfile(WidgetTester tester) async {
  // Tall surface so every ListView section is laid out without scrolling.
  tester.view.physicalSize = const Size(450, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final fakeDb = _FakeFirestore();
  final fakeStorage = _FakeStorage();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_SignedOutAuthNotifier.new),
        userProfileProvider.overrideWith(
          () => UserProfileNotifier(
            repository: UserRepository(db: fakeDb, storage: fakeStorage),
          ),
        ),
        resumeProvider.overrideWith(
          () => ResumeNotifier(
            repository: ResumesRepository(db: fakeDb, storage: fakeStorage),
          ),
        ),
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, home: const ProfilePage()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Profile shows Agent Autonomy and hides Bounded Auto-Apply', (
    tester,
  ) async {
    await _pumpProfile(tester);

    // Assert on the SectionTitle.title property (the widget uppercases its
    // text at render time, so matching rendered Text would be brittle).
    expect(
      find.byWidgetPredicate(
        (w) => w is SectionTitle && w.title == 'Agent Autonomy',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is SectionTitle && w.title == 'Bounded Auto-Apply',
      ),
      findsNothing,
      reason: 'the duplicate visible Bounded Auto-Apply section was removed',
    );

    // No stray "Bounded Auto-Apply" label anywhere on the page either.
    expect(find.text('Bounded Auto-Apply'), findsNothing);
  });

  testWidgets('autonomy option blurb is hidden until its ⓘ is tapped', (
    tester,
  ) async {
    await _pumpProfile(tester);

    const assistBlurb = 'Asks before each step — you approve every move.';

    // Descriptions are no longer inline.
    expect(find.text(assistBlurb), findsNothing);

    // The first ⓘ belongs to the top row (Assist); tapping it opens the popup.
    expect(find.byIcon(Icons.info_outline_rounded), findsNWidgets(3));
    await tester.tap(find.byIcon(Icons.info_outline_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(assistBlurb), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
  });
}

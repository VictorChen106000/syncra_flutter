import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../dev/dev_flags_notifier.dart';
import '../../features/agent_chat/presentation/ai_chatbot_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/morning_brief_page.dart';
import '../../features/auth/presentation/onboarding_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/agent/state/passive_agent_notifier.dart';
import '../../features/auth/state/auth_notifier.dart';
import '../../features/auth/state/user_profile_notifier.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/resumes/models/resume_file.dart';
import '../../features/resumes/presentation/resume_lists_page.dart';
import '../../features/resumes/presentation/resume_preview_page.dart';
import '../../features/applications/presentation/applications_page.dart';
import 'route_names.dart';

/// A [ChangeNotifier] that fires whenever auth or user-profile state
/// changes, so [GoRouter] can re-run its redirect (e.g. land a new sign-in
/// on onboarding once the profile stream confirms `role == null`).
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
    ref.listen(userProfileProvider, (_, _) => notifyListeners());
    ref.listen(devFlagsProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  ref.read(authProvider.notifier);
  ref.read(passiveAgentProvider.notifier);
  ref.read(userProfileProvider.notifier);

  final refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  Page<void> fadePage(GoRouterState state, Widget child) {
    return NoTransitionPage<void>(key: state.pageKey, child: child);
  }

  return GoRouter(
    initialLocation: RouteNames.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final passive = ref.read(passiveAgentProvider);
      final profile = ref.read(userProfileProvider);
      final dev = ref.read(devFlagsProvider);
      final isSignedIn = auth.isSignedIn;
      final isGuest = auth.appUser?.isGuest ?? false;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == RouteNames.login ||
          loc == RouteNames.signup ||
          loc == RouteNames.splash ||
          loc == RouteNames.onboarding;

      if (!isSignedIn && !isAuthRoute) {
        return RouteNames.login;
      }
      if (!isSignedIn) return null;

      // Dev: force-show toggles take priority over normal routing so devs
      // can preview onboarding / morning brief at will. Each page's exit
      // handler clears its flag so the user isn't trapped.
      if (dev.showOnboarding && loc != RouteNames.onboarding) {
        return RouteNames.onboarding;
      }
      if (dev.showMorningBrief && loc != RouteNames.morningBrief) {
        return RouteNames.morningBrief;
      }

      final needsOnboarding = !isGuest &&
          profile != null &&
          (profile.role ?? '').trim().isEmpty;
      if (needsOnboarding && loc != RouteNames.onboarding) {
        return RouteNames.onboarding;
      }

      // Boot the user off onboarding when it isn't needed AND a dev override
      // isn't actively keeping them there.
      if (!needsOnboarding &&
          !dev.showOnboarding &&
          loc == RouteNames.onboarding) {
        return RouteNames.agentChat;
      }

      // After sign-in the chat is the home. Morning brief still shows first
      // when the user has opted in (Profile → "Today's brief").
      if (loc == RouteNames.login || loc == RouteNames.signup) {
        final wantsMorningBrief = profile?.morningBriefEnabled ?? false;
        if (wantsMorningBrief && !passive.morningBriefShown) {
          return RouteNames.morningBrief;
        }
        return RouteNames.agentChat;
      }

      return null;
    },
    routes: _routes(fadePage),
  );
});

List<RouteBase> _routes(Page<void> Function(GoRouterState, Widget) fadePage) =>
    [
      GoRoute(
        path: RouteNames.splash,
        pageBuilder: (context, state) => fadePage(state, const SplashPage()),
      ),
      GoRoute(
        path: RouteNames.login,
        pageBuilder: (context, state) => fadePage(state, const LoginPage()),
      ),
      GoRoute(
        path: RouteNames.signup,
        pageBuilder: (context, state) => fadePage(state, const SignUpPage()),
      ),
      GoRoute(
        path: RouteNames.onboarding,
        pageBuilder: (context, state) =>
            fadePage(state, const OnboardingPage()),
      ),
      GoRoute(
        path: RouteNames.morningBrief,
        pageBuilder: (context, state) =>
            fadePage(state, const MorningBriefPage()),
      ),
      GoRoute(
        path: RouteNames.resumes,
        pageBuilder: (context, state) =>
            fadePage(state, const ResumeListsPage()),
      ),
      GoRoute(
        path: RouteNames.resumePreview,
        pageBuilder: (context, state) {
          final resume =
              state.extra is ResumeFile ? state.extra as ResumeFile : null;
          return fadePage(state, ResumePreviewPage(resume: resume));
        },
      ),
      GoRoute(
        path: RouteNames.agentChat,
        pageBuilder: (context, state) => fadePage(
          state,
          AiChatbotPage(
            autofocusComposer: state.uri.queryParameters['focus'] == '1',
          ),
        ),
      ),
      // Chat is the app's home — there are no sibling top-level routes for
      // dashboard / jobs / profile any more. Their UI now lives inside the
      // chat itself (inbox empty state) and inside the drawer's profile
      // sheet. The pages below are workflow sub-screens, not nav targets.
      GoRoute(
        path: RouteNames.applications,
        pageBuilder: (context, state) =>
            fadePage(state, const ApplicationsPage()),
      ),
      GoRoute(
        path: RouteNames.notifications,
        pageBuilder: (context, state) =>
            fadePage(state, const NotificationsPage()),
      ),
    ];

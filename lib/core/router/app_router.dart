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
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/jobs/presentation/jobs_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/resumes/models/resume_file.dart';
import '../../features/resumes/presentation/resume_lists_page.dart';
import '../../features/resumes/presentation/resume_preview_page.dart';
import '../../features/applications/presentation/applications_page.dart';
import '../../shared/widgets/app_shell_scaffold.dart';
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

      // Onboarding is gated on an explicit flag, not on `role` being empty —
      // the Skip path intentionally leaves the role blank but still marks the
      // user past first-run setup so they aren't bounced back here every load.
      final needsOnboarding =
          !isGuest && profile != null && !profile.hasCompletedOnboarding;
      if (needsOnboarding && loc != RouteNames.onboarding) {
        return RouteNames.onboarding;
      }

      // Boot the user off onboarding when it isn't needed AND a dev override
      // isn't actively keeping them there.
      if (!needsOnboarding &&
          !dev.showOnboarding &&
          loc == RouteNames.onboarding) {
        return RouteNames.dashboard;
      }

      // After sign-in, only greet the user with the morning brief when they
      // have opted in (Profile → "Today's brief"). Off by default — most
      // sign-ins, and every sign-in during development, land straight on the
      // dashboard. `morningBriefShown` keeps it to once per app session.
      if (loc == RouteNames.login || loc == RouteNames.signup) {
        final wantsMorningBrief = profile?.morningBriefEnabled ?? false;
        if (wantsMorningBrief && !passive.morningBriefShown) {
          return RouteNames.morningBrief;
        }
        return RouteNames.dashboard;
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShellScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.dashboard,
                pageBuilder: (context, state) =>
                    fadePage(state, const DashboardPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.jobs,
                pageBuilder: (context, state) =>
                    fadePage(state, const JobsPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.profile,
                pageBuilder: (context, state) =>
                    fadePage(state, const ProfilePage()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: RouteNames.applications,
        pageBuilder: (context, state) =>
            fadePage(state, const ApplicationsPage()),
      ),
    ];

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/agent_chat/presentation/ai_chatbot_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/onboarding_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/agent/state/passive_agent_notifier.dart';
import '../../features/auth/state/auth_notifier.dart';
import '../../features/auth/state/user_profile_notifier.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/email/presentation/link_gmail_page.dart';
import '../../features/jobs/presentation/jobs_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/resumes/models/resume_file.dart';
import '../../features/resumes/presentation/resume_lists_page.dart';
import '../../features/resumes/presentation/resume_preview_page.dart';
import '../../shared/widgets/app_shell_scaffold.dart';
import 'route_names.dart';

/// A [ChangeNotifier] that fires whenever auth or user-profile state
/// changes, so [GoRouter] can re-run its redirect (e.g. land a new sign-in
/// on onboarding once the profile stream confirms `role == null`).
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
    ref.listen(userProfileProvider, (_, _) => notifyListeners());
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
      final profile = ref.read(userProfileProvider);
      final isSignedIn = auth.isSignedIn;
      final isGuest = auth.appUser?.isGuest ?? false;
      final loc = state.matchedLocation;
      final isAuthRoute =
          loc == RouteNames.login ||
          loc == RouteNames.signup ||
          loc == RouteNames.splash ||
          loc == RouteNames.onboarding;

      if (!isSignedIn && !isAuthRoute) {
        return RouteNames.login;
      }
      if (!isSignedIn) return null;

      // Onboarding is gated on an explicit flag, not on `role` being empty —
      // the Skip path intentionally leaves the role blank but still marks the
      // user past first-run setup so they aren't bounced back here every load.
      final needsOnboarding =
          !isGuest && profile != null && !profile.hasCompletedOnboarding;
      if (needsOnboarding && loc != RouteNames.onboarding) {
        return RouteNames.onboarding;
      }

      // Boot the user off onboarding when it isn't needed.
      if (!needsOnboarding && loc == RouteNames.onboarding) {
        return RouteNames.dashboard;
      }

      // After sign-in, send users to the dashboard. New accounts are caught by
      // the `needsOnboarding` check above and routed to onboarding instead.
      if (loc == RouteNames.login || loc == RouteNames.signup) {
        // Guests have no profile — straight to the dashboard.
        if (isGuest) return RouteNames.dashboard;

        // Non-guest: wait for the `users/{uid}` stream before deciding.
        // Routing on a still-loading (null) profile would drop a brand-new
        // account on the dashboard before we know it still needs onboarding —
        // the user would never see first-run setup. Staying put lets the
        // refresh listener re-run this redirect the moment the profile lands,
        // at which point `needsOnboarding` (above) catches new accounts and
        // sends them to onboarding.
        if (profile == null) return null;
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
        path: RouteNames.linkGmail,
        pageBuilder: (context, state) => fadePage(state, const LinkGmailPage()),
      ),
      GoRoute(
        path: RouteNames.resumes,
        pageBuilder: (context, state) =>
            fadePage(state, const ResumeListsPage()),
      ),
      GoRoute(
        path: RouteNames.resumePreview,
        pageBuilder: (context, state) {
          final resume = state.extra is ResumeFile
              ? state.extra as ResumeFile
              : null;
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
    ];

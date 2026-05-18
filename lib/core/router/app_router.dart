import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/job.dart';
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
import '../../features/jobs/presentation/job_detail_page.dart';
import '../../features/jobs/presentation/jobs_page.dart';
import '../../features/jobs/presentation/review_page.dart';
import '../../features/jobs/presentation/submitted_page.dart';
import '../../features/jobs/presentation/tailor_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/resumes/models/resume_file.dart';
import '../../features/resumes/presentation/resume_lists_page.dart';
import '../../features/resumes/presentation/resume_preview_page.dart';
import '../../features/applications/presentation/applications_page.dart';
import '../../shared/widgets/app_shell_scaffold.dart';
import '../../shared/widgets/light_theme_scope.dart';
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
  // Force initialization of every provider the redirect reads, so the first
  // redirect (which fires synchronously when GoRouter mounts) can never hit
  // an uninitialized provider. Reading `.notifier` triggers `build()` without
  // subscribing routerProvider to state changes — refreshListenable handles
  // re-runs.
  ref.read(authProvider.notifier);
  ref.read(passiveAgentProvider.notifier);
  ref.read(userProfileProvider.notifier);

  final refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  Page<void> fadePage(GoRouterState state, Widget child) {
    return NoTransitionPage<void>(key: state.pageKey, child: child);
  }

  // Light-only routes: pages not yet polished for dark mode. The wrapper
  // forces light theme regardless of [ThemeMode] until they get their own
  // pass. Remove a wrap once a page reads from `BrandTheme.of(context)`.
  Page<void> lightOnlyPage(GoRouterState state, Widget child) {
    return NoTransitionPage<void>(
      key: state.pageKey,
      child: LightThemeScope(child: child),
    );
  }

  return GoRouter(
    initialLocation: RouteNames.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final passive = ref.read(passiveAgentProvider);
      final profile = ref.read(userProfileProvider);
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

      // First-time setup: signed-in non-guest whose profile has loaded
      // but has no `role` yet → send to onboarding once.
      //
      // Profile being null means either (a) guest, or (b) the
      // `users/{uid}` stream hasn't fired its first snapshot yet. In
      // either case we don't redirect — the refresh listener will
      // re-evaluate when the profile arrives.
      final needsOnboarding =
          isSignedIn && !isGuest && profile != null && (profile.role ?? '').trim().isEmpty;
      if (needsOnboarding && loc != RouteNames.onboarding) {
        return RouteNames.onboarding;
      }

      // Conversely, if the user has a role and is sitting on onboarding,
      // bounce them to the dashboard.
      if (!needsOnboarding && loc == RouteNames.onboarding) {
        return RouteNames.dashboard;
      }

      if (isSignedIn &&
          (loc == RouteNames.login || loc == RouteNames.signup)) {
        return passive.morningBriefShown
            ? RouteNames.dashboard
            : RouteNames.morningBrief;
      }

      return null;
    },
    routes: _routes(fadePage, lightOnlyPage),
  );
});

List<RouteBase> _routes(
  Page<void> Function(GoRouterState, Widget) fadePage,
  Page<void> Function(GoRouterState, Widget) lightOnlyPage,
) =>
    [
        GoRoute(
          path: RouteNames.splash,
          pageBuilder: (context, state) =>
              lightOnlyPage(state, const SplashPage()),
        ),
        GoRoute(
          path: RouteNames.login,
          pageBuilder: (context, state) =>
              lightOnlyPage(state, const LoginPage()),
        ),
        GoRoute(
          path: RouteNames.signup,
          pageBuilder: (context, state) =>
              lightOnlyPage(state, const SignUpPage()),
        ),
        GoRoute(
          path: RouteNames.onboarding,
          pageBuilder: (context, state) =>
              lightOnlyPage(state, const OnboardingPage()),
        ),
        GoRoute(
          path: RouteNames.morningBrief,
          pageBuilder: (context, state) =>
              lightOnlyPage(state, const MorningBriefPage()),
        ),
        GoRoute(
          path: RouteNames.resumes,
          pageBuilder: (context, state) =>
              lightOnlyPage(state, const ResumeListsPage()),
        ),
        GoRoute(
          path: RouteNames.resumePreview,
          pageBuilder: (context, state) {
            final resume =
                state.extra is ResumeFile ? state.extra as ResumeFile : null;
            return lightOnlyPage(state, ResumePreviewPage(resume: resume));
          },
        ),
        GoRoute(
          path: RouteNames.agentChat,
          pageBuilder: (context, state) =>
              lightOnlyPage(state, const AiChatbotPage()),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShellScaffold(navigationShell: navigationShell),
          branches: [
            // Branch order must match AppShellScaffold._indexToTab.
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
              lightOnlyPage(state, const ApplicationsPage()),
        ),
        GoRoute(
          path: RouteNames.notifications,
          pageBuilder: (context, state) =>
              lightOnlyPage(state, const NotificationsPage()),
        ),
        GoRoute(
          path: RouteNames.detail,
          pageBuilder: (context, state) {
            final job = state.extra is Job ? state.extra as Job : null;
            return fadePage(state, JobDetailPage(job: job));
          },
        ),
        GoRoute(
          path: RouteNames.tailor,
          pageBuilder: (context, state) {
            final job = state.extra is Job ? state.extra as Job : null;
            return fadePage(state, TailorPage(job: job));
          },
        ),
        GoRoute(
          path: RouteNames.review,
          pageBuilder: (context, state) {
            final job = state.extra is Job ? state.extra as Job : null;
            return fadePage(state, ReviewPage(job: job));
          },
        ),
        GoRoute(
          path: RouteNames.submitted,
          pageBuilder: (context, state) {
            final job = state.extra is Job ? state.extra as Job : null;
            return lightOnlyPage(state, SubmittedPage(job: job));
          },
        ),
    ];

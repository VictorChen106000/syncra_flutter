import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/job.dart';
import '../../features/agent_chat/presentation/ai_chatbot_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/morning_brief_page.dart';
import '../../features/auth/presentation/onboarding_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/agent/state/passive_agent_controller.dart';
import '../../features/auth/state/auth_controller.dart';
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
import '../../features/tracker/presentation/tracker_page.dart';
import '../../shared/widgets/app_shell_scaffold.dart';
import 'route_names.dart';

class AppRouter {
  const AppRouter._();

  static Page<void> _fadePage(GoRouterState state, Widget child) {
    return NoTransitionPage<void>(key: state.pageKey, child: child);
  }

  /// Creates a [GoRouter] that redirects based on auth state.
  ///
  /// The [authController] is used to check sign-in status and trigger
  /// refreshes when the auth state changes. The [passiveAgent] controller
  /// is consulted to decide whether to send a fresh sign-in to the
  /// morning brief before the dashboard.
  static GoRouter router(
    AuthController authController,
    PassiveAgentController passiveAgent,
  ) {
    return GoRouter(
      initialLocation: RouteNames.splash,
      refreshListenable: authController,
      redirect: (context, state) {
        final isSignedIn = authController.isSignedIn;
        final loc = state.matchedLocation;
        final isAuthRoute = loc == RouteNames.login ||
            loc == RouteNames.signup ||
            loc == RouteNames.splash ||
            loc == RouteNames.onboarding;

        // Not signed in and trying to reach a protected route → login.
        if (!isSignedIn && !isAuthRoute) {
          return RouteNames.login;
        }

        // Signed in but sitting on login/signup → morning brief on first
        // sign-in this session, then straight to dashboard.
        if (isSignedIn &&
            (loc == RouteNames.login || loc == RouteNames.signup)) {
          return passiveAgent.morningBriefShown
              ? RouteNames.dashboard
              : RouteNames.morningBrief;
        }

        return null;
      },
      routes: [
        GoRoute(
          path: RouteNames.splash,
          pageBuilder: (context, state) => _fadePage(state, const SplashPage()),
        ),
        GoRoute(
          path: RouteNames.login,
          pageBuilder: (context, state) => _fadePage(state, const LoginPage()),
        ),
        GoRoute(
          path: RouteNames.signup,
          pageBuilder: (context, state) => _fadePage(state, const SignUpPage()),
        ),
        GoRoute(
          path: RouteNames.onboarding,
          pageBuilder: (context, state) =>
              _fadePage(state, const OnboardingPage()),
        ),
        GoRoute(
          path: RouteNames.morningBrief,
          pageBuilder: (context, state) =>
              _fadePage(state, const MorningBriefPage()),
        ),
        GoRoute(
          path: RouteNames.resumes,
          pageBuilder: (context, state) =>
              _fadePage(state, const ResumeListsPage()),
        ),
        GoRoute(
          path: RouteNames.resumePreview,
          pageBuilder: (context, state) {
            final resume =
                state.extra is ResumeFile ? state.extra as ResumeFile : null;
            return _fadePage(state, ResumePreviewPage(resume: resume));
          },
        ),
        GoRoute(
          path: RouteNames.agentChat,
          pageBuilder: (context, state) =>
              _fadePage(state, const AiChatbotPage()),
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
                      _fadePage(state, const DashboardPage()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RouteNames.jobs,
                  pageBuilder: (context, state) =>
                      _fadePage(state, const JobsPage()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RouteNames.profile,
                  pageBuilder: (context, state) =>
                      _fadePage(state, const ProfilePage()),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: RouteNames.tracker,
          pageBuilder: (context, state) =>
              _fadePage(state, const TrackerPage()),
        ),
        GoRoute(
          path: RouteNames.notifications,
          pageBuilder: (context, state) =>
              _fadePage(state, const NotificationsPage()),
        ),
        GoRoute(
          path: RouteNames.detail,
          pageBuilder: (context, state) {
            final job = state.extra is Job ? state.extra as Job : null;
            return _fadePage(state, JobDetailPage(job: job));
          },
        ),
        GoRoute(
          path: RouteNames.tailor,
          pageBuilder: (context, state) {
            final job = state.extra is Job ? state.extra as Job : null;
            return _fadePage(state, TailorPage(job: job));
          },
        ),
        GoRoute(
          path: RouteNames.review,
          pageBuilder: (context, state) {
            final job = state.extra is Job ? state.extra as Job : null;
            return _fadePage(state, ReviewPage(job: job));
          },
        ),
        GoRoute(
          path: RouteNames.submitted,
          pageBuilder: (context, state) {
            final job = state.extra is Job ? state.extra as Job : null;
            return _fadePage(state, SubmittedPage(job: job));
          },
        ),
      ],
    );
  }
}

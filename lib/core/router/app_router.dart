import 'package:go_router/go_router.dart';

import '../../features/agent_chat/presentation/ai_chatbot_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/state/auth_controller.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/resumes/presentation/resume_lists_page.dart';
import 'route_names.dart';

class AppRouter {
  const AppRouter._();

  /// Creates a [GoRouter] that redirects based on auth state.
  ///
  /// The [authController] is used to check sign-in status and trigger
  /// refreshes when the auth state changes.
  static GoRouter router(AuthController authController) {
    return GoRouter(
      initialLocation: RouteNames.login,
      refreshListenable: authController,
      redirect: (context, state) {
        final isSignedIn = authController.isSignedIn;
        final isOnLogin = state.matchedLocation == RouteNames.login;

        // Not signed in and not on login → redirect to login.
        if (!isSignedIn && !isOnLogin) {
          return RouteNames.login;
        }

        // Signed in but still on login → redirect to resumes.
        if (isSignedIn && isOnLogin) {
          return RouteNames.resumes;
        }

        // No redirect needed.
        return null;
      },
      routes: [
        GoRoute(
          path: RouteNames.login,
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: RouteNames.resumes,
          builder: (context, state) => const ResumeListsPage(),
        ),
        GoRoute(
          path: RouteNames.dashboard,
          builder: (context, state) => const DashboardPage(),
        ),
        GoRoute(
          path: RouteNames.agentChat,
          builder: (context, state) => const AiChatbotPage(),
        ),
        GoRoute(
          path: RouteNames.profile,
          builder: (context, state) => const ProfilePage(),
        ),
      ],
    );
  }
}

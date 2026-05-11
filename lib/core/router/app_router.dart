import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/agent_chat/presentation/ai_chatbot_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/jobs/presentation/jobs_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/resumes/presentation/resume_lists_page.dart';
import 'route_names.dart';

class AppRouter {
  const AppRouter._();

  static Page<void> _fadePage(GoRouterState state, Widget child) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fadeIn = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        final slideIn = Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

        return FadeTransition(
          opacity: fadeIn,
          child: SlideTransition(position: slideIn, child: child),
        );
      },
    );
  }

  static final GoRouter router = GoRouter(
    initialLocation: RouteNames.login,
    routes: [
      GoRoute(
        path: RouteNames.login,
        pageBuilder: (context, state) => _fadePage(state, const LoginPage()),
      ),
      GoRoute(
        path: RouteNames.resumes,
        pageBuilder: (context, state) => _fadePage(state, const ResumeListsPage()),
      ),
      GoRoute(
        path: RouteNames.dashboard,
        pageBuilder: (context, state) => _fadePage(state, const DashboardPage()),
      ),
      GoRoute(
        path: RouteNames.agentChat,
        pageBuilder: (context, state) => _fadePage(state, const AiChatbotPage()),
      ),
      GoRoute(
        path: RouteNames.profile,
        pageBuilder: (context, state) => _fadePage(state, const ProfilePage()),
      ),
      GoRoute(
        path: RouteNames.jobs,
        pageBuilder: (context, state) => _fadePage(state, const JobsPage()),
      ),
    ],
  );
}

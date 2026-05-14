import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/agent/state/passive_agent_controller.dart';
import 'features/agent_chat/state/agent_chat_controller.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/jobs/state/jobs_controller.dart';
import 'features/notifications/state/notifications_controller.dart';
import 'features/resumes/state/resume_controller.dart';
import 'features/tracker/state/tracker_controller.dart';

class SyncraApp extends StatelessWidget {
  const SyncraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthController()),
        ChangeNotifierProvider(create: (_) => ResumeController()),
        ChangeNotifierProvider(create: (_) => AgentChatController()),
        ChangeNotifierProvider(create: (_) => TrackerController()),
        ChangeNotifierProvider(create: (_) => NotificationsController()),
        ChangeNotifierProvider(create: (_) => JobsController()),
        ChangeNotifierProvider(create: (_) => PassiveAgentController()),
      ],
      child: const _SyncraAppShell(),
    );
  }
}

/// Builds the [GoRouter] exactly once so navigation state survives across
/// controller rebuilds. The router itself listens on the auth controller
/// for refreshes; the redirect reads the passive agent controller's
/// session flag synchronously on every navigation.
class _SyncraAppShell extends StatefulWidget {
  const _SyncraAppShell();

  @override
  State<_SyncraAppShell> createState() => _SyncraAppShellState();
}

class _SyncraAppShellState extends State<_SyncraAppShell> {
  GoRouter? _router;

  @override
  Widget build(BuildContext context) {
    _router ??= AppRouter.router(
      context.read<AuthController>(),
      context.read<PassiveAgentController>(),
    );
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Syncra',
      theme: AppTheme.lightTheme,
      routerConfig: _router!,
    );
  }
}

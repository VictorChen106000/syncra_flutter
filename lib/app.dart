import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/mock/mock_agent_service.dart';
import 'features/agent/state/passive_agent_controller.dart';
import 'features/agent_chat/services/agent_service.dart';
import 'features/agent_chat/services/anthropic_chat_service.dart';
import 'features/agent_chat/state/agent_chat_controller.dart';
import 'features/agent_chat/tools/builtin_tools.dart';
import 'features/agent_chat/tools/tool_registry.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/jobs/state/jobs_controller.dart';
import 'features/notifications/state/notifications_controller.dart';
import 'features/resumes/state/resume_controller.dart';
import 'features/tracker/state/tracker_controller.dart';

AgentService _buildAgentService() {
  final registry = ToolRegistry();
  registerBuiltinTools(registry);

  final anthropic = AnthropicChatService(registry: registry);
  if (anthropic.hasApiKey) return anthropic;
  return MockAgentService();
}

class SyncraApp extends StatelessWidget {
  const SyncraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthController()),
        ChangeNotifierProxyProvider<AuthController, ResumeController>(
          create: (context) => ResumeController(
            auth: context.read<AuthController>(),
          ),
          update: (_, _, previous) =>
              previous ?? ResumeController(auth: AuthController()),
        ),
        ChangeNotifierProvider(
          create: (_) => AgentChatController(service: _buildAgentService()),
        ),
        ChangeNotifierProxyProvider<AuthController, TrackerController>(
          create: (context) => TrackerController(
            auth: context.read<AuthController>(),
          ),
          update: (_, _, previous) =>
              previous ?? TrackerController(auth: AuthController()),
        ),
        ChangeNotifierProvider(create: (_) => NotificationsController()),
        ChangeNotifierProxyProvider<AuthController, JobsController>(
          create: (context) => JobsController(
            auth: context.read<AuthController>(),
          ),
          update: (_, _, previous) =>
              previous ?? JobsController(auth: AuthController()),
        ),
        ChangeNotifierProxyProvider<AuthController, PassiveAgentController>(
          create: (context) => PassiveAgentController(
            auth: context.read<AuthController>(),
          ),
          update: (_, _, previous) =>
              previous ?? PassiveAgentController(),
        ),
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

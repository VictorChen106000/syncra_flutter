import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/agent_chat/state/agent_chat_controller.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/resumes/state/resume_controller.dart';

class SyncraApp extends StatelessWidget {
  const SyncraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthController()),
        ChangeNotifierProvider(create: (_) => ResumeController()),
        ChangeNotifierProvider(create: (_) => AgentChatController()),
      ],
      child: Consumer<AuthController>(
        builder: (context, authController, _) {
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            title: 'Syncra',
            theme: AppTheme.lightTheme,
            routerConfig: AppRouter.router(authController),
          );
        },
      ),
    );
  }
}

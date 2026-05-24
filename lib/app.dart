import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_notifier.dart';
import 'shared/widgets/running_task_banner.dart';

class SyncraApp extends ConsumerWidget {
  const SyncraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Syncra',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      // Overlay the global running-task banner above every route so a
      // background task stays visible no matter where the user navigates.
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) Positioned.fill(child: child),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: RunningTaskBanner(),
            ),
          ],
        );
      },
    );
  }
}

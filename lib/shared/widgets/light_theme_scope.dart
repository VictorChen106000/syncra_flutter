import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Forces any subtree to render with the light theme regardless of the
/// app-wide [ThemeMode]. Used to lock unpolished screens to light while
/// dark mode is rolled out to the priority surfaces. Remove a wrap once a
/// screen has been fully dark-mode polished.
class LightThemeScope extends StatelessWidget {
  const LightThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(data: AppTheme.lightTheme, child: child);
  }
}

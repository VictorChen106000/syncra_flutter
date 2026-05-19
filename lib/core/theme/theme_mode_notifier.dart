import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent app-wide theme mode (light / dark / system).
///
/// Defaults to [ThemeMode.system] on first launch. Choice persists across
/// cold starts via `shared_preferences`. The toggle lives in Profile.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _prefsKey = 'syncra.themeMode';

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final mode = _parse(raw);
    if (mode != null && state != mode) state = mode;
  }

  Future<void> setMode(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _serialize(mode));
  }

  static ThemeMode? _parse(String? raw) {
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => null,
    };
  }

  static String _serialize(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

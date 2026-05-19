import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent developer-only feature gates.
///
/// Surfaces in Profile → Developer (only visible when `kDebugMode == true`).
/// Backed by `shared_preferences` so toggles survive hot restarts.
@immutable
class DevFlags {
  const DevFlags({
    this.skipOnboarding = false,
    this.skipMorningBrief = false,
    this.forceNotificationDot = false,
  });

  final bool skipOnboarding;
  final bool skipMorningBrief;
  final bool forceNotificationDot;

  DevFlags copyWith({
    bool? skipOnboarding,
    bool? skipMorningBrief,
    bool? forceNotificationDot,
  }) {
    return DevFlags(
      skipOnboarding: skipOnboarding ?? this.skipOnboarding,
      skipMorningBrief: skipMorningBrief ?? this.skipMorningBrief,
      forceNotificationDot: forceNotificationDot ?? this.forceNotificationDot,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DevFlags &&
          other.skipOnboarding == skipOnboarding &&
          other.skipMorningBrief == skipMorningBrief &&
          other.forceNotificationDot == forceNotificationDot;

  @override
  int get hashCode =>
      Object.hash(skipOnboarding, skipMorningBrief, forceNotificationDot);
}

class DevFlagsNotifier extends Notifier<DevFlags> {
  static const _kSkipOnboarding = 'syncra.dev.skipOnboarding';
  static const _kSkipMorningBrief = 'syncra.dev.skipMorningBrief';
  static const _kForceNotificationDot = 'syncra.dev.forceNotificationDot';

  @override
  DevFlags build() {
    _load();
    return const DevFlags();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = DevFlags(
      skipOnboarding: prefs.getBool(_kSkipOnboarding) ?? false,
      skipMorningBrief: prefs.getBool(_kSkipMorningBrief) ?? false,
      forceNotificationDot: prefs.getBool(_kForceNotificationDot) ?? false,
    );
    if (loaded != state) state = loaded;
  }

  Future<void> setSkipOnboarding(bool value) async {
    state = state.copyWith(skipOnboarding: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSkipOnboarding, value);
  }

  Future<void> setSkipMorningBrief(bool value) async {
    state = state.copyWith(skipMorningBrief: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSkipMorningBrief, value);
  }

  Future<void> setForceNotificationDot(bool value) async {
    state = state.copyWith(forceNotificationDot: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kForceNotificationDot, value);
  }
}

final devFlagsProvider = NotifierProvider<DevFlagsNotifier, DevFlags>(
  DevFlagsNotifier.new,
);

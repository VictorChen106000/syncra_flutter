import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent developer-only feature gates.
///
/// Surfaces in Profile → Developer (only visible when `kDebugMode == true`).
/// Backed by `shared_preferences` so toggles survive hot restarts.
@immutable
class DevFlags {
  const DevFlags({this.showOnboarding = false, this.showMorningBrief = false});

  /// When ON, the router force-routes the user to onboarding regardless of
  /// whether their profile already has a role. The page's submit handler
  /// auto-clears this flag so the user isn't trapped.
  final bool showOnboarding;

  /// When ON, the router force-routes the user to the morning brief even if
  /// it has already been marked shown. The page's Continue/Skip handler
  /// auto-clears this flag.
  final bool showMorningBrief;

  DevFlags copyWith({bool? showOnboarding, bool? showMorningBrief}) {
    return DevFlags(
      showOnboarding: showOnboarding ?? this.showOnboarding,
      showMorningBrief: showMorningBrief ?? this.showMorningBrief,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DevFlags &&
          other.showOnboarding == showOnboarding &&
          other.showMorningBrief == showMorningBrief;

  @override
  int get hashCode => Object.hash(showOnboarding, showMorningBrief);
}

class DevFlagsNotifier extends Notifier<DevFlags> {
  static const _kShowOnboarding = 'syncra.dev.showOnboarding';
  static const _kShowMorningBrief = 'syncra.dev.showMorningBrief';

  @override
  DevFlags build() {
    _load();
    return const DevFlags();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = DevFlags(
      showOnboarding: prefs.getBool(_kShowOnboarding) ?? false,
      showMorningBrief: prefs.getBool(_kShowMorningBrief) ?? false,
    );
    if (loaded != state) state = loaded;
  }

  Future<void> setShowOnboarding(bool value) async {
    state = state.copyWith(showOnboarding: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowOnboarding, value);
  }

  Future<void> setShowMorningBrief(bool value) async {
    state = state.copyWith(showMorningBrief: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowMorningBrief, value);
  }
}

final devFlagsProvider = NotifierProvider<DevFlagsNotifier, DevFlags>(
  DevFlagsNotifier.new,
);

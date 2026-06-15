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
    this.showOnboarding = false,
  });

  /// When ON, the router force-routes the user to onboarding regardless of
  /// whether their profile already has a role. The page's submit handler
  /// auto-clears this flag so the user isn't trapped.
  final bool showOnboarding;

  DevFlags copyWith({
    bool? showOnboarding,
  }) {
    return DevFlags(
      showOnboarding: showOnboarding ?? this.showOnboarding,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DevFlags && other.showOnboarding == showOnboarding;

  @override
  int get hashCode => showOnboarding.hashCode;
}

class DevFlagsNotifier extends Notifier<DevFlags> {
  static const _kShowOnboarding = 'syncra.dev.showOnboarding';

  @override
  DevFlags build() {
    _load();
    return const DevFlags();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = DevFlags(
      showOnboarding: prefs.getBool(_kShowOnboarding) ?? false,
    );
    if (loaded != state) state = loaded;
  }

  Future<void> setShowOnboarding(bool value) async {
    state = state.copyWith(showOnboarding: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowOnboarding, value);
  }
}

final devFlagsProvider = NotifierProvider<DevFlagsNotifier, DevFlags>(
  DevFlagsNotifier.new,
);

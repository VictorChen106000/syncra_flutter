import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the dashboard's "MY READ ON YOU" entrance (the type-out + the
/// auto roll-up) has already played for this user.
///
/// That reveal is a one-time welcome: it finishes the thought onboarding
/// started, so it should play once — on the first dashboard the user sees
/// after setup — and never again. Without this flag the animation replays
/// every time the user re-selects the Home tab, because the widget's State is
/// rebuilt on each visit. Persisted via `shared_preferences` so the intro
/// stays spent across cold starts, mirroring `themeModeProvider`.
class AgentReadIntroNotifier extends AsyncNotifier<bool> {
  static const _prefsKey = 'syncra.agentReadIntroPlayed';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  /// Marks the entrance as played so it never animates again. No-op once set.
  Future<void> markPlayed() async {
    if (state.value == true) return;
    state = const AsyncData(true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }
}

final agentReadIntroPlayedProvider =
    AsyncNotifierProvider<AgentReadIntroNotifier, bool>(
      AgentReadIntroNotifier.new,
    );

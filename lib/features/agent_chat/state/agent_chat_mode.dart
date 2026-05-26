import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the shared chat infrastructure is being used for right now.
///
/// The chatbot stack (service + notifier + widgets) is reused across the
/// dashboard chat *and* the first-time onboarding flow. The mode picks which
/// system prompt and tool registry the service is constructed with, and tells
/// the notifier whether to persist transcripts to Firestore.
enum AgentChatMode {
  /// Default. Full tool arsenal (search_jobs, tailor_resume, draft_email, …),
  /// transcripts persisted to `users/{uid}/conversations/{id}`, history
  /// drawer enabled.
  jobs,

  /// First-time setup. Minimal tool set (`ask_user` + `complete_onboarding`),
  /// no Firestore persistence, no history drawer. The agent's only goal is to
  /// capture the user's target role and emit an `OnboardingCompleteBlock`.
  onboarding,
}

/// The active [AgentChatMode]. The onboarding page flips this to
/// [AgentChatMode.onboarding] in `initState` and back to [AgentChatMode.jobs]
/// when the user taps the Enter Syncra card.
///
/// `agentServiceProvider` and `agentChatProvider` both ref.watch this — a
/// mode change rebuilds the service with the right system prompt + tools and
/// resets the chat state to the right opener.
final agentChatModeProvider =
    NotifierProvider<AgentChatModeNotifier, AgentChatMode>(
  AgentChatModeNotifier.new,
);

class AgentChatModeNotifier extends Notifier<AgentChatMode> {
  @override
  AgentChatMode build() => AgentChatMode.jobs;

  void set(AgentChatMode mode) {
    if (state == mode) return;
    state = mode;
  }
}

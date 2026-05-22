/// Starter prompts surfaced as dashboard cards and chat quick-replies.
/// Plain UI copy — no mock behavior attached.
class AgentPromptSuggestions {
  const AgentPromptSuggestions._();

  static const String discover =
      'Find UX roles at AI startups hiring this week';
  static const String tailor =
      'Tailor my resume for the Linear UX Designer role';
  static const String outreach =
      "Draft a cold outreach to Linear's hiring manager";
  static const String strategy = 'What roles match my current trajectory?';

  /// All four, in the order they appear on the dashboard.
  static const List<String> all = [discover, tailor, outreach, strategy];
}

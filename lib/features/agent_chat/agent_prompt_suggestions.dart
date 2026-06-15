/// Starter prompts surfaced as dashboard cards and chat quick-replies.
/// Plain UI copy — no mock behavior attached.
class AgentPromptSuggestions {
  const AgentPromptSuggestions._();

  static const String discover =
      'Find roles that fit my resume and rank the best matches';
  static const String tailor = 'Tailor my resume to the role that fits me best';
  static const String outreach =
      'Find a role I fit well and draft an outreach email';
  static const String strategy =
      'Review my resume for my strengths and biggest gaps';

  /// All four, in the order they appear on the dashboard.
  static const List<String> all = [discover, tailor, outreach, strategy];
}

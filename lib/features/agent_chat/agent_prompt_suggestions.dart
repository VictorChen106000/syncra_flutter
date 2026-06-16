/// Starter prompts surfaced as dashboard cards and chat quick-replies.
/// Plain UI copy — no mock behavior attached.
///
/// Three demo-tuned openers, each lighting up a distinct agentic path
/// end-to-end. On the default Auto-draft autonomy level these chain the whole
/// pipeline (search → match → tailor → draft) from a single tap and stop at the
/// human gates (Save résumé + tap Send).
class AgentPromptSuggestions {
  const AgentPromptSuggestions._();

  /// The headline: one tap runs the whole pipeline — search → match → tailor →
  /// draft — and stops ready-to-send. The "boom" card.
  static const String apply =
      'Find roles that fit my resume, tailor it for the best match, '
      'and draft the outreach';

  /// Lands on the tailored-changes diff — glowing edits, tap-to-see-why. The
  /// most visually premium moment, and rock-solid reliable.
  static const String tailor =
      'Tailor my resume to my best-matched role and show me what changed and why';

  /// Outreach: find a fitting role, then draft (and, on Autopilot, send) the
  /// email. Closes the loop end-to-end.
  static const String outreach =
      'Find a role I fit well, then draft my outreach email';

  /// All three, in the order they appear on the dashboard.
  static const List<String> all = [apply, tailor, outreach];
}

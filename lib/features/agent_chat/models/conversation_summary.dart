/// Lightweight header for a saved conversation — everything the history
/// drawer needs to render a row without loading the full transcript.
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  /// Firestore document id under `users/{uid}/conversations`.
  final String id;

  /// Short label, derived from the first user message.
  final String title;

  /// Last time the conversation received a message — the history sort key.
  final DateTime updatedAt;
}

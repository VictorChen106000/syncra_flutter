import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../data/firestore/firestore_paths.dart';
import '../../../data/models/job.dart';
import '../models/agent_block.dart';
import '../models/chat_message.dart';
import '../models/conversation_summary.dart';
import 'chat_snapshot_codec.dart';

/// Persists versioned chat transcript snapshots — one Firestore document per
/// conversation — so the history drawer can list and reopen past chats.
///
/// v2 stores the full recoverable chat UI model through [ChatSnapshotCodec]:
/// user bubbles, attachments, agent turns, tool rows, job cards, proposed
/// edits, resume drafts, input requests, action proposals, and email drafts.
///
/// Legacy v1 text-only documents are still supported by the same decoder.
class ChatHistoryRepository {
  ChatHistoryRepository({FirebaseFirestore? db})
    : _paths = FirestorePaths(db ?? FirebaseFirestore.instance);

  static const int schemaVersion = 2;

  final FirestorePaths _paths;

  DocumentReference<Map<String, dynamic>> _doc(String uid, String id) =>
      _paths.conversations(uid).doc(id);

  /// Live-updating list of conversation headers, most recently updated first.
  /// Powers the history drawer.
  Stream<List<ConversationSummary>> watchConversations(String uid) {
    return _paths
        .conversations(uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(_summaryOf)
              .whereType<ConversationSummary>()
              .toList(),
        );
  }

  /// One-shot read of the conversation headers — used to resume the most
  /// recent chat on a cold start without leaving a listener open.
  Future<List<ConversationSummary>> listConversations(String uid) async {
    final snap = await _paths
        .conversations(uid)
        .orderBy('updatedAt', descending: true)
        .get();
    return snap.docs.map(_summaryOf).whereType<ConversationSummary>().toList();
  }

  static ConversationSummary? _summaryOf(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final rawItems = _listValue(data, 'items');

    // Skip empty or fully malformed shells so the drawer never renders a
    // blank row. The codec keeps this compatible with both v1 and v2.
    if (rawItems.isEmpty) return null;

    final decodedItems = rawItems
        .map(ChatSnapshotCodec.decodeItem)
        .whereType<ChatItem>()
        .toList(growable: false);

    if (decodedItems.isEmpty) return null;

    final renamedTitle = _stringValue(data, 'renamedTitle')?.trim();
    final title = _stringValue(data, 'title')?.trim();
    final lastPreview = _stringValue(data, 'lastPreview')?.trim();
    final ts = data['updatedAt'];

    return ConversationSummary(
      id: doc.id,
      title: _displayTitle(renamedTitle, title, rawItems),
      preview: _displayPreview(lastPreview, decodedItems),
      updatedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      pinned: data['pinned'] == true,
    );
  }

  static String _displayTitle(
    String? renamedTitle,
    String? title,
    List<dynamic> rawItems,
  ) {
    if (renamedTitle != null && renamedTitle.isNotEmpty) {
      return renamedTitle;
    }
    if (title != null && title.isNotEmpty) return title;
    return _deriveTitleFromRaw(rawItems);
  }

  /// Fallback title for legacy docs written before `title` was stored.
  static String _deriveTitleFromRaw(List<dynamic> rawItems) {
    for (final entry in rawItems) {
      if (entry is! Map) continue;
      final kind = _stringValue(entry, 'kind')?.trim().toLowerCase();
      if (kind != 'user' && kind != 'user_message') continue;

      final text = _stringValue(entry, 'text')?.trim() ?? '';
      if (text.isEmpty) continue;
      return text.length > 48 ? '${text.substring(0, 48)}…' : text;
    }
    return 'New chat';
  }

  static String _displayPreview(String? storedPreview, List<ChatItem> items) {
    final cleanStored = _cleanPreview(storedPreview);
    if (cleanStored != null) return _clipPreview(cleanStored);
    return deriveConversationPreview(items);
  }

  static String deriveConversationPreview(List<ChatItem> items) {
    for (final item in items.reversed) {
      switch (item) {
        case UserMessage():
          final text = _cleanPreview(item.text);
          if (text != null) return 'You: ${_clipPreview(text)}';

        case AgentTurn():
          for (final block in item.blocks.reversed) {
            final preview = _previewForBlock(block);
            if (preview != null) return preview;
          }

          final error = _cleanPreview(item.errorMessage);
          if (error != null) return 'Error: ${_clipPreview(error)}';
      }
    }

    return '';
  }

  static String? _previewForBlock(AgentBlock block) {
    switch (block) {
      case ThinkingBlock():
        return null;

      case TextBlock():
        final text = _cleanPreview(block.text);
        return text == null ? null : _clipPreview(text);

      case ToolCallBlock():
        final result = _cleanPreview(block.resultSummary);
        if (result != null) return 'Tool result: ${_clipPreview(result)}';

        final label = _cleanPreview(block.label);
        return label == null ? null : 'Tool: ${_clipPreview(label)}';

      case JobsBlock():
        if (block.jobs.isEmpty) return null;
        final label = block.jobs.length == 1 ? 'match' : 'matches';
        return 'Showed ${block.jobs.length} job $label';

      case ProposedEditsBlock():
        final stateLabel = switch (block.state) {
          ProposedEditsState.reviewing => 'for review',
          ProposedEditsState.applying => 'rendering',
          ProposedEditsState.applied => 'preview ready',
          ProposedEditsState.dismissed => 'dismissed',
        };
        final label = block.edits.length == 1 ? 'change' : 'changes';
        return 'Resume edits $stateLabel · ${block.edits.length} $label';

      case ResumeDraftBlock():
        final prefix = switch (block.state) {
          ResumeDraftState.rendering => 'Rendering resume draft',
          ResumeDraftState.ready => 'Resume draft ready',
        };
        return '$prefix: ${_clipPreview(block.fileName)}';

      case InputRequestBlock():
        if (block.state == InputRequestState.answered) {
          final answer = _cleanPreview(block.answer);
          if (answer != null) return 'Answered: ${_clipPreview(answer)}';
        }
        return 'Asked: ${_clipPreview(block.question)}';

      case ActionProposalBlock():
        return 'Action proposal: ${_clipPreview(block.title)}';

      case EmailDraftBlock():
        return 'Email draft: ${_clipPreview(block.subject)}';
    }
  }

  static String? _cleanPreview(String? value) {
    final clean = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean == null || clean.isEmpty) return null;
    return clean;
  }

  static String _clipPreview(String value, {int max = 96}) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length <= max) return clean;
    return '${clean.substring(0, max)}…';
  }

  Future<List<ChatItem>> load(String uid, String conversationId) async {
    return (await loadConversation(uid, conversationId)).items;
  }

  Future<SavedConversation> loadConversation(
    String uid,
    String conversationId,
  ) async {
    final snap = await _doc(uid, conversationId).get();
    return SavedConversation.fromMap(snap.data());
  }

  Future<void> save(
    String uid,
    String conversationId, {
    required List<ChatItem> items,
    required String title,
    Job? threadJob,
    List<Map<String, dynamic>> agentMessages = const [],
  }) async {
    final payload = _encode(items);
    if (payload.isEmpty) return;

    await _doc(uid, conversationId).set({
      'schemaVersion': schemaVersion,
      'items': payload,
      'title': title,
      'lastPreview': deriveConversationPreview(items),
      'threadJob': threadJob == null
          ? FieldValue.delete()
          : _encodeThreadJob(threadJob),
      'agentContext': _encodeAgentContext(agentMessages),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Firestore document hard-caps at ~1 MB. The verbatim Anthropic history can
  /// carry full job/resume JSON in its tool_results, so cap the serialized
  /// blob well under that; over the cap (or on encode failure) we store nothing
  /// and the loader falls back to the lossy UI-snapshot summary.
  static const int _maxAgentContextChars = 700000;

  /// Serializes the verbatim Anthropic message history to a JSON string. Stored
  /// as a string rather than a structured field to sidestep Firestore's
  /// no-nested-arrays limit (assistant turns are arrays of content blocks).
  /// Returns a [FieldValue.delete] sentinel when there's nothing safe to store
  /// so a stale blob never lingers on the doc.
  static Object _encodeAgentContext(List<Map<String, dynamic>> messages) {
    if (messages.isEmpty) return FieldValue.delete();
    try {
      final encoded = jsonEncode(messages);
      if (encoded.length > _maxAgentContextChars) return FieldValue.delete();
      return encoded;
    } catch (_) {
      return FieldValue.delete();
    }
  }

  /// Decodes the verbatim Anthropic history saved by [_encodeAgentContext].
  /// Returns an empty list for legacy docs (no `agentContext`) or anything
  /// unparseable, signalling the caller to fall back to the summary restore.
  static List<Map<String, dynamic>> _decodeAgentContext(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> rename(
    String uid,
    String conversationId, {
    required String title,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return;
    await _doc(
      uid,
      conversationId,
    ).update({'title': cleanTitle, 'renamedTitle': cleanTitle});
  }

  Future<void> setPinned(
    String uid,
    String conversationId, {
    required bool pinned,
  }) async {
    await _doc(uid, conversationId).update({'pinned': pinned});
  }

  Future<void> delete(String uid, String conversationId) async {
    await _doc(uid, conversationId).delete();
  }

  static Map<String, dynamic> _encodeThreadJob(Job job) {
    return job.toJson();
  }

  static Job? _decodeThreadJob(Object? raw) {
    if (raw is! Map) return null;
    try {
      return Job.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  static List<ChatItem> _decode(List<dynamic> raw) {
    return raw
        .map(ChatSnapshotCodec.decodeItem)
        .whereType<ChatItem>()
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _encode(List<ChatItem> items) {
    final payload = <Map<String, dynamic>>[];

    for (final item in items) {
      // Do not persist the empty initial assistant turn used only to keep the
      // empty chat shell mounted.
      if (item is AgentTurn && item.blocks.isEmpty) continue;

      payload.add(ChatSnapshotCodec.encodeItem(item));
    }

    return payload;
  }

  static String? _stringValue(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    return value is String ? value : null;
  }

  static List<dynamic> _listValue(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    return value is List ? value : const [];
  }
}

class SavedConversation {
  const SavedConversation({
    required this.items,
    this.threadJob,
    this.agentMessages = const [],
  });

  factory SavedConversation.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const SavedConversation(items: []);

    return SavedConversation(
      items: ChatHistoryRepository._decode(
        ChatHistoryRepository._listValue(data, 'items'),
      ),
      threadJob: ChatHistoryRepository._decodeThreadJob(data['threadJob']),
      agentMessages: ChatHistoryRepository._decodeAgentContext(
        data['agentContext'],
      ),
    );
  }

  final List<ChatItem> items;
  final Job? threadJob;

  /// The verbatim Anthropic message history, when the snapshot saved one.
  /// Empty for legacy/oversized transcripts — callers fall back to rebuilding
  /// a summary context from [items].
  final List<Map<String, dynamic>> agentMessages;
}

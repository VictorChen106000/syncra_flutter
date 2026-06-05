import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../data/firestore/firestore_paths.dart';
import '../../../data/models/job.dart';
import '../models/agent_block.dart';
import '../models/chat_message.dart';
import '../models/conversation_summary.dart';

/// Persists *text-only* snapshots of chat transcripts — one Firestore document
/// per conversation — so the history drawer can list and reopen past chats as
/// readable transcripts.
///
/// The full reasoning timeline (thinking, tool calls, action proposals, resume
/// diffs, and email draft buttons) is deliberately *not* round-tripped — it's
/// transient by design and rebuilding the exact UI state from JSON is more
/// failure surface than this demo needs.
///
/// Schema: `users/{uid}/conversations/{conversationId}` — each doc holds:
///   - `title`: short label derived from the first user message
///   - `renamedTitle`: optional user-provided title override
///   - `pinned`: optional bool; missing means unpinned
///   - `threadJob`: optional job context for conversations opened from a job
///   - `updatedAt`: server timestamp (also the history sort key)
///   - `items`: [{ kind: 'user'|'agent', id, text, attachments? }]
class ChatHistoryRepository {
  ChatHistoryRepository({FirebaseFirestore? db})
    : _paths = FirestorePaths(db ?? FirebaseFirestore.instance);

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
    // Skip empty shells so the drawer never renders a blank row.
    if (rawItems.isEmpty) return null;
    final renamedTitle = (data['renamedTitle'] as String?)?.trim();
    final title = (data['title'] as String?)?.trim();
    final ts = data['updatedAt'];
    return ConversationSummary(
      id: doc.id,
      title: _displayTitle(renamedTitle, title, rawItems),
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
      if (entry is Map && entry['kind'] == 'user') {
        final text = (entry['text'] as String?)?.trim() ?? '';
        if (text.isNotEmpty) return text;
      }
    }
    return 'New chat';
  }

  Future<List<ChatItem>> load(String uid, String conversationId) async {
    return (await loadConversation(uid, conversationId)).items;
  }

  Future<SavedConversation> loadConversation(
    String uid,
    String conversationId,
  ) async {
    final snap = await _doc(uid, conversationId).get();
    final data = snap.data();
    return SavedConversation.fromMap(data);
  }

  Future<void> save(
    String uid,
    String conversationId, {
    required List<ChatItem> items,
    required String title,
    Job? threadJob,
  }) async {
    final payload = _encode(items);
    if (payload.isEmpty) return;
    await _doc(uid, conversationId).set({
      'items': payload,
      'title': title,
      'threadJob': threadJob == null
          ? FieldValue.delete()
          : _encodeThreadJob(threadJob),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    final items = <ChatItem>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final kind = _stringValue(entry, 'kind');
      final id = _stringValue(entry, 'id');
      if (id == null || id.trim().isEmpty) continue;
      switch (kind) {
        case 'user':
          final text = _stringValue(entry, 'text')?.trim();
          if (text == null || text.isEmpty) continue;
          items.add(
            UserMessage(
              id: id,
              text: text,
              attachments: _decodeAttachments(entry['attachments']),
            ),
          );
        case 'agent':
          final text = _agentText(entry);
          if (text == null || text.isEmpty) continue;
          items.add(
            AgentTurn(
              id: id,
              blocks: [TextBlock(id: '$id-text', text: text)],
              status: AgentTurnStatus.done,
            ),
          );
      }
    }
    return items;
  }

  static String? _stringValue(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    return value is String ? value : null;
  }

  static List<dynamic> _listValue(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    return value is List ? value : const [];
  }

  static List<ChatAttachment> _decodeAttachments(Object? raw) {
    if (raw is! List) return const [];
    final attachments = <ChatAttachment>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = _stringValue(entry, 'id')?.trim();
      final name = _stringValue(entry, 'name')?.trim();
      if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
      attachments.add(ChatAttachment(id: id, name: name));
    }
    return attachments;
  }

  static String? _agentText(Map<dynamic, dynamic> map) {
    final text = _stringValue(map, 'text')?.trim();
    if (text != null && text.isNotEmpty) return text;

    final blocks = map['blocks'];
    if (blocks is! List) return null;

    final buffer = StringBuffer();
    for (final block in blocks) {
      if (block is! Map) continue;
      final kind = (_stringValue(block, 'kind') ?? _stringValue(block, 'type'))
          ?.trim()
          .toLowerCase();
      if (kind != null && kind != 'text' && kind != 'textblock') continue;

      final blockText = _stringValue(block, 'text')?.trim();
      if (blockText == null || blockText.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(blockText);
    }

    final value = buffer.toString();
    return value.isEmpty ? null : value;
  }

  static List<Map<String, dynamic>> _encode(List<ChatItem> items) {
    final payload = <Map<String, dynamic>>[];
    for (final item in items) {
      switch (item) {
        case UserMessage():
          payload.add({
            'kind': 'user',
            'id': item.id,
            'text': item.text,
            if (item.attachments.isNotEmpty)
              'attachments': [
                for (final a in item.attachments) {'id': a.id, 'name': a.name},
              ],
          });
        case AgentTurn():
          // Skip turns that are still streaming or failed — only completed
          // text-only summaries persist.
          if (item.status != AgentTurnStatus.done &&
              item.status != AgentTurnStatus.stopped) {
            continue;
          }
          final buf = StringBuffer();
          for (final block in item.blocks) {
            if (block is TextBlock) {
              if (buf.isNotEmpty) buf.write('\n\n');
              buf.write(block.text);
            }
          }
          final text = buf.toString();
          if (text.isEmpty) continue;
          payload.add({'kind': 'agent', 'id': item.id, 'text': text});
      }
    }
    return payload;
  }
}

class SavedConversation {
  const SavedConversation({required this.items, this.threadJob});

  factory SavedConversation.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const SavedConversation(items: []);
    return SavedConversation(
      items: ChatHistoryRepository._decode(
        ChatHistoryRepository._listValue(data, 'items'),
      ),
      threadJob: ChatHistoryRepository._decodeThreadJob(data['threadJob']),
    );
  }

  final List<ChatItem> items;
  final Job? threadJob;
}

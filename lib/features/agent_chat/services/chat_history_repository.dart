import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../data/firestore/firestore_paths.dart';
import '../../../data/models/job.dart';
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
    // blank row. The codec check keeps this compatible with both v1 and v2.
    if (rawItems.isEmpty) return null;
    final hasRecoverableItem = rawItems.any(
      (entry) => ChatSnapshotCodec.decodeItem(entry) != null,
    );
    if (!hasRecoverableItem) return null;

    final renamedTitle = _stringValue(data, 'renamedTitle')?.trim();
    final title = _stringValue(data, 'title')?.trim();
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
      if (entry is! Map) continue;
      final kind = _stringValue(entry, 'kind')?.trim().toLowerCase();
      if (kind != 'user' && kind != 'user_message') continue;

      final text = _stringValue(entry, 'text')?.trim() ?? '';
      if (text.isEmpty) continue;
      return text.length > 48 ? '${text.substring(0, 48)}…' : text;
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
    return SavedConversation.fromMap(snap.data());
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
      'schemaVersion': schemaVersion,
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

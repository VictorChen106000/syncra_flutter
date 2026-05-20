import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../data/firestore/firestore_paths.dart';
import '../models/agent_block.dart';
import '../models/chat_message.dart';

/// Persists a *text-only* snapshot of the chat transcript so it survives app
/// restarts. The full reasoning timeline (thinking, tool calls, action
/// proposals) is deliberately *not* round-tripped — it's transient by design
/// and reconstructing the exact UI state from JSON is more failure surface
/// than this demo needs.
///
/// Schema: `users/{uid}/conversations/active` — single doc with:
///   - `updatedAt`: server timestamp
///   - `items`: [{ kind: 'user'|'agent', id, text, attachments? }]
class ChatHistoryRepository {
  ChatHistoryRepository({FirebaseFirestore? db})
      : _paths = FirestorePaths(db ?? FirebaseFirestore.instance);

  final FirestorePaths _paths;

  static const _docId = 'active';

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _paths.conversations(uid).doc(_docId);

  Future<List<ChatItem>> load(String uid) async {
    final snap = await _doc(uid).get();
    final data = snap.data();
    if (data == null) return const [];
    final raw = (data['items'] as List?) ?? const [];
    final items = <ChatItem>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = entry.cast<String, dynamic>();
      final kind = map['kind'] as String?;
      final id = map['id'] as String?;
      final text = (map['text'] as String?) ?? '';
      if (id == null || text.isEmpty) continue;
      switch (kind) {
        case 'user':
          final attachmentList =
              (map['attachments'] as List?) ?? const [];
          final attachments = <ChatAttachment>[
            for (final a in attachmentList)
              if (a is Map &&
                  a['id'] is String &&
                  a['name'] is String)
                ChatAttachment(
                  id: a['id'] as String,
                  name: a['name'] as String,
                ),
          ];
          items.add(UserMessage(
            id: id,
            text: text,
            attachments: attachments,
          ));
        case 'agent':
          items.add(AgentTurn(
            id: id,
            blocks: [TextBlock(id: '$id-text', text: text)],
            status: AgentTurnStatus.done,
          ));
      }
    }
    return items;
  }

  Future<void> save(String uid, List<ChatItem> items) async {
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
                for (final a in item.attachments)
                  {'id': a.id, 'name': a.name},
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
          payload.add({
            'kind': 'agent',
            'id': item.id,
            'text': text,
          });
      }
    }
    await _doc(uid).set({
      'items': payload,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> clear(String uid) async {
    await _doc(uid).delete();
  }
}

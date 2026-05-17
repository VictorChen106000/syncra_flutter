import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

class ResumeSessionStorage {
  const ResumeSessionStorage._();

  static String _key(String uid, String resumeId) {
    return 'syncra_resume_bytes:$uid:$resumeId';
  }

  static String _prefix(String uid) {
    return 'syncra_resume_bytes:$uid:';
  }

  static Future<void> saveBytes({
    required String uid,
    required String resumeId,
    required Uint8List bytes,
  }) async {
    try {
      html.window.sessionStorage[_key(uid, resumeId)] = base64Encode(bytes);
    } catch (_) {
      // Browser storage can fail if the file is too large.
      // Upload still succeeds; preview just will not survive reload.
    }
  }

  static Future<Uint8List?> readBytes({
    required String uid,
    required String resumeId,
  }) async {
    try {
      final encoded = html.window.sessionStorage[_key(uid, resumeId)];
      if (encoded == null || encoded.isEmpty) return null;
      return Uint8List.fromList(base64Decode(encoded));
    } catch (_) {
      await removeBytes(uid: uid, resumeId: resumeId);
      return null;
    }
  }

  static Future<void> removeBytes({
    required String uid,
    required String resumeId,
  }) async {
    html.window.sessionStorage.remove(_key(uid, resumeId));
  }

  static Future<void> clearForUser(String uid) async {
    final storage = html.window.sessionStorage;
    final prefix = _prefix(uid);

    final keysToRemove = storage.keys
        .where((key) => key.startsWith(prefix))
        .toList();

    for (final key in keysToRemove) {
      storage.remove(key);
    }
  }
}
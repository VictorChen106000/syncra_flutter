import 'dart:typed_data';

class ResumeSessionStorage {
  const ResumeSessionStorage._();

  static Future<void> saveBytes({
    required String uid,
    required String resumeId,
    required Uint8List bytes,
  }) async {}

  static Future<Uint8List?> readBytes({
    required String uid,
    required String resumeId,
  }) async {
    return null;
  }

  static Future<void> removeBytes({
    required String uid,
    required String resumeId,
  }) async {}

  static Future<void> clearForUser(String uid) async {}
}
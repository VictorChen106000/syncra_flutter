import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../features/resumes/models/resume_file.dart';
import 'firestore_paths.dart';

/// Stores resume **metadata** in Firestore and the actual **PDF/DOC bytes**
/// in Firebase Storage at `users/{uid}/resumes/{resumeId}.{ext}`. The two
/// writes are coordinated so a Firestore doc only ever points at bytes
/// that successfully landed in Storage.
class ResumesRepository {
  ResumesRepository({FirebaseFirestore? db, FirebaseStorage? storage})
      : _paths = FirestorePaths(db ?? FirebaseFirestore.instance),
        _storage = storage ?? FirebaseStorage.instance;

  final FirestorePaths _paths;
  final FirebaseStorage _storage;

  Stream<List<ResumeFile>> watchResumes(String uid) {
    return _paths
        .resumes(uid)
        .orderBy('uploaded_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(_fromDoc).toList());
  }

  Future<ResumeFile> uploadResume({
    required String uid,
    required String name,
    required Uint8List bytes,
    required String contentType,
    ResumeSource source = ResumeSource.manual,
    void Function(int percent)? onProgress,
  }) async {
    final docRef = _paths.resumes(uid).doc();
    final storagePath =
        _storagePathFor(uid: uid, resumeId: docRef.id, name: name);

    await _uploadBytesToStorage(
      path: storagePath,
      bytes: bytes,
      contentType: contentType,
      onProgress: onProgress,
    );

    final uploadedAt = DateTime.now();
    try {
      await docRef.set({
        'name': name,
        'size': bytes.length,
        'mime_type': contentType,
        'source': source == ResumeSource.tailored ? 'tailored' : 'manual',
        'storage_path': storagePath,
        'uploaded_at': Timestamp.fromDate(uploadedAt),
      });
    } catch (_) {
      // Firestore write failed — clean up the orphaned blob so we don't
      // leak bytes that no UI can ever reach.
      await _safeDeleteBlob(storagePath);
      rethrow;
    }

    return ResumeFile(
      id: docRef.id,
      name: name,
      size: bytes.length,
      type: contentType,
      uploadedAt: uploadedAt,
      source: source,
      storagePath: storagePath,
    );
  }

  Future<void> deleteResume({
    required String uid,
    required String resumeId,
    String? storagePath,
  }) async {
    await _paths.resumes(uid).doc(resumeId).delete();
    if (storagePath != null && storagePath.isNotEmpty) {
      await _safeDeleteBlob(storagePath);
    }
  }

  Future<ResumeFile> saveGeneratedResume({
    required String uid,
    required String name,
    required Uint8List bytes,
    String contentType = 'application/pdf',
    String? parentResumeId,
    String? tailoredForJobId,
  }) async {
    final docRef = _paths.resumes(uid).doc();
    final storagePath =
        _storagePathFor(uid: uid, resumeId: docRef.id, name: name);

    await _uploadBytesToStorage(
      path: storagePath,
      bytes: bytes,
      contentType: contentType,
    );

    final uploadedAt = DateTime.now();
    try {
      await docRef.set({
        'name': name,
        'size': bytes.length,
        'mime_type': contentType,
        'source': 'tailored',
        'storage_path': storagePath,
        'uploaded_at': Timestamp.fromDate(uploadedAt),
        'parent_resume_id': ?parentResumeId,
        'tailored_for_job_id': ?tailoredForJobId,
      });
    } catch (_) {
      await _safeDeleteBlob(storagePath);
      rethrow;
    }

    return ResumeFile(
      id: docRef.id,
      name: name,
      size: bytes.length,
      type: contentType,
      uploadedAt: uploadedAt,
      source: ResumeSource.tailored,
      storagePath: storagePath,
      parentResumeId: parentResumeId,
    );
  }

  /// Download the PDF/DOC bytes for [storagePath]. Returns `null` if the
  /// blob is missing (e.g. legacy Firestore doc from before the migration).
  Future<Uint8List?> downloadBytes(String storagePath) async {
    try {
      return await _storage.ref(storagePath).getData(
            // Storage rules cap uploads at 5MB; allow slack for tailored
            // PDFs that may grow slightly after rendering.
            10 * 1024 * 1024,
          );
    } on FirebaseException {
      return null;
    }
  }

  Future<void> _uploadBytesToStorage({
    required String path,
    required Uint8List bytes,
    required String contentType,
    void Function(int percent)? onProgress,
  }) async {
    final task = _storage.ref(path).putData(
          bytes,
          SettableMetadata(contentType: contentType),
        );

    // Stream real byte-transfer progress, capped at 95% — the final 5% is
    // reserved for the Firestore metadata write the caller does next, so the
    // bar never reads 100% before the resume is actually queryable.
    if (onProgress != null) {
      task.snapshotEvents.listen(
        (snapshot) {
          final total = snapshot.totalBytes;
          if (total <= 0) return;
          final pct = (snapshot.bytesTransferred / total * 95).round();
          onProgress(pct.clamp(0, 95));
        },
        // Swallow stream errors — the awaited task below surfaces the real
        // failure with a proper stack, so a duplicate throw here is noise.
        onError: (_) {},
      );
    }

    await task;
  }

  Future<void> _safeDeleteBlob(String storagePath) async {
    try {
      await _storage.ref(storagePath).delete();
    } catch (_) {
      // Best-effort. A leaked blob is harmless; the Firestore doc drives UI.
    }
  }

  String _storagePathFor({
    required String uid,
    required String resumeId,
    required String name,
  }) {
    return 'users/$uid/resumes/$resumeId${_extensionFor(name)}';
  }

  String _extensionFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return '.pdf';
    if (lower.endsWith('.docx')) return '.docx';
    if (lower.endsWith('.doc')) return '.doc';
    return '';
  }
}

ResumeFile _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  return ResumeFile(
    id: doc.id,
    name: (data['name'] as String?) ?? 'Untitled',
    size: (data['size'] as num?)?.toInt() ?? 0,
    type: (data['mime_type'] as String?) ?? 'application/octet-stream',
    uploadedAt: _toDate(data['uploaded_at']) ?? DateTime.now(),
    source: (data['source'] as String?) == 'tailored'
        ? ResumeSource.tailored
        : ResumeSource.manual,
    storagePath: data['storage_path'] as String?,
    parentResumeId: data['parent_resume_id'] as String?,
  );
}

DateTime? _toDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

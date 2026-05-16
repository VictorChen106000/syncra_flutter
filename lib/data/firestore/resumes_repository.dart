import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/resumes/models/resume_file.dart';
import 'firestore_paths.dart';

/// Stores resume **metadata** in Firestore and the actual **PDF bytes** in
/// the app's documents directory on the device. Firebase Storage is not
/// used — keeps the project on the free Spark plan.
class ResumesRepository {
  ResumesRepository({FirebaseFirestore? db})
      : _paths = FirestorePaths(db ?? FirebaseFirestore.instance);

  final FirestorePaths _paths;

  /// Stream the user's resumes. Each emitted [ResumeFile] has [path]
  /// populated when the file exists on this device.
  Stream<List<ResumeFile>> watchResumes(String uid) {
    return _paths
        .resumes(uid)
        .orderBy('uploaded_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(_fromDoc).toList());
  }

  /// Persists [bytes] to local disk + writes a Firestore doc with the
  /// metadata + local file path. Returns the newly created [ResumeFile]
  /// with [path] and [bytes] populated for immediate preview.
  Future<ResumeFile> uploadResume({
    required String uid,
    required String name,
    required Uint8List bytes,
    required String contentType,
    ResumeSource source = ResumeSource.manual,
  }) async {
    final docRef = _paths.resumes(uid).doc();
    final localPath = await _writeBytesToAppDocs(
      resumeId: docRef.id,
      name: name,
      bytes: bytes,
    );
    final uploadedAt = DateTime.now();

    await docRef.set({
      'name': name,
      'size': bytes.length,
      'mime_type': contentType,
      'source': source == ResumeSource.tailored ? 'tailored' : 'manual',
      'local_path': localPath,
      'uploaded_at': Timestamp.fromDate(uploadedAt),
    });

    return ResumeFile(
      id: docRef.id,
      name: name,
      size: bytes.length,
      type: contentType,
      uploadedAt: uploadedAt,
      source: source,
      path: localPath,
      bytes: bytes,
    );
  }

  /// Deletes the Firestore doc and the local file (if present). Safe to
  /// call even when the local file is missing.
  Future<void> deleteResume({
    required String uid,
    required String resumeId,
    String? localPath,
  }) async {
    if (localPath != null && localPath.isNotEmpty) {
      try {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Ignore — Firestore deletion below is what drives the UI.
      }
    }
    await _paths.resumes(uid).doc(resumeId).delete();
  }

  /// Persists already-rendered PDF [bytes] (e.g. a tailored output) as a
  /// new resume under [uid]. Skips the file picker path entirely.
  Future<ResumeFile> saveGeneratedResume({
    required String uid,
    required String name,
    required Uint8List bytes,
    String contentType = 'application/pdf',
    String? parentResumeId,
    String? tailoredForJobId,
  }) async {
    final docRef = _paths.resumes(uid).doc();
    final localPath = await _writeBytesToAppDocs(
      resumeId: docRef.id,
      name: name,
      bytes: bytes,
    );
    final uploadedAt = DateTime.now();

    await docRef.set({
      'name': name,
      'size': bytes.length,
      'mime_type': contentType,
      'source': 'tailored',
      'local_path': localPath,
      'uploaded_at': Timestamp.fromDate(uploadedAt),
      'parent_resume_id': ?parentResumeId,
      'tailored_for_job_id': ?tailoredForJobId,
    });

    return ResumeFile(
      id: docRef.id,
      name: name,
      size: bytes.length,
      type: contentType,
      uploadedAt: uploadedAt,
      source: ResumeSource.tailored,
      path: localPath,
      bytes: bytes,
    );
  }

  Future<String> _writeBytesToAppDocs({
    required String resumeId,
    required String name,
    required Uint8List bytes,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final resumesDir = Directory('${docsDir.path}/resumes');
    if (!await resumesDir.exists()) {
      await resumesDir.create(recursive: true);
    }
    final ext = _extensionFor(name);
    final filePath = '${resumesDir.path}/$resumeId$ext';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return filePath;
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
    path: data['local_path'] as String?,
  );
}

DateTime? _toDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

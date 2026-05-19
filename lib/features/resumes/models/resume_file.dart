enum ResumeSource {
  manual,
  tailored,
}

class ResumeFile {
  const ResumeFile({
    required this.id,
    required this.name,
    required this.size,
    required this.type,
    required this.uploadedAt,
    required this.source,
    this.storagePath,
  });

  final String id;
  final String name;
  final int size;
  final String type;
  final DateTime uploadedAt;
  final ResumeSource source;

  /// Path of the blob inside the Firebase Storage bucket
  /// (e.g. `users/{uid}/resumes/{resumeId}.pdf`). `null` only for legacy
  /// docs created before the Storage migration.
  final String? storagePath;

  bool get isPdf =>
      type == 'application/pdf' || name.toLowerCase().endsWith('.pdf');

  bool get hasStorageBlob => storagePath != null && storagePath!.isNotEmpty;
}

import 'dart:typed_data';

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
    this.path,
    this.bytes,
  });

  final String id;
  final String name;
  final int size;
  final String type;
  final DateTime uploadedAt;
  final ResumeSource source;

  /// Absolute path to the PDF on this device, under the app's documents
  /// directory. May be `null` if the resume was uploaded from a different
  /// device (the Firestore metadata exists, the local file doesn't).
  final String? path;

  /// In-memory bytes — set immediately after upload so the preview screen
  /// can render without a disk round-trip. Subsequent loads use `path`.
  final Uint8List? bytes;

  bool get isPdf =>
      type == 'application/pdf' || name.toLowerCase().endsWith('.pdf');

  bool get isAvailableLocally =>
      bytes != null || (path != null && path!.isNotEmpty);
}

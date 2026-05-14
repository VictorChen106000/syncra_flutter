import 'dart:typed_data';

enum ResumeSource {
  manual,
  syncraAi,
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
  final String? path;
  final Uint8List? bytes;

  bool get isPdf => type == 'application/pdf' || name.toLowerCase().endsWith('.pdf');
}

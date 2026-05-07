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
  });

  final String id;
  final String name;
  final int size;
  final String type;
  final DateTime uploadedAt;
  final ResumeSource source;
  final String? path;

  bool get isPdf => type == 'application/pdf' || name.toLowerCase().endsWith('.pdf');
}

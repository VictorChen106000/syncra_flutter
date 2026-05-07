class FileFormatter {
  const FileFormatter._();

  static String size(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String cleanName(String name) {
    return name.replaceAll(RegExp(r'\.(pdf|docx?|PDF|DOCX?)$'), '');
  }
}

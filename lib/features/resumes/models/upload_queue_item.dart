class UploadQueueItem {
  const UploadQueueItem({
    required this.id,
    required this.name,
    required this.size,
    required this.progress,
    this.error,
  });

  final String id;
  final String name;
  final int size;
  final int progress;
  final String? error;

  bool get hasError => error != null;
}

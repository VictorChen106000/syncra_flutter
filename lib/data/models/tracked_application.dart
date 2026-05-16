import 'job.dart';

class TrackedApplicationNote {
  const TrackedApplicationNote({required this.body, required this.createdAt});

  final String body;
  final DateTime createdAt;
}

class TrackedApplication {
  const TrackedApplication({
    required this.id,
    required this.job,
    required this.status,
    required this.submittedLabel,
    required this.lastUpdate,
    this.nextStep,
    this.notes = const [],
  });

  final String id;
  final Job job;
  final JobStatus status;
  final String submittedLabel;
  final String lastUpdate;
  final String? nextStep;
  final List<TrackedApplicationNote> notes;

  TrackedApplication copyWith({
    JobStatus? status,
    String? lastUpdate,
    String? nextStep,
    List<TrackedApplicationNote>? notes,
  }) {
    return TrackedApplication(
      id: id,
      job: job,
      status: status ?? this.status,
      submittedLabel: submittedLabel,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      nextStep: nextStep ?? this.nextStep,
      notes: notes ?? this.notes,
    );
  }
}

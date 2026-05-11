import '../models/job.dart';

abstract class JobsRepository {
  Future<List<Job>> getApprovalQueue();
  Future<List<Job>> getHistory();
  Future<void> approveJob(String jobId);
  Future<void> dismissJob(String jobId);
  Future<void> undoAction(String jobId);
}

import '../../core/network/api_client.dart';
import '../models/job.dart';
import '../repositories/jobs_repository.dart';

class JobsService implements JobsRepository {
  JobsService(this._client);

  final ApiClient _client;

  @override
  Future<List<Job>> getApprovalQueue() async {
    final json = await _client.get('/jobs/queue');
    final list = json['data'] as List;
    return list.map((e) => Job.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<Job>> getHistory() async {
    final json = await _client.get('/jobs/history');
    final list = json['data'] as List;
    return list.map((e) => Job.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> approveJob(String jobId) async {
    await _client.post('/jobs/$jobId/approve', {});
  }

  @override
  Future<void> dismissJob(String jobId) async {
    await _client.delete('/jobs/$jobId');
  }

  @override
  Future<void> undoAction(String jobId) async {
    await _client.post('/jobs/$jobId/undo', {});
  }
}

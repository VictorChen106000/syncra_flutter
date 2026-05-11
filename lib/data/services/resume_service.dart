import '../../core/network/api_client.dart';
import '../../features/resumes/models/resume_file.dart';
import '../repositories/resume_repository.dart';

class ResumeService implements ResumeRepository {
  ResumeService(this._client);

  final ApiClient _client;

  @override
  Future<List<ResumeFile>> getUploads() async {
    final json = await _client.get('/resumes/uploads');
    final list = json['data'] as List;
    return list.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<ResumeFile>> getTailored() async {
    final json = await _client.get('/resumes/tailored');
    final list = json['data'] as List;
    return list.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<ResumeFile> upload(String filePath, String mimeType) async {
    final json = await _client.post('/resumes/upload', {
      'file_path': filePath,
      'mime_type': mimeType,
    });
    return _fromJson(json);
  }

  @override
  Future<void> delete(String resumeId) async {
    await _client.delete('/resumes/$resumeId');
  }

  @override
  Future<ResumeFile> tailorForJob(String resumeId, String jobId) async {
    final json = await _client.post('/resumes/$resumeId/tailor', {
      'job_id': jobId,
    });
    return _fromJson(json);
  }

  ResumeFile _fromJson(Map<String, dynamic> json) => ResumeFile(
        id: json['id'] as String,
        name: json['name'] as String,
        size: json['size'] as int,
        type: json['mime_type'] as String,
        uploadedAt: DateTime.parse(json['uploaded_at'] as String),
        source: json['source'] == 'syncra_ai'
            ? ResumeSource.syncraAi
            : json['source'] == 'tailored'
                ? ResumeSource.tailored
                : ResumeSource.manual,
        path: json['path'] as String?,
      );
}

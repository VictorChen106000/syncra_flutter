import '../../features/resumes/models/resume_file.dart';

abstract class ResumeRepository {
  Future<List<ResumeFile>> getUploads();
  Future<List<ResumeFile>> getTailored();
  Future<ResumeFile> upload(String filePath, String mimeType);
  Future<void> delete(String resumeId);
  Future<ResumeFile> tailorForJob(String resumeId, String jobId);
}

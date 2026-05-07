import '../../features/resumes/models/resume_file.dart';

class MockResumes {
  const MockResumes._();

  static List<ResumeFile> initialUploads = [
    ResumeFile(
      id: 'base-resume-1',
      name: 'Daryn_resume.pdf',
      size: 142000,
      type: 'application/pdf',
      uploadedAt: DateTime(2026, 5, 7, 10, 30),
      source: ResumeSource.manual,
    ),
  ];

  static List<ResumeFile> tailored = List.generate(
    5,
    (index) => ResumeFile(
      id: 'tailored-resume-${index + 1}',
      name: 'Tailored Resume #${index + 1}.pdf',
      size: 98000 + (index * 1200),
      type: 'application/pdf',
      uploadedAt: DateTime(2026, 5, 7, 11, index),
      source: ResumeSource.tailored,
    ),
  );
}

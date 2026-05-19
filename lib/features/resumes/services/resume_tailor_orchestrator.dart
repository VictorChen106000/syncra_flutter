import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../data/firestore/firestore_paths.dart';
import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/resumes_repository.dart';
import '../../../data/models/job.dart';
import '../models/resume_file.dart';
import '../models/resume_json.dart';
import 'pdf_template.dart';
import 'pdf_text_extractor.dart';
import 'resume_parser_service.dart';
import 'resume_tailor_service.dart';

/// One-shot orchestrator: load resume → (lazy) parse → tailor for a job →
/// render to PDF via the fixed template → save to local disk + Firestore.
///
/// Owned by the agent tools layer. Returns the new tailored [ResumeFile]
/// for the agent (and UI) to reference in subsequent steps.
class ResumeTailorOrchestrator {
  ResumeTailorOrchestrator({
    required ResumesRepository resumesRepository,
    required JobsRepository jobsRepository,
    required ResumeParserService parser,
    required ResumeTailorService tailor,
    ResumePdfTextExtractor? extractor,
    ResumePdfTemplate? template,
    FirebaseFirestore? db,
  })  : _resumes = resumesRepository,
        _jobs = jobsRepository,
        _parser = parser,
        _tailor = tailor,
        _extractor = extractor ?? const ResumePdfTextExtractor(),
        _template = template ?? const ResumePdfTemplate(),
        _paths = FirestorePaths(db ?? FirebaseFirestore.instance);

  final ResumesRepository _resumes;
  final JobsRepository _jobs;
  final ResumeParserService _parser;
  final ResumeTailorService _tailor;
  final ResumePdfTextExtractor _extractor;
  final ResumePdfTemplate _template;
  final FirestorePaths _paths;

  /// Reads a resume from Firestore, parses lazily if needed, returns the
  /// canonical [ResumeJson]. Caches the parsed JSON back to Firestore on
  /// first call.
  Future<ResumeJson> readResumeJson({
    required String uid,
    required String resumeId,
  }) async {
    final snap = await _paths.resumes(uid).doc(resumeId).get();
    if (!snap.exists) {
      throw TailorOrchestratorException('Resume $resumeId not found.');
    }
    final data = snap.data() ?? const {};

    final cached = data['resume_json'];
    if (cached is Map) {
      return ResumeJson.fromJson(cached.cast<String, dynamic>());
    }

    final storagePath = data['storage_path'] as String?;
    if (storagePath == null || storagePath.isEmpty) {
      throw const TailorOrchestratorException(
        'This resume has no file attached — re-upload it to continue.',
      );
    }

    final bytes = await _resumes.downloadBytes(storagePath);
    if (bytes == null) {
      throw const TailorOrchestratorException(
        'Could not download the resume from storage.',
      );
    }

    final rawText = _extractor.extractFromBytes(bytes);
    final parsed = await _parser.parse(rawText);
    if (parsed == null) {
      throw const TailorOrchestratorException(
        'No Anthropic API key configured.',
      );
    }

    // Cache for next time so we never re-parse the same resume.
    try {
      await snap.reference.update({'resume_json': parsed.toJson()});
    } catch (e) {
      debugPrint('caching resume_json failed: $e');
    }
    return parsed;
  }

  /// Full tailor flow. Returns the newly created tailored [ResumeFile].
  Future<ResumeFile> tailorForJob({
    required String uid,
    required String resumeId,
    required String jobId,
  }) async {
    final job = await _jobs.fetchById(jobId);
    if (job == null) {
      throw TailorOrchestratorException('Job $jobId not found.');
    }
    final resumeJson = await readResumeJson(uid: uid, resumeId: resumeId);

    final tailored = await _tailor.tailor(resume: resumeJson, job: job);
    if (tailored == null) {
      throw const TailorOrchestratorException(
        'No Anthropic API key configured.',
      );
    }

    final bytes = await _template.render(tailored);
    final fileName = _fileNameFor(job: job);
    final saved = await _resumes.saveGeneratedResume(
      uid: uid,
      name: fileName,
      bytes: bytes,
      parentResumeId: resumeId,
      tailoredForJobId: jobId,
    );

    try {
      final docRef = _paths.resumes(uid).doc(saved.id);
      await docRef.update({'resume_json': tailored.toJson()});
    } catch (e) {
      debugPrint('caching tailored resume_json failed: $e');
    }
    return saved;
  }

  String _fileNameFor({required Job job}) {
    final safeCompany = job.company
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final base = safeCompany.isEmpty ? 'Tailored' : safeCompany;
    return '${base}_Resume_$stamp.pdf';
  }
}

class TailorOrchestratorException implements Exception {
  const TailorOrchestratorException(this.message);
  final String message;
  @override
  String toString() => 'TailorOrchestratorException: $message';
}

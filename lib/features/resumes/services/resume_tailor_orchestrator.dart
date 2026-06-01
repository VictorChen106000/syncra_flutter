import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../data/firestore/firestore_paths.dart';
import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/resumes_repository.dart';
import '../../../data/models/job.dart';
import '../models/proposed_edit.dart';
import '../models/resume_file.dart';
import '../models/resume_json.dart';
import 'pdf_template.dart';
import 'pdf_text_extractor.dart';
import 'resume_diff_service.dart';
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
    ResumeDiffService? diff,
    FirebaseFirestore? db,
  })  : _resumes = resumesRepository,
        _jobs = jobsRepository,
        _parser = parser,
        _tailor = tailor,
        _extractor = extractor ?? const ResumePdfTextExtractor(),
        _template = template ?? const ResumePdfTemplate(),
        _diff = diff ?? const ResumeDiffService(),
        _paths = FirestorePaths(db ?? FirebaseFirestore.instance);

  final ResumesRepository _resumes;
  final JobsRepository _jobs;
  final ResumeParserService _parser;
  final ResumeTailorService _tailor;
  final ResumePdfTextExtractor _extractor;
  final ResumePdfTemplate _template;
  final ResumeDiffService _diff;
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
    if (rawText.trim().isEmpty) {
      // No embedded text — almost always a scanned-image PDF. Surface an
      // actionable error instead of guessing or substituting a sample.
      throw const TailorOrchestratorException(
        'This PDF has no readable text — it looks like a scanned image. '
        'Upload a text-based PDF resume so the agent can read it.',
      );
    }
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

  /// Renders the tailored PDF for a user-accepted edit subset **without
  /// saving anything**. Reads the source resume, applies [acceptedEdits] via
  /// [ResumeDiffService], and renders the fixed template. Returns the PDF
  /// bytes + the resulting [ResumeJson] so a caller can preview first and
  /// persist later via [saveRenderedResume]. Throws if no edit matched.
  Future<RenderEditsResult> renderEdits({
    required String uid,
    required String resumeId,
    required List<ProposedEdit> acceptedEdits,
  }) async {
    if (acceptedEdits.isEmpty) {
      throw const TailorOrchestratorException(
        'No accepted edits to apply.',
      );
    }

    final original = await readResumeJson(uid: uid, resumeId: resumeId);
    final diff = _diff.apply(original, acceptedEdits);

    if (diff.applied.isEmpty) {
      throw const TailorOrchestratorException(
        'None of the accepted edits matched the resume — nothing to apply.',
      );
    }

    final bytes = await _template.render(diff.resume);
    return RenderEditsResult(
      bytes: bytes,
      resume: diff.resume,
      appliedCount: diff.applied.length,
      skippedCount: diff.skipped.length,
    );
  }

  /// Persists an already-rendered tailored resume as a new `source: tailored`
  /// doc (the second half of the apply flow, gated behind a preview). Saves
  /// the [bytes] to Storage and caches [resume] as the doc's `resume_json`.
  Future<ResumeFile> saveRenderedResume({
    required String uid,
    required Uint8List bytes,
    required ResumeJson resume,
    String? parentResumeId,
    String? jobId,
  }) async {
    Job? job;
    if (jobId != null && jobId.isNotEmpty) {
      job = await _jobs.fetchById(jobId);
    }

    final saved = await _resumes.saveGeneratedResume(
      uid: uid,
      name: _fileNameFor(job: job),
      bytes: bytes,
      parentResumeId: parentResumeId,
      tailoredForJobId: jobId,
    );

    try {
      await _paths
          .resumes(uid)
          .doc(saved.id)
          .update({'resume_json': resume.toJson()});
    } catch (e) {
      debugPrint('caching tailored resume_json failed: $e');
    }

    return saved;
  }

  /// Renders a complete [ResumeJson] (assembled from scratch by `build_resume`)
  /// to PDF bytes via the fixed template, **without saving**. Returns the bytes
  /// so the caller can preview before persisting via [saveBuiltResume]. No
  /// source resume, no diff — the agent built the whole structure.
  Future<Uint8List> renderResume(ResumeJson resume) => _template.render(resume);

  /// Persists an agent-built resume as a new `source: manual` base resume the
  /// user can later tailor. Saves [bytes] to Storage and caches [resume] as the
  /// doc's `resume_json` — so a built resume never needs PDF parsing.
  Future<ResumeFile> saveBuiltResume({
    required String uid,
    required Uint8List bytes,
    required ResumeJson resume,
    required String name,
  }) async {
    final saved = await _resumes.uploadResume(
      uid: uid,
      name: name,
      bytes: bytes,
      contentType: 'application/pdf',
      source: ResumeSource.manual,
    );

    try {
      await _paths
          .resumes(uid)
          .doc(saved.id)
          .update({'resume_json': resume.toJson()});
    } catch (e) {
      debugPrint('caching built resume_json failed: $e');
    }

    return saved;
  }

  /// One-shot apply (render + save) for the agent's `apply_resume_edits` tool.
  /// The diff-viewer UI uses [renderEdits] / [saveRenderedResume] instead so
  /// it can preview before persisting.
  Future<ApplyEditsResult> applyEdits({
    required String uid,
    required String resumeId,
    required List<ProposedEdit> acceptedEdits,
    String? jobId,
  }) async {
    final rendered = await renderEdits(
      uid: uid,
      resumeId: resumeId,
      acceptedEdits: acceptedEdits,
    );
    final saved = await saveRenderedResume(
      uid: uid,
      bytes: rendered.bytes,
      resume: rendered.resume,
      parentResumeId: resumeId,
      jobId: jobId,
    );
    return ApplyEditsResult(
      file: saved,
      appliedCount: rendered.appliedCount,
      skippedCount: rendered.skippedCount,
    );
  }

  /// The user's most recent `source: manual` resume id, or null if they
  /// haven't uploaded one. Used to resolve a source resume when a proposed-
  /// edits card didn't carry an explicit id.
  Future<String?> latestManualResumeId(String uid) async {
    final snap = await _paths
        .resumes(uid)
        .orderBy('uploaded_at', descending: true)
        .limit(10)
        .get();
    for (final doc in snap.docs) {
      if (doc.data()['source'] == 'manual') return doc.id;
    }
    return null;
  }

  String _fileNameFor({Job? job}) {
    final safeCompany = (job?.company ?? '')
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final base = safeCompany.isEmpty ? 'Tailored' : safeCompany;
    return '${base}_Resume_$stamp.pdf';
  }
}

/// Result of [ResumeTailorOrchestrator.renderEdits] — a rendered-but-unsaved
/// tailored resume, ready to preview before [ResumeTailorOrchestrator.saveRenderedResume].
class RenderEditsResult {
  const RenderEditsResult({
    required this.bytes,
    required this.resume,
    required this.appliedCount,
    required this.skippedCount,
  });

  final Uint8List bytes;
  final ResumeJson resume;
  final int appliedCount;
  final int skippedCount;
}

/// Result of [ResumeTailorOrchestrator.applyEdits].
class ApplyEditsResult {
  const ApplyEditsResult({
    required this.file,
    required this.appliedCount,
    required this.skippedCount,
  });

  final ResumeFile file;
  final int appliedCount;
  final int skippedCount;
}

class TailorOrchestratorException implements Exception {
  const TailorOrchestratorException(this.message);
  final String message;
  @override
  String toString() => 'TailorOrchestratorException: $message';
}

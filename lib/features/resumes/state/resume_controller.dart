import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/mock/mock_resumes.dart';
import '../models/resume_file.dart';
import '../models/upload_queue_item.dart';

class ResumeController extends ChangeNotifier {
  ResumeController()
      : _resumes = List.of(MockResumes.initialUploads),
        _tailoredResumes = List.of(MockResumes.tailored),
        _selectedResumeIds = {'base-resume-1'};

  final List<Timer> _uploadTimers = [];
  final List<ResumeFile> _resumes;
  final List<ResumeFile> _tailoredResumes;
  final List<UploadQueueItem> _uploadQueue = [];
  final Set<String> _selectedResumeIds;

  int _mockUploadCounter = 1;

  List<ResumeFile> get resumes => List.unmodifiable(_resumes);
  List<ResumeFile> get tailoredResumes => List.unmodifiable(_tailoredResumes);
  List<UploadQueueItem> get uploadQueue => List.unmodifiable(_uploadQueue);
  Set<String> get selectedResumeIds => Set.unmodifiable(_selectedResumeIds);

  List<ResumeFile> get selectedResumes {
    return _resumes
        .where((resume) => _selectedResumeIds.contains(resume.id))
        .toList();
  }

  Future<void> pickAndUploadResumes() async {
    final fileNumber = _mockUploadCounter++;
    _simulateUpload(
      name: 'Uploaded Resume #$fileNumber.pdf',
      size: 128000 + (fileNumber * 9000),
      type: 'application/pdf',
    );
  }

  void toggleSelectedResume(String resumeId) {
    if (_selectedResumeIds.contains(resumeId)) {
      _selectedResumeIds.remove(resumeId);
    } else if (_selectedResumeIds.length < AppConstants.maxResumeAttachments) {
      _selectedResumeIds.add(resumeId);
    }

    notifyListeners();
  }

  void removeSelectedResume(String resumeId) {
    _selectedResumeIds.remove(resumeId);
    notifyListeners();
  }

  void deleteResume(String resumeId) {
    _resumes.removeWhere((resume) => resume.id == resumeId);
    _selectedResumeIds.remove(resumeId);
    notifyListeners();
  }

  void _simulateUpload({
    required String name,
    required int size,
    required String type,
    String? path,
  }) {
    final id = '$name-${DateTime.now().microsecondsSinceEpoch}';

    if (!_isResumeFile(name) || size > AppConstants.maxResumeUploadBytes) {
      _uploadQueue.insert(
        0,
        UploadQueueItem(
          id: id,
          name: name,
          size: size,
          progress: 0,
          error: 'Please upload a PDF, DOC, or DOCX file under 5MB.',
        ),
      );

      notifyListeners();

      Timer(const Duration(seconds: 3), () {
        _uploadQueue.removeWhere((item) => item.id == id);
        notifyListeners();
      });

      return;
    }

    int progress = 8;

    _uploadQueue.insert(
      0,
      UploadQueueItem(
        id: id,
        name: name,
        size: size,
        progress: progress,
      ),
    );

    notifyListeners();

    final timer = Timer.periodic(const Duration(milliseconds: 260), (timer) {
      progress = (progress + 16).clamp(0, 100);

      final index = _uploadQueue.indexWhere((item) => item.id == id);

      if (index != -1) {
        _uploadQueue[index] = UploadQueueItem(
          id: id,
          name: name,
          size: size,
          progress: progress,
        );
      }

      if (progress >= 100) {
        timer.cancel();
        _uploadTimers.remove(timer);

        Future.delayed(const Duration(milliseconds: 650), () {
          _uploadQueue.removeWhere((item) => item.id == id);

          final resume = ResumeFile(
            id: id,
            name: name,
            size: size,
            type: type,
            uploadedAt: DateTime.now(),
            source: ResumeSource.manual,
            path: path,
          );

          _resumes.insert(0, resume);
          _selectedResumeIds.add(resume.id);

          notifyListeners();
        });
      }

      notifyListeners();
    });

    _uploadTimers.add(timer);
  }

  bool _isResumeFile(String name) {
    final lower = name.toLowerCase();

    return lower.endsWith('.pdf') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.docx');
  }

  @override
  void dispose() {
    for (final timer in _uploadTimers) {
      timer.cancel();
    }

    super.dispose();
  }
}
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/mock/mock_resumes.dart';
import '../models/resume_file.dart';
import '../models/upload_queue_item.dart';

/// Outcome of a controller operation surfaced through SnackBars.
class ResumeActionResult {
  const ResumeActionResult({required this.message, this.isError = false});

  final String message;
  final bool isError;
}

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

  ResumeActionResult? _lastAction;

  List<ResumeFile> get resumes => List.unmodifiable(_resumes);
  List<ResumeFile> get tailoredResumes => List.unmodifiable(_tailoredResumes);
  List<UploadQueueItem> get uploadQueue => List.unmodifiable(_uploadQueue);
  Set<String> get selectedResumeIds => Set.unmodifiable(_selectedResumeIds);

  /// Consumed by the UI after each notify to show a SnackBar exactly once.
  ResumeActionResult? consumeLastAction() {
    final result = _lastAction;
    _lastAction = null;
    return result;
  }

  List<ResumeFile> get selectedResumes {
    return _resumes
        .where((resume) => _selectedResumeIds.contains(resume.id))
        .toList();
  }

  Future<void> pickAndUploadResumes() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'doc', 'docx'],
        allowMultiple: true,
        withData: true,
      );
    } catch (_) {
      _lastAction = ResumeActionResult(
        message: 'Could not open the file picker.',
        isError: true,
      );
      notifyListeners();
      return;
    }

    if (result == null || result.files.isEmpty) return;

    for (final file in result.files) {
      _enqueueUpload(
        name: file.name,
        size: file.size,
        type: _typeFromExtension(file.extension),
        bytes: file.bytes,
        path: file.path,
      );
    }
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
    final index = _resumes.indexWhere((r) => r.id == resumeId);
    if (index == -1) return;
    final removed = _resumes.removeAt(index);
    _selectedResumeIds.remove(resumeId);
    _lastAction = ResumeActionResult(message: '${removed.name} deleted');
    notifyListeners();
  }

  void _enqueueUpload({
    required String name,
    required int size,
    required String type,
    Uint8List? bytes,
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

      _lastAction = const ResumeActionResult(
        message: 'Unsupported file or larger than 5MB.',
        isError: true,
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
            bytes: bytes,
          );

          _resumes.insert(0, resume);
          _selectedResumeIds.add(resume.id);
          _lastAction = ResumeActionResult(message: '$name uploaded');

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

  String _typeFromExtension(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  void dispose() {
    for (final timer in _uploadTimers) {
      timer.cancel();
    }

    super.dispose();
  }
}

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/firestore/resumes_repository.dart';
import '../../auth/state/auth_controller.dart';
import '../models/resume_file.dart';
import '../models/upload_queue_item.dart';
import '../services/resume_session_storage.dart';

/// Outcome of a controller operation surfaced through SnackBars.
class ResumeActionResult {
  const ResumeActionResult({required this.message, this.isError = false});

  final String message;
  final bool isError;
}

class ResumeController extends ChangeNotifier {
  ResumeController({
    required AuthController auth,
    ResumesRepository? repository,
  })  : _auth = auth,
        _repository = repository ?? ResumesRepository() {
    _auth.addListener(_onAuthChanged);
    _bindToCurrentUser();
  }

  final AuthController _auth;
  final ResumesRepository _repository;

  StreamSubscription<List<ResumeFile>>? _subscription;
  String? _boundUid;

  List<ResumeFile> _allResumes = const [];
  final List<UploadQueueItem> _uploadQueue = [];
  final Set<String> _selectedResumeIds = {};
  final Map<String, Uint8List> _resumeBytesCache = {};
  ResumeActionResult? _lastAction;

 List<ResumeFile> get resumes => _allResumes
    .where((r) => r.source == ResumeSource.manual)
    .map(_withCachedBytes)
    .toList();

List<ResumeFile> get tailoredResumes => _allResumes
    .where((r) => r.source == ResumeSource.tailored)
    .map(_withCachedBytes)
    .toList();
  List<UploadQueueItem> get uploadQueue => List.unmodifiable(_uploadQueue);
  Set<String> get selectedResumeIds => Set.unmodifiable(_selectedResumeIds);

  ResumeActionResult? consumeLastAction() {
    final result = _lastAction;
    _lastAction = null;
    return result;
  }

  List<ResumeFile> get selectedResumes {
    return resumes
        .where((resume) => _selectedResumeIds.contains(resume.id))
        .toList();
  }

  ResumeFile? resumeById(String resumeId) {
  for (final resume in [...resumes, ...tailoredResumes]) {
    if (resume.id == resumeId) return resume;
  }
  return null;
}

Future<void> _restoreSessionBytes(
  String uid,
  List<ResumeFile> resumes,
) async {
  var changed = false;

  for (final resume in resumes) {
    if (_resumeBytesCache.containsKey(resume.id)) continue;

    final bytes = await ResumeSessionStorage.readBytes(
      uid: uid,
      resumeId: resume.id,
    );

    if (bytes == null) continue;

    _resumeBytesCache[resume.id] = bytes;
    changed = true;
  }

  if (changed) {
    notifyListeners();
  }
}

  Future<void> pickAndUploadResumes() async {
    final uid = _auth.appUser?.uid;
    if (uid == null || _auth.appUser!.isGuest) {
      _lastAction = const ResumeActionResult(
        message: 'Sign in to upload resumes.',
        isError: true,
      );
      notifyListeners();
      return;
    }

    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'doc', 'docx'],
        allowMultiple: true,
        withData: true,
      );
    } catch (_) {
      _lastAction = const ResumeActionResult(
        message: 'Could not open the file picker.',
        isError: true,
      );
      notifyListeners();
      return;
    }

    if (result == null || result.files.isEmpty) return;

    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) {
        _lastAction = ResumeActionResult(
          message: 'Could not read ${file.name}.',
          isError: true,
        );
        notifyListeners();
        continue;
      }
      unawaited(_uploadFile(
        uid: uid,
        name: file.name,
        size: file.size,
        type: _typeFromExtension(file.extension),
        bytes: bytes,
      ));
    }
  }

  ResumeFile _withCachedBytes(ResumeFile resume) {
  final cachedBytes = resume.bytes ?? _resumeBytesCache[resume.id];

  if (cachedBytes == null) return resume;

  return ResumeFile(
    id: resume.id,
    name: resume.name,
    size: resume.size,
    type: resume.type,
    uploadedAt: resume.uploadedAt,
    source: resume.source,
    path: resume.path,
    bytes: cachedBytes,
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

  Future<void> deleteResume(String resumeId) async {
    final uid = _auth.appUser?.uid;
    if (uid == null || _auth.appUser!.isGuest) return;
    final target = _allResumes.firstWhere(
      (r) => r.id == resumeId,
      orElse: () => _allResumes.isEmpty
          ? throw StateError('No resume $resumeId')
          : _allResumes.first,
    );
    _selectedResumeIds.remove(resumeId);
    _resumeBytesCache.remove(resumeId);
    unawaited(
      ResumeSessionStorage.removeBytes(
        uid: uid,
        resumeId: resumeId,
      ),
    );
    _lastAction = ResumeActionResult(message: '${target.name} deleted');
    notifyListeners();
    try {
      await _repository.deleteResume(
        uid: uid,
        resumeId: resumeId,
        localPath: target.path,
      );
    } catch (e) {
      debugPrint('delete resume failed: $e');
    }
  }

  Future<void> _uploadFile({
    required String uid,
    required String name,
    required int size,
    required String type,
    required Uint8List bytes,
  }) async {
    final queueId = '$name-${DateTime.now().microsecondsSinceEpoch}';

    if (!_isResumeFile(name) || size > AppConstants.maxResumeUploadBytes) {
      _uploadQueue.insert(
        0,
        UploadQueueItem(
          id: queueId,
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
        _uploadQueue.removeWhere((item) => item.id == queueId);
        notifyListeners();
      });
      return;
    }

    _uploadQueue.insert(
      0,
      UploadQueueItem(id: queueId, name: name, size: size, progress: 50),
    );
    notifyListeners();

    try {
      final uploaded = await _repository.uploadResume(
        uid: uid,
        name: name,
        bytes: bytes,
        contentType: type,
      );

      _resumeBytesCache[uploaded.id] = bytes;
      unawaited(
        ResumeSessionStorage.saveBytes(
          uid: uid,
          resumeId: uploaded.id,
          bytes: bytes,
        ),
      );
      _allResumes = [
        uploaded,
        ..._allResumes.where((resume) => resume.id != uploaded.id),
      ];
      _uploadQueue.removeWhere((item) => item.id == queueId);
      _selectedResumeIds.add(uploaded.id);
      _lastAction = ResumeActionResult(message: '$name uploaded');
      notifyListeners();
    } catch (e) {
      debugPrint('upload failed: $e');
      final i = _uploadQueue.indexWhere((item) => item.id == queueId);
      if (i != -1) {
        _uploadQueue[i] = UploadQueueItem(
          id: queueId,
          name: name,
          size: size,
          progress: 0,
          error: 'Upload failed. Tap to retry.',
        );
      }
      _lastAction = ResumeActionResult(
        message: 'Failed to upload $name',
        isError: true,
      );
      notifyListeners();
    }
  }

  void _onAuthChanged() {
    final nextUid = _auth.appUser?.uid;
    final guest = _auth.appUser?.isGuest ?? true;
    if (nextUid == _boundUid && !(guest && _subscription != null)) return;
    _bindToCurrentUser();
  }

  void _bindToCurrentUser() {
    _subscription?.cancel();
    _subscription = null;
    _allResumes = const [];
    _uploadQueue.clear();
    _selectedResumeIds.clear();
    _resumeBytesCache.clear();

    final user = _auth.appUser;
    if (user == null || user.isGuest) {
      _boundUid = null;
      notifyListeners();
      return;
    }

    _boundUid = user.uid;
    _subscription = _repository.watchResumes(user.uid).listen(
      (resumes) {
        _allResumes = resumes;
        notifyListeners();
        unawaited(_restoreSessionBytes(user.uid, resumes));
      },
      onError: (Object e) {
        debugPrint('resumes stream error: $e');
      },
    );
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
    _auth.removeListener(_onAuthChanged);
    _subscription?.cancel();
    super.dispose();
  }
}

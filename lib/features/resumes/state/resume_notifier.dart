import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/firestore/resumes_repository.dart';
import '../../auth/state/auth_notifier.dart';
import '../models/resume_file.dart';
import '../models/upload_queue_item.dart';

/// Outcome of a notifier operation surfaced through SnackBars.
class ResumeActionResult {
  const ResumeActionResult({required this.message, this.isError = false});

  final String message;
  final bool isError;
}

@immutable
class ResumeState {
  const ResumeState({
    this.allResumes = const [],
    this.uploadQueue = const [],
    this.selectedResumeIds = const {},
    this.lastAction,
  });

  /// Every resume in the user's library — manual + tailored.
  final List<ResumeFile> allResumes;
  final List<UploadQueueItem> uploadQueue;
  final Set<String> selectedResumeIds;
  final ResumeActionResult? lastAction;

  List<ResumeFile> get resumes =>
      allResumes.where((r) => r.source == ResumeSource.manual).toList();
  List<ResumeFile> get tailoredResumes =>
      allResumes.where((r) => r.source == ResumeSource.tailored).toList();
  List<ResumeFile> get selectedResumes => resumes
      .where((resume) => selectedResumeIds.contains(resume.id))
      .toList();

  ResumeState copyWith({
    List<ResumeFile>? allResumes,
    List<UploadQueueItem>? uploadQueue,
    Set<String>? selectedResumeIds,
    ResumeActionResult? lastAction,
    bool clearLastAction = false,
  }) {
    return ResumeState(
      allResumes: allResumes ?? this.allResumes,
      uploadQueue: uploadQueue ?? this.uploadQueue,
      selectedResumeIds: selectedResumeIds ?? this.selectedResumeIds,
      lastAction: clearLastAction ? null : (lastAction ?? this.lastAction),
    );
  }
}

class ResumeNotifier extends Notifier<ResumeState> {
  ResumeNotifier({ResumesRepository? repository})
      : _repository = repository ?? ResumesRepository();

  final ResumesRepository _repository;

  StreamSubscription<List<ResumeFile>>? _subscription;
  String? _boundUid;

  /// In-memory bytes cache keyed by resume id. Seeded on upload/tailor so
  /// the user never re-downloads bytes they just produced, and populated
  /// on first preview for resumes uploaded from another device/session.
  final Map<String, Uint8List> _bytesCache = {};

  /// Inflight downloads keyed by resume id, so concurrent `bytesFor` calls
  /// share a single network request instead of fanning out.
  final Map<String, Future<Uint8List?>> _inflight = {};

  @override
  ResumeState build() {
    final auth = ref.watch(authProvider);
    _bindTo(auth.appUser?.uid, auth.appUser?.isGuest ?? true);

    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });

    return const ResumeState();
  }

  void _bindTo(String? uid, bool isGuest) {
    if (uid == _boundUid && _subscription != null) return;

    _subscription?.cancel();
    _subscription = null;

    if (uid == null || isGuest) {
      _boundUid = null;
      _bytesCache.clear();
      _inflight.clear();
      return;
    }

    if (uid != _boundUid) {
      // Switching accounts — drop the previous user's cached bytes.
      _bytesCache.clear();
      _inflight.clear();
    }

    _boundUid = uid;
    _subscription = _repository.watchResumes(uid).listen(
      (resumes) {
        state = state.copyWith(allResumes: resumes);
      },
      onError: (Object e) {
        debugPrint('resumes stream error: $e');
      },
    );
  }

  ResumeActionResult? consumeLastAction() {
    final result = state.lastAction;
    if (result != null) {
      state = state.copyWith(clearLastAction: true);
    }
    return result;
  }

  /// Returns the PDF/DOC bytes for [resume], downloading from Firebase
  /// Storage on cache miss. Returns `null` if the blob is missing or the
  /// download fails — callers should render a metadata-only fallback.
  Future<Uint8List?> bytesFor(ResumeFile resume) {
    final cached = _bytesCache[resume.id];
    if (cached != null) return Future.value(cached);

    final pending = _inflight[resume.id];
    if (pending != null) return pending;

    if (!resume.hasStorageBlob) return Future.value(null);

    final future = _repository
        .downloadBytes(resume.storagePath!)
        .then((bytes) {
      if (bytes != null) _bytesCache[resume.id] = bytes;
      return bytes;
    }).whenComplete(() {
      _inflight.remove(resume.id);
    });

    _inflight[resume.id] = future;
    return future;
  }

  Future<void> pickAndUploadResumes() async {
    final user = ref.read(authProvider).appUser;
    final uid = user?.uid;
    if (uid == null || user!.isGuest) {
      state = state.copyWith(
        lastAction: const ResumeActionResult(
          message: 'Sign in to upload resumes.',
          isError: true,
        ),
      );
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
      state = state.copyWith(
        lastAction: const ResumeActionResult(
          message: 'Could not open the file picker.',
          isError: true,
        ),
      );
      return;
    }

    if (result == null || result.files.isEmpty) return;

    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) {
        state = state.copyWith(
          lastAction: ResumeActionResult(
            message: 'Could not read ${file.name}.',
            isError: true,
          ),
        );
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

  void toggleSelectedResume(String resumeId) {
    final next = {...state.selectedResumeIds};
    if (next.contains(resumeId)) {
      next.remove(resumeId);
    } else if (next.length < AppConstants.maxResumeAttachments) {
      next.add(resumeId);
    } else {
      return;
    }
    state = state.copyWith(selectedResumeIds: next);
  }

  void removeSelectedResume(String resumeId) {
    if (!state.selectedResumeIds.contains(resumeId)) return;
    final next = {...state.selectedResumeIds}..remove(resumeId);
    state = state.copyWith(selectedResumeIds: next);
  }

  Future<void> deleteResume(String resumeId) async {
    final user = ref.read(authProvider).appUser;
    final uid = user?.uid;
    if (uid == null || user!.isGuest) return;
    final target = state.allResumes.firstWhere(
      (r) => r.id == resumeId,
      orElse: () => state.allResumes.isEmpty
          ? throw StateError('No resume $resumeId')
          : state.allResumes.first,
    );

    final nextSelected = {...state.selectedResumeIds}..remove(resumeId);
    state = state.copyWith(
      selectedResumeIds: nextSelected,
      lastAction: ResumeActionResult(message: '${target.name} deleted'),
    );

    _bytesCache.remove(resumeId);
    _inflight.remove(resumeId);

    try {
      await _repository.deleteResume(
        uid: uid,
        resumeId: resumeId,
        storagePath: target.storagePath,
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
      final nextQueue = [
        UploadQueueItem(
          id: queueId,
          name: name,
          size: size,
          progress: 0,
          error: 'Please upload a PDF, DOC, or DOCX file under 5MB.',
        ),
        ...state.uploadQueue,
      ];
      state = state.copyWith(
        uploadQueue: nextQueue,
        lastAction: const ResumeActionResult(
          message: 'Unsupported file or larger than 5MB.',
          isError: true,
        ),
      );
      Timer(const Duration(seconds: 3), () {
        state = state.copyWith(
          uploadQueue: state.uploadQueue.where((i) => i.id != queueId).toList(),
        );
      });
      return;
    }

    state = state.copyWith(
      uploadQueue: [
        UploadQueueItem(id: queueId, name: name, size: size, progress: 50),
        ...state.uploadQueue,
      ],
    );

    try {
      final uploaded = await _repository.uploadResume(
        uid: uid,
        name: name,
        bytes: bytes,
        contentType: type,
      );

      // Seed the cache so the immediate preview after upload is instant.
      _bytesCache[uploaded.id] = bytes;

      final currentResumes = [...state.allResumes];
      final existingIndex =
          currentResumes.indexWhere((resume) => resume.id == uploaded.id);

      if (existingIndex == -1) {
        currentResumes.insert(0, uploaded);
      } else {
        currentResumes[existingIndex] = uploaded;
      }

      state = state.copyWith(
        allResumes: currentResumes,
        uploadQueue: state.uploadQueue.where((i) => i.id != queueId).toList(),
        selectedResumeIds: {...state.selectedResumeIds, uploaded.id},
        lastAction: ResumeActionResult(message: '$name uploaded'),
      );
    } catch (e) {
      debugPrint('upload failed: $e');
      final nextQueue = state.uploadQueue.map((item) {
        if (item.id != queueId) return item;
        return UploadQueueItem(
          id: queueId,
          name: name,
          size: size,
          progress: 0,
          error: 'Upload failed. Tap to retry.',
        );
      }).toList();
      state = state.copyWith(
        uploadQueue: nextQueue,
        lastAction: ResumeActionResult(
          message: 'Failed to upload $name',
          isError: true,
        ),
      );
    }
  }

  /// Seed the cache with bytes for a resume the caller just produced
  /// (e.g. the tailor orchestrator after rendering a PDF). Avoids a
  /// redundant Storage download when the user opens the result.
  void primeBytes(String resumeId, Uint8List bytes) {
    _bytesCache[resumeId] = bytes;
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
}

final resumeProvider = NotifierProvider<ResumeNotifier, ResumeState>(ResumeNotifier.new);

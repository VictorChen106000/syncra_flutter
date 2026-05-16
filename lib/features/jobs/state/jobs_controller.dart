import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/firestore/applications_repository.dart';
import '../../../data/firestore/pipeline_repository.dart';
import '../../../data/models/job.dart';
import '../../auth/state/auth_controller.dart';

/// Streams the user's pending pipeline cards from Firestore and tracks
/// per-card UX state (saved / hidden / dismissed).
class JobsController extends ChangeNotifier {
  JobsController({
    required AuthController auth,
    PipelineRepository? repository,
    ApplicationsRepository? applicationsRepository,
  })  : _auth = auth,
        _repository = repository ?? PipelineRepository(),
        _applications = applicationsRepository ?? ApplicationsRepository() {
    _auth.addListener(_onAuthChanged);
    _bindToCurrentUser();
  }

  final AuthController _auth;
  final PipelineRepository _repository;
  final ApplicationsRepository _applications;

  StreamSubscription<List<PipelineCard>>? _subscription;
  String? _boundUid;
  List<PipelineCard> _cards = const [];

  final Set<String> _savedIds = {};
  final Set<String> _hiddenIds = {};
  final Set<String> _dismissedIds = {};
  String? _lastMessage;

  List<PipelineCard> get pendingCards => List.unmodifiable(_cards);
  List<Job> get pendingJobs => _cards.map((c) => c.job).toList(growable: false);

  Set<String> get savedIds => Set.unmodifiable(_savedIds);
  Set<String> get hiddenIds => Set.unmodifiable(_hiddenIds);
  Set<String> get dismissedIds => Set.unmodifiable(_dismissedIds);

  bool isSaved(String id) => _savedIds.contains(id);
  bool isHidden(String id) => _hiddenIds.contains(id);
  bool isDismissed(String id) => _dismissedIds.contains(id);

  String? consumeMessage() {
    final m = _lastMessage;
    _lastMessage = null;
    return m;
  }

  void toggleSaved(String id, {String label = ''}) {
    final added = !_savedIds.contains(id);
    if (added) {
      _savedIds.add(id);
      _lastMessage = label.isEmpty ? 'Saved' : 'Saved $label';
    } else {
      _savedIds.remove(id);
      _lastMessage = label.isEmpty ? 'Removed from saved' : 'Unsaved $label';
    }
    notifyListeners();
  }

  void hide(String id, {String label = ''}) {
    _hiddenIds.add(id);
    _dismissedIds.add(id);
    _lastMessage = label.isEmpty ? 'Hidden' : 'Hidden $label';
    notifyListeners();
  }

  void unhide(String id) {
    _hiddenIds.remove(id);
    _dismissedIds.remove(id);
    notifyListeners();
  }

  Future<void> dismiss(String id, {String label = ''}) async {
    _dismissedIds.add(id);
    _lastMessage = label.isEmpty ? 'Dismissed' : '$label dismissed';
    notifyListeners();
    final uid = _auth.appUser?.uid;
    if (uid == null || _auth.appUser!.isGuest) return;
    final card = _cards.firstWhere(
      (c) => c.job.id == id,
      orElse: () => _cards.isEmpty
          ? throw StateError('No card $id')
          : _cards.first,
    );
    try {
      await _repository.dismiss(uid, card.id);
    } catch (e) {
      debugPrint('dismiss card failed: $e');
    }
  }

  void undismiss(String id) {
    _dismissedIds.remove(id);
    notifyListeners();
  }

  /// Approves the pipeline card whose embedded job id matches [jobId]:
  /// marks the card as approved and creates a matching application doc
  /// that will appear in the tracker. Safe to call for guests (no-op).
  Future<void> approveByJobId(String jobId) async {
    final uid = _auth.appUser?.uid;
    if (uid == null || _auth.appUser!.isGuest) return;
    final card = _cards.where((c) => c.job.id == jobId).firstOrNull;
    if (card == null) return;
    try {
      await _applications.createApplication(
        uid: uid,
        job: card.job,
        status: JobStatus.submitted,
      );
      await _repository.approve(uid, card.id);
      _lastMessage = '${card.job.company} added to tracker';
      notifyListeners();
    } catch (e) {
      debugPrint('approve flow failed: $e');
      _lastMessage = 'Could not save application';
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
    _cards = const [];

    final user = _auth.appUser;
    if (user == null || user.isGuest) {
      _boundUid = null;
      notifyListeners();
      return;
    }

    _boundUid = user.uid;
    _subscription = _repository.watchPending(user.uid).listen(
      (cards) {
        _cards = cards;
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint('pipeline stream error: $e');
      },
    );
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _subscription?.cancel();
    super.dispose();
  }
}

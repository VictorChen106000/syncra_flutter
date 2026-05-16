import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/firestore/applications_repository.dart';
import '../../../data/models/job.dart';
import '../../../data/models/tracked_application.dart';
import '../../auth/state/auth_controller.dart';

class TrackerFilter {
  const TrackerFilter.all() : status = null;
  const TrackerFilter.status(JobStatus s) : status = s;

  final JobStatus? status;

  bool get isAll => status == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackerFilter && other.status == status;

  @override
  int get hashCode => status.hashCode;
}

class TrackerController extends ChangeNotifier {
  TrackerController({
    required AuthController auth,
    ApplicationsRepository? repository,
  })  : _auth = auth,
        _repository = repository ?? ApplicationsRepository() {
    _auth.addListener(_onAuthChanged);
    _bindToCurrentUser();
  }

  final AuthController _auth;
  final ApplicationsRepository _repository;

  StreamSubscription<List<TrackedApplication>>? _subscription;
  String? _boundUid;
  List<TrackedApplication> _items = const [];
  TrackerFilter _filter = const TrackerFilter.all();
  String? _lastMessage;

  TrackerFilter get filter => _filter;
  List<TrackedApplication> get items => List.unmodifiable(_items);

  String? consumeMessage() {
    final m = _lastMessage;
    _lastMessage = null;
    return m;
  }

  List<TrackedApplication> get filtered {
    final s = _filter.status;
    if (s == null) return List.unmodifiable(_items);
    return _items.where((a) => a.status == s).toList();
  }

  void setFilter(TrackerFilter f) {
    _filter = f;
    notifyListeners();
  }

  Future<void> updateStatus(String applicationId, JobStatus status) async {
    final uid = _auth.appUser?.uid;
    if (uid == null || _auth.appUser!.isGuest) return;
    final current = _items.firstWhere(
      (a) => a.id == applicationId,
      orElse: () => _items.isEmpty
          ? throw StateError('No application $applicationId')
          : _items.first,
    );
    await _repository.updateStatus(uid, applicationId, status);
    _lastMessage = '${current.job.company}: status set to ${status.label}';
    notifyListeners();
  }

  Future<void> addNote(String applicationId, String body) async {
    final uid = _auth.appUser?.uid;
    if (uid == null || _auth.appUser!.isGuest) return;
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    final current = _items.firstWhere(
      (a) => a.id == applicationId,
      orElse: () => _items.first,
    );
    await _repository.addNote(uid, applicationId, trimmed);
    _lastMessage = 'Note added to ${current.job.company}';
    notifyListeners();
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
    _items = const [];

    final user = _auth.appUser;
    if (user == null || user.isGuest) {
      _boundUid = null;
      notifyListeners();
      return;
    }

    _boundUid = user.uid;
    _subscription = _repository.watchApplications(user.uid).listen(
      (apps) {
        _items = apps;
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint('applications stream error: $e');
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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/firestore/applications_repository.dart';
import '../../../data/models/job.dart';
import '../../../data/models/tracked_application.dart';
import '../../auth/state/auth_notifier.dart';

class ApplicationsFilter {
  const ApplicationsFilter.all() : status = null;
  const ApplicationsFilter.status(JobStatus s) : status = s;

  final JobStatus? status;

  bool get isAll => status == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApplicationsFilter && other.status == status;

  @override
  int get hashCode => status.hashCode;
}

@immutable
class ApplicationsState {
  const ApplicationsState({
    this.items = const [],
    this.filter = const ApplicationsFilter.all(),
    this.lastMessage,
  });

  final List<TrackedApplication> items;
  final ApplicationsFilter filter;
  final String? lastMessage;

  List<TrackedApplication> get filtered {
    final s = filter.status;
    if (s == null) return items;
    return items.where((a) => a.status == s).toList();
  }

  ApplicationsState copyWith({
    List<TrackedApplication>? items,
    ApplicationsFilter? filter,
    String? lastMessage,
    bool clearMessage = false,
  }) {
    return ApplicationsState(
      items: items ?? this.items,
      filter: filter ?? this.filter,
      lastMessage: clearMessage ? null : (lastMessage ?? this.lastMessage),
    );
  }
}

class ApplicationsNotifier extends Notifier<ApplicationsState> {
  ApplicationsNotifier({ApplicationsRepository? repository})
      : _repository = repository ?? ApplicationsRepository();

  final ApplicationsRepository _repository;
  StreamSubscription<List<TrackedApplication>>? _subscription;
  String? _boundUid;

  @override
  ApplicationsState build() {
    final auth = ref.watch(authProvider);
    _bindTo(auth.appUser?.uid, auth.appUser?.isGuest ?? true);

    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });

    return const ApplicationsState();
  }

  void _bindTo(String? uid, bool isGuest) {
    if (uid == _boundUid && _subscription != null) return;

    _subscription?.cancel();
    _subscription = null;

    if (uid == null || isGuest) {
      _boundUid = null;
      // Don't read/write `state` here — this is called from build() before
      // the initial state is published. build()'s return value resets state.
      return;
    }

    _boundUid = uid;
    _subscription = _repository.watchApplications(uid).listen(
      (apps) {
        state = state.copyWith(items: apps);
      },
      onError: (Object e) {
        debugPrint('applications stream error: $e');
      },
    );
  }

  String? consumeMessage() {
    final m = state.lastMessage;
    if (m != null) {
      state = state.copyWith(clearMessage: true);
    }
    return m;
  }

  void setFilter(ApplicationsFilter f) {
    if (f == state.filter) return;
    state = state.copyWith(filter: f);
  }

  Future<void> updateStatus(String applicationId, JobStatus status) async {
    final user = ref.read(authProvider).appUser;
    final uid = user?.uid;
    if (uid == null || user!.isGuest) return;
    final current = state.items.firstWhere(
      (a) => a.id == applicationId,
      orElse: () => state.items.isEmpty
          ? throw StateError('No application $applicationId')
          : state.items.first,
    );
    await _repository.updateStatus(uid, applicationId, status);
    state = state.copyWith(
      lastMessage: '${current.job.company}: status set to ${status.label}',
    );
  }

  Future<void> addNote(String applicationId, String body) async {
    final user = ref.read(authProvider).appUser;
    final uid = user?.uid;
    if (uid == null || user!.isGuest) return;
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    final current = state.items.firstWhere(
      (a) => a.id == applicationId,
      orElse: () => state.items.first,
    );
    await _repository.addNote(uid, applicationId, trimmed);
    state = state.copyWith(lastMessage: 'Note added to ${current.job.company}');
  }
}

final applicationsProvider =
    NotifierProvider<ApplicationsNotifier, ApplicationsState>(ApplicationsNotifier.new);

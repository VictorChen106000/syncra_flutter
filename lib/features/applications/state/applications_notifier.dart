import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/firestore/applications_repository.dart';
import '../../../data/models/tracked_application.dart';
import '../../auth/state/auth_notifier.dart';
import '../services/application_bundle_summary.dart';

enum ApplicationsFilter {
  all,
  bundleReview,
  drafts,
  sent,
  replied;

  String get label => switch (this) {
    ApplicationsFilter.all => 'All',
    ApplicationsFilter.bundleReview => 'Bundle review',
    ApplicationsFilter.drafts => 'Drafts',
    ApplicationsFilter.sent => 'Sent',
    ApplicationsFilter.replied => 'Replied',
  };
}

@immutable
class ApplicationsState {
  const ApplicationsState({
    this.items = const [],
    this.filter = ApplicationsFilter.all,
    this.lastMessage,
  });

  final List<TrackedApplication> items;
  final ApplicationsFilter filter;
  final String? lastMessage;

  /// Items the filter accepts, already sorted newest-first by [TrackedApplication.sortAt].
  List<TrackedApplication> get filtered {
    final base = switch (filter) {
      ApplicationsFilter.all => items,
      ApplicationsFilter.bundleReview =>
        items.where((a) => evaluateApplicationBundle(a).hasBlocker).toList(),
      ApplicationsFilter.drafts =>
        items.where((a) => a.phase == ApplicationPhase.draft).toList(),
      ApplicationsFilter.sent =>
        items.where((a) => a.phase == ApplicationPhase.sent).toList(),
      ApplicationsFilter.replied =>
        items.where((a) => a.phase == ApplicationPhase.replied).toList(),
    };
    return List.of(base)..sort((a, b) => b.sortAt.compareTo(a.sortAt));
  }

  int countOf(ApplicationPhase phase) =>
      items.where((a) => a.phase == phase).length;

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
      return;
    }

    _boundUid = uid;
    _subscription = _repository
        .watchApplications(uid)
        .listen(
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

  TrackedApplication? _find(String applicationId) {
    for (final a in state.items) {
      if (a.id == applicationId) return a;
    }
    return null;
  }

  Future<void> markSent(String applicationId, {String? sentEmailId}) async {
    final uid = _boundUid;
    final app = _find(applicationId);
    if (uid == null || app == null) return;
    await _repository.markSent(uid, applicationId, sentEmailId: sentEmailId);
    state = state.copyWith(lastMessage: '${app.job.company} marked as sent');
  }

  Future<void> setGotReply(String applicationId, bool gotReply) async {
    final uid = _boundUid;
    final app = _find(applicationId);
    if (uid == null || app == null) return;
    await _repository.setGotReply(uid, applicationId, gotReply);
    state = state.copyWith(
      lastMessage: gotReply
          ? '${app.job.company}: marked replied'
          : '${app.job.company}: reply cleared',
    );
  }

  Future<void> setFollowUp(String applicationId, DateTime? followUpAt) async {
    final uid = _boundUid;
    if (uid == null || _find(applicationId) == null) return;
    await _repository.setFollowUp(uid, applicationId, followUpAt);
  }

  Future<void> addNote(String applicationId, String body) async {
    final uid = _boundUid;
    final app = _find(applicationId);
    if (uid == null || app == null) return;
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    await _repository.addNote(uid, applicationId, trimmed);
    state = state.copyWith(lastMessage: 'Note added to ${app.job.company}');
  }

  Future<void> updateNote(
    String applicationId,
    String noteId,
    String body,
  ) async {
    final uid = _boundUid;
    final app = _find(applicationId);
    if (uid == null || app == null) return;

    final trimmed = body.trim();
    if (trimmed.isEmpty) return;

    await _repository.updateNote(
      uid,
      applicationId,
      app.notes,
      noteId,
      trimmed,
    );
    state = state.copyWith(lastMessage: 'Note updated');
  }

  Future<void> deleteNote(String applicationId, String noteId) async {
    final uid = _boundUid;
    final app = _find(applicationId);
    if (uid == null || app == null) return;

    await _repository.deleteNote(uid, applicationId, app.notes, noteId);
    state = state.copyWith(lastMessage: 'Note deleted');
  }
}

final applicationsProvider =
    NotifierProvider<ApplicationsNotifier, ApplicationsState>(
      ApplicationsNotifier.new,
    );

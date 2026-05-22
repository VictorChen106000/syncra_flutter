import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/firestore/applications_repository.dart';
import '../../../data/firestore/pipeline_repository.dart';
import '../../../data/models/job.dart';
import '../../auth/state/auth_notifier.dart';

@immutable
class JobsState {
  const JobsState({
    this.cards = const [],
    this.savedIds = const {},
    this.hiddenIds = const {},
    this.dismissedIds = const {},
    this.lastMessage,
  });

  final List<PipelineCard> cards;
  final Set<String> savedIds;
  final Set<String> hiddenIds;
  final Set<String> dismissedIds;
  final String? lastMessage;

  List<PipelineCard> get pendingCards => cards;
  List<Job> get pendingJobs => cards.map((c) => c.job).toList(growable: false);

  bool isSaved(String id) => savedIds.contains(id);
  bool isHidden(String id) => hiddenIds.contains(id);
  bool isDismissed(String id) => dismissedIds.contains(id);

  JobsState copyWith({
    List<PipelineCard>? cards,
    Set<String>? savedIds,
    Set<String>? hiddenIds,
    Set<String>? dismissedIds,
    String? lastMessage,
    bool clearMessage = false,
  }) {
    return JobsState(
      cards: cards ?? this.cards,
      savedIds: savedIds ?? this.savedIds,
      hiddenIds: hiddenIds ?? this.hiddenIds,
      dismissedIds: dismissedIds ?? this.dismissedIds,
      lastMessage: clearMessage ? null : (lastMessage ?? this.lastMessage),
    );
  }
}

class JobsNotifier extends Notifier<JobsState> {
  JobsNotifier({
    PipelineRepository? repository,
    ApplicationsRepository? applicationsRepository,
  })  : _repository = repository ?? PipelineRepository(),
        _applications = applicationsRepository ?? ApplicationsRepository();

  final PipelineRepository _repository;
  final ApplicationsRepository _applications;

  StreamSubscription<List<PipelineCard>>? _subscription;
  String? _boundUid;

  @override
  JobsState build() {
    final auth = ref.watch(authProvider);
    final uid = auth.appUser?.uid;
    final isGuest = auth.appUser?.isGuest ?? true;
    _bindTo(uid, isGuest);

    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });

    // Empty until the Firestore pipeline stream emits its first snapshot.
    // Guests and signed-out users have no pipeline; for signed-in users
    // the agent's brief populates it.
    return const JobsState();
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
    _subscription = _repository.watchPending(uid).listen(
      (cards) {
        state = state.copyWith(cards: cards);
      },
      onError: (Object e) {
        debugPrint('pipeline stream error: $e');
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

  void toggleSaved(String id, {String label = ''}) {
    final next = {...state.savedIds};
    final added = !next.contains(id);
    if (added) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(
      savedIds: next,
      lastMessage: added
          ? (label.isEmpty ? 'Saved' : 'Saved $label')
          : (label.isEmpty ? 'Removed from saved' : 'Unsaved $label'),
    );
  }

  void hide(String id, {String label = ''}) {
    state = state.copyWith(
      hiddenIds: {...state.hiddenIds, id},
      dismissedIds: {...state.dismissedIds, id},
      lastMessage: label.isEmpty ? 'Hidden' : 'Hidden $label',
    );
  }

  void unhide(String id) {
    final h = {...state.hiddenIds}..remove(id);
    final d = {...state.dismissedIds}..remove(id);
    state = state.copyWith(hiddenIds: h, dismissedIds: d);
  }

  Future<void> dismiss(String id, {String label = ''}) async {
    state = state.copyWith(
      dismissedIds: {...state.dismissedIds, id},
      lastMessage: label.isEmpty ? 'Dismissed' : '$label dismissed',
    );
    final user = ref.read(authProvider).appUser;
    final uid = user?.uid;
    if (uid == null || user!.isGuest) return;
    final card = state.cards.firstWhere(
      (c) => c.job.id == id,
      orElse: () => state.cards.isEmpty
          ? throw StateError('No card $id')
          : state.cards.first,
    );
    try {
      await _repository.dismiss(uid, card.id);
    } catch (e) {
      debugPrint('dismiss card failed: $e');
    }
  }

  void undismiss(String id) {
    final next = {...state.dismissedIds}..remove(id);
    state = state.copyWith(dismissedIds: next);
  }

  /// Approves the pipeline card whose embedded job id matches [jobId]:
  /// marks the card as approved and creates a matching application doc
  /// that will appear in the tracker. Safe to call for guests (no-op).
  Future<void> approveByJobId(String jobId) async {
    final user = ref.read(authProvider).appUser;
    final uid = user?.uid;
    if (uid == null || user!.isGuest) return;
    final card = state.cards.where((c) => c.job.id == jobId).firstOrNull;
    if (card == null) return;
    try {
      final appId = await _applications.createApplication(
        uid: uid,
        job: card.job,
      );
      // Approving from the agent-pipeline screen means "the user accepts
      // this draft and intends to send it" — flip sent_at immediately. For
      // the v1 demo we don't actually call send_email here.
      await _applications.markSent(uid, appId);
      await _repository.approve(uid, card.id);
      state = state.copyWith(
        lastMessage: '${card.job.company} added to tracker',
      );
    } catch (e) {
      debugPrint('approve flow failed: $e');
      state = state.copyWith(lastMessage: 'Could not save application');
    }
  }
}

final jobsProvider = NotifierProvider<JobsNotifier, JobsState>(JobsNotifier.new);

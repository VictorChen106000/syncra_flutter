import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lifecycle of the single background task the app surfaces globally.
enum RunningTaskStatus { idle, running, completed, failed }

/// A snapshot of the background task shown in the global running-task banner.
@immutable
class RunningTaskState {
  const RunningTaskState({
    this.status = RunningTaskStatus.idle,
    this.label = '',
    this.detail,
  });

  final RunningTaskStatus status;

  /// Headline shown in the banner, e.g. "Tailoring resume…".
  final String label;

  /// Optional secondary line — null when there's nothing extra to say.
  final String? detail;

  /// Whether the banner should be on screen at all.
  bool get isActive => status != RunningTaskStatus.idle;

  bool get isRunning => status == RunningTaskStatus.running;
}

/// Single source of truth for "is something running in the background".
///
/// Any feature drives the global [RunningTaskBanner] by calling [start] /
/// [update] / [complete] / [fail]; any page reads the current status with
/// `ref.watch(runningTaskProvider)`. The notifier is deliberately NOT
/// `autoDispose` so a task — and its banner — survives the user navigating
/// away from the page that started it.
class RunningTaskNotifier extends Notifier<RunningTaskState> {
  Timer? _autoDismiss;

  /// How long a terminal ("completed" / "failed") banner lingers before it
  /// clears itself, so a finished task doesn't sit on screen forever.
  static const _terminalLinger = Duration(seconds: 4);

  @override
  RunningTaskState build() {
    ref.onDispose(() => _autoDismiss?.cancel());
    return const RunningTaskState();
  }

  /// Marks a new task as running, replacing whatever was showing before.
  void start(String label, {String? detail}) {
    _autoDismiss?.cancel();
    state = RunningTaskState(
      status: RunningTaskStatus.running,
      label: label,
      detail: detail,
    );
  }

  /// Updates the running task's label/detail without changing its status.
  /// No-op unless a task is actually running, so a late event can't resurrect
  /// a banner the user already dismissed.
  void update(String label, {String? detail}) {
    if (state.status != RunningTaskStatus.running) return;
    state = RunningTaskState(
      status: RunningTaskStatus.running,
      label: label,
      detail: detail,
    );
  }

  /// Marks the running task done. Shows a success banner that auto-clears
  /// after [_terminalLinger]. No-op unless a task was running, so a repeated
  /// completion event (or one after a dismiss) is harmless.
  void complete({String label = 'Task completed'}) {
    if (state.status != RunningTaskStatus.running) return;
    state = RunningTaskState(status: RunningTaskStatus.completed, label: label);
    _scheduleAutoDismiss();
  }

  /// Marks the running task failed. Same lifecycle as [complete].
  void fail({String label = 'Task failed', String? detail}) {
    if (state.status != RunningTaskStatus.running) return;
    state = RunningTaskState(
      status: RunningTaskStatus.failed,
      label: label,
      detail: detail,
    );
    _scheduleAutoDismiss();
  }

  /// Clears the banner immediately — a user dismiss, or a cancelled task.
  void dismiss() {
    _autoDismiss?.cancel();
    state = const RunningTaskState();
  }

  void _scheduleAutoDismiss() {
    _autoDismiss?.cancel();
    _autoDismiss = Timer(_terminalLinger, () {
      // Only clear if still in the terminal state we scheduled for — a new
      // task may have started during the linger window.
      if (state.status == RunningTaskStatus.completed ||
          state.status == RunningTaskStatus.failed) {
        state = const RunningTaskState();
      }
    });
  }
}

final runningTaskProvider =
    NotifierProvider<RunningTaskNotifier, RunningTaskState>(
  RunningTaskNotifier.new,
);

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/firestore/pipeline_repository.dart';
import '../../../data/models/job.dart';
import '../../auth/state/auth_notifier.dart';
import '../../jobs/state/jobs_notifier.dart';
import '../services/anthropic_service.dart';
import '../../agent_chat/models/agent_block.dart';
import '../../agent_chat/services/agent_service.dart';
import '../../agent_chat/services/anthropic_chat_service.dart';
import '../../agent_chat/tools/builtin_tools.dart';
import '../../agent_chat/tools/tool_registry.dart';
import '../../notifications/state/notifications_notifier.dart';

/// Lifecycle of the agent's passive job-discovery brief.
enum AgentBriefStatus { idle, scanning, matching, done, error }

class AgentActivityStep {
  AgentActivityStep({
    required this.tool,
    required this.detail,
    required this.status,
    required this.createdAt,
    this.undoable = false,
  });

  final String tool;
  final String detail;
  final String status; // 'active' | 'done' | 'waiting'
  final DateTime createdAt;
  final bool undoable;
}

@immutable
class PassiveAgentState {
  const PassiveAgentState({
    this.status = AgentBriefStatus.idle,
    this.lastBriefAt,
    this.pipeline = const [],
    this.activity = const [],
    this.briefId,
    this.lastMessage,
    this.lastError,
    this.morningBriefShown = false,
    this.isLiveModeEnabled = false,
  });

  final AgentBriefStatus status;
  final DateTime? lastBriefAt;
  final List<Job> pipeline;
  final List<AgentActivityStep> activity;
  final String? briefId;
  final String? lastMessage;
  final String? lastError;
  final bool morningBriefShown;
  final bool isLiveModeEnabled;

  bool get hasPipeline => pipeline.isNotEmpty;
  bool get isRunning =>
      status == AgentBriefStatus.scanning ||
      status == AgentBriefStatus.matching;

  int get readyCount =>
      pipeline.where((j) => j.category == JobCategory.ready).length;
  int get inputNeededCount =>
      pipeline.where((j) => j.category == JobCategory.inputNeeded).length;
  int get explorationCount =>
      pipeline.where((j) => j.category == JobCategory.exploration).length;

  Job? get topMatch {
    if (pipeline.isEmpty) return null;
    final ranked = [...pipeline]
      ..sort((a, b) => b.matchScore.compareTo(a.matchScore));
    return ranked.firstWhere(
      (j) => j.category == JobCategory.ready,
      orElse: () => ranked.first,
    );
  }

  PassiveAgentState copyWith({
    AgentBriefStatus? status,
    DateTime? lastBriefAt,
    List<Job>? pipeline,
    List<AgentActivityStep>? activity,
    String? briefId,
    String? lastMessage,
    String? lastError,
    bool? morningBriefShown,
    bool? isLiveModeEnabled,
    bool clearMessage = false,
    bool clearError = false,
  }) {
    return PassiveAgentState(
      status: status ?? this.status,
      lastBriefAt: lastBriefAt ?? this.lastBriefAt,
      pipeline: pipeline ?? this.pipeline,
      activity: activity ?? this.activity,
      briefId: briefId ?? this.briefId,
      lastMessage: clearMessage ? null : (lastMessage ?? this.lastMessage),
      lastError: clearError ? null : (lastError ?? this.lastError),
      morningBriefShown: morningBriefShown ?? this.morningBriefShown,
      isLiveModeEnabled: isLiveModeEnabled ?? this.isLiveModeEnabled,
    );
  }
}

class PassiveAgentNotifier extends Notifier<PassiveAgentState> {
  static const _defaultBriefQuery =
      'UX Designer Frontend Developer Product Designer';

  String _briefPrompt(String query) =>
      '''
    Run today's career brief.

    Use the tool flow only:
    1. Call search_jobs with query "$query" and location "Remote".
    2. Call read_resume.
    3. Call match_jobs for the best jobs returned by search_jobs.
    4. Call save_to_pipeline once for each of the top 5 matched jobs.

    Rules:
    - Save at most 5 jobs.
    - Do not call tailor_resume.
    - Do not call draft_email.
    - Do not call send_email.
    - Do not ask the user questions during this brief. If information is missing, classify the job as input_needed and save it to the pipeline.
    - If read_resume returns no resume (the user has not uploaded one yet),
      skip match_jobs and instead save the top 5 search results directly with
      category "exploration" — do not fabricate scores.
    - End with one short sentence summarizing what you saved.
    ''';
  PassiveAgentNotifier({
    AnthropicService? service,
    PipelineRepository? pipelineRepository,
  }) : _service = service ?? AnthropicService(),
       _pipelineRepository = pipelineRepository ?? PipelineRepository();

  final AnthropicService _service;
  final PipelineRepository _pipelineRepository;

  /// The brief's own agentic-loop service. Built lazily and reused across
  /// briefs, with its own [ToolRegistry] so the brief's threaded run can't
  /// pollute (or be polluted by) the chat's running conversation. The brief
  /// is a self-contained one-shot, so it owns its service rather than sharing
  /// the chat's `agentServiceProvider`.
  AnthropicChatService? _briefService;

  AnthropicChatService _ensureBriefService() {
    final existing = _briefService;
    if (existing != null) return existing;
    final registry = ToolRegistry();
    registerBuiltinTools(registry);
    return _briefService = AnthropicChatService(registry: registry);
  }

  @override
  PassiveAgentState build() {
    ref.onDispose(() {
      _service.dispose();
    });
    // Mirror the combined pipeline that jobsProvider already streams from
    // Firestore — one listener, one source of truth. It reflects everything
    // saved by BOTH the passive brief and the chatbot's `save_to_pipeline`
    // tool (same collection), survives app restarts, and re-binds on auth
    // change. `ref.listen` (not `watch`) keeps pipeline updates from wiping
    // the brief's in-progress activity log via a rebuild.
    ref.listen(
      jobsProvider.select((s) => s.pendingJobs),
      (_, jobs) => state = state.copyWith(pipeline: jobs),
    );
    return PassiveAgentState(
      isLiveModeEnabled: _service.hasApiKey,
      pipeline: ref.read(jobsProvider).pendingJobs,
    );
  }

  String? consumeMessage() {
    final m = state.lastMessage;
    if (m != null) {
      state = state.copyWith(clearMessage: true);
    }
    return m;
  }

  void markMorningBriefShown() {
    if (state.morningBriefShown) return;
    state = state.copyWith(morningBriefShown: true);
  }

  /// Kicks off the agent brief. [query] overrides the default search keyword
  /// set — onboarding passes the user's just-captured target role here so the
  /// pipeline that lands on the dashboard is actually relevant to them.
  Future<void> runBrief({String? query}) async {
    if (state.isRunning) return;

    final service = _ensureBriefService();
    final effectiveQuery =
        (query == null || query.trim().isEmpty) ? _defaultBriefQuery : query.trim();

    // No mock path anymore: the brief always runs through the real Anthropic
    // agent + live job search. Without a key there's nothing to fake, so we
    // surface an actionable error instead of inventing a pipeline.
    if (!service.hasApiKey) {
      state = state.copyWith(
        status: AgentBriefStatus.error,
        lastError:
            'Add an ANTHROPIC_API_KEY (--dart-define) to run the agent brief.',
        lastMessage: 'Brief needs an Anthropic API key',
        clearMessage: false,
      );
      return;
    }

    await _runAgentBrief(service, query: effectiveQuery);
  }

  Future<void> _runAgentBrief(AgentService service, {required String query}) async {
    state = state.copyWith(
      briefId: 'brief_${DateTime.now().millisecondsSinceEpoch}',
      status: AgentBriefStatus.scanning,
      clearError: true,
    );

    _pushActivity(
      AgentActivityStep(
        tool: 'Syncra Agent',
        detail: 'Running today\'s brief through the agent tool loop…',
        status: 'active',
        createdAt: DateTime.now(),
      ),
    );

    var savedCount = 0;
    var failedCount = 0;
    String? turnFailure;

    try {
      // The brief is a self-contained one-shot — run it non-threaded so it
      // neither inherits nor pollutes the chat's running conversation.
      await for (final event in service.runPrompt(
        prompt: _briefPrompt(query),
        threaded: false,
      )) {
        ref.read(notificationsProvider.notifier).onAgentEvent(event);

        switch (event) {
          case BlockAdded(:final block):
            _handleBriefBlock(block);

          case ToolCallCompleted(:final summary, :final status):
            if (status == ToolCallStatus.failed) {
              failedCount += 1;
            }

            final normalizedSummary = summary.toLowerCase();
            if (status == ToolCallStatus.done &&
                normalizedSummary.startsWith('saved ') &&
                normalizedSummary.contains(' to pipeline')) {
              savedCount += 1;
            }

            _markFirstActivityDone();

          case TurnFailed(:final message):
            turnFailure = message;

          case TurnCompleted():
            break;
        }
      }

      final now = DateTime.now();
      final hadHardFailure =
          turnFailure != null || (failedCount > 0 && savedCount == 0);

      final refreshedPipeline = hadHardFailure
          ? state.pipeline
          : await _fetchPendingPipelineJobs();

      state = state.copyWith(
        pipeline: refreshedPipeline,
        status: hadHardFailure ? AgentBriefStatus.error : AgentBriefStatus.done,
        lastBriefAt: hadHardFailure ? state.lastBriefAt : now,
        lastError: hadHardFailure
            ? (turnFailure ??
                  'The agent brief hit tool failures before saving jobs.')
            : null,
        clearError: !hadHardFailure,
        lastMessage: savedCount > 0
            ? 'Brief complete · $savedCount roles saved to pipeline'
            : 'Brief complete · check notifications for details',
      );

      _pushActivity(
        AgentActivityStep(
          tool: 'BriefPipeline',
          detail: savedCount > 0
              ? 'Saved $savedCount roles to your pipeline.'
              : 'Brief completed. Check notifications for details.',
          status: hadHardFailure ? 'waiting' : 'done',
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      _markFirstActivityDone();
      state = state.copyWith(
        status: AgentBriefStatus.error,
        lastError: e.toString(),
        lastMessage: 'Brief failed unexpectedly',
      );
      _pushActivity(
        AgentActivityStep(
          tool: 'BriefPipeline',
          detail: 'Brief failed: $e',
          status: 'waiting',
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  Future<List<Job>> _fetchPendingPipelineJobs() async {
    final user = ref.read(authProvider).appUser;
    final uid = user?.uid;
    final isGuest = user?.isGuest ?? true;

    if (uid == null || isGuest) {
      return const [];
    }

    try {
      final cards = await _pipelineRepository.fetchPending(uid);
      return cards.map((card) => card.job).toList(growable: false);
    } catch (e) {
      debugPrint('pending pipeline refresh failed: $e');
      return const [];
    }
  }

  void _handleBriefBlock(AgentBlock block) {
    if (block is ToolCallBlock) {
      final nextStatus = switch (block.name) {
        'match_jobs' || 'save_to_pipeline' => AgentBriefStatus.matching,
        _ => AgentBriefStatus.scanning,
      };

      if (state.status != nextStatus) {
        state = state.copyWith(status: nextStatus);
      }

      _pushActivity(
        AgentActivityStep(
          tool: _briefToolLabel(block.name),
          detail: block.label,
          status: 'active',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    if (block is TextBlock) {
      final text = block.text.trim();
      if (text.isEmpty) return;

      _pushActivity(
        AgentActivityStep(
          tool: 'Syncra',
          detail: text.length > 120 ? '${text.substring(0, 120)}…' : text,
          status: 'done',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    if (block is InputRequestBlock) {
      _pushActivity(
        AgentActivityStep(
          tool: 'Input needed',
          detail: block.question,
          status: 'waiting',
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  String _briefToolLabel(String toolName) {
    return switch (toolName) {
      'search_jobs' => 'Job Search',
      'read_resume' => 'Resume Context',
      'match_jobs' => 'Match Scoring',
      'save_to_pipeline' => 'Pipeline Save',
      _ => toolName,
    };
  }

  void _pushActivity(AgentActivityStep step) {
    state = state.copyWith(activity: [step, ...state.activity]);
  }

  void _markFirstActivityDone() {
    if (state.activity.isEmpty) return;
    final first = state.activity.first;
    if (first.status != 'active') return;
    final next = [...state.activity];
    next[0] = AgentActivityStep(
      tool: first.tool,
      detail: first.detail,
      status: 'done',
      createdAt: first.createdAt,
      undoable: true,
    );
    state = state.copyWith(activity: next);
  }
}

final passiveAgentProvider =
    NotifierProvider<PassiveAgentNotifier, PassiveAgentState>(
      PassiveAgentNotifier.new,
    );

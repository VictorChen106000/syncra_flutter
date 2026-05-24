import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/firestore/firestore_paths.dart';
import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/pipeline_repository.dart';
import '../../../data/models/job.dart';
import '../../auth/state/auth_notifier.dart';
import '../../jobs/state/jobs_notifier.dart';
import '../services/anthropic_service.dart';
import '../../agent_chat/models/agent_block.dart';
import '../../agent_chat/services/agent_service.dart';
import '../../agent_chat/services/anthropic_chat_service.dart';
import '../../agent_chat/state/agent_chat_notifier.dart';
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
  static const _briefPrompt = '''
    Run today's career brief.

    Use the tool flow only:
    1. Call search_jobs with query "UX Designer Frontend Developer Product Designer" and location "Remote".
    2. Call read_resume.
    3. Call match_jobs for the best jobs returned by search_jobs.
    4. Call save_to_pipeline once for each of the top 5 matched jobs.

    Rules:
    - Save at most 5 jobs.
    - Do not call tailor_resume.
    - Do not call draft_email.
    - Do not call send_email.
    - Do not ask the user questions during this brief. If information is missing, classify the job as input_needed and save it to the pipeline.
    - End with one short sentence summarizing what you saved.
    ''';
  PassiveAgentNotifier({
    AnthropicService? service,
    JobsRepository? jobsRepository,
    PipelineRepository? pipelineRepository,
  }) : _service = service ?? AnthropicService(),
       _jobsRepository = jobsRepository ?? JobsRepository(),
       _pipelineRepository = pipelineRepository ?? PipelineRepository();

  final AnthropicService _service;
  final JobsRepository _jobsRepository;
  final PipelineRepository _pipelineRepository;

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

  Future<void> runBrief() async {
    if (state.isRunning) return;

    final service = ref.read(agentServiceProvider);

    if (service is AnthropicChatService && service.hasApiKey) {
      await _runAgentBrief(service);
      return;
    }

    await _runLegacyMockBrief();
  }

  Future<void> _runAgentBrief(AgentService service) async {
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
        prompt: _briefPrompt,
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

  /// Kicks off a fresh agent brief.
  Future<void> _runLegacyMockBrief() async {
    if (state.isRunning) return;

    state = state.copyWith(
      briefId: 'brief_${DateTime.now().millisecondsSinceEpoch}',
      status: AgentBriefStatus.scanning,
      clearError: true,
    );

    List<Job> candidates = const [];
    try {
      candidates = await _jobsRepository.fetchAll();
    } catch (e) {
      debugPrint('jobs fetch failed: $e');
    }
    if (candidates.isEmpty) {
      _markFirstActivityDone();
      state = state.copyWith(
        status: AgentBriefStatus.done,
        lastBriefAt: DateTime.now(),
        lastMessage: 'Brief complete · no new roles found',
      );
      _pushActivity(
        AgentActivityStep(
          tool: 'BriefPipeline',
          detail: 'No candidate roles available right now.',
          status: 'done',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    _pushActivity(
      AgentActivityStep(
        tool: 'Firestore',
        detail: 'Scanning ${candidates.length} candidate roles…',
        status: 'active',
        createdAt: DateTime.now(),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 400));
    _markFirstActivityDone();
    state = state.copyWith(status: AgentBriefStatus.matching);
    _pushActivity(
      AgentActivityStep(
        tool: _service.hasApiKey ? 'Claude Haiku' : 'BriefPipeline',
        detail: _service.hasApiKey
            ? 'Asking Claude Haiku to score each role against your resume…'
            : 'Listing candidate roles (set ANTHROPIC_API_KEY to score them)…',
        status: 'active',
        createdAt: DateTime.now(),
      ),
    );

    final user = ref.read(authProvider).appUser;
    final uid = user?.uid;
    final isGuest = user?.isGuest ?? true;

    try {
      List<Job> nextPipeline;
      final resumeJson = (uid != null && !isGuest && _service.hasApiKey)
          ? await _loadResumeJsonForBrief(uid)
          : null;
      if (_service.hasApiKey && resumeJson != null) {
        final results = await _service.scoreJobs(
          resume: resumeJson,
          jobs: candidates,
        );
        nextPipeline = results != null
            ? _applyResults(candidates, results)
            : List.of(candidates);
      } else {
        await Future.delayed(const Duration(milliseconds: 900));
        nextPipeline = List.of(candidates);
      }

      if (uid != null && !isGuest && nextPipeline.isNotEmpty) {
        for (final j in nextPipeline) {
          try {
            await _pipelineRepository.createCard(
              uid: uid,
              job: j,
              category: j.category,
              matchScore: j.matchScore,
              agentAction: j.agentAction,
              agentJustification: j.agentJustification,
              matchedSkills: j.skills,
              missingSkills: j.missingSkills,
            );
          } catch (e) {
            debugPrint('pipeline card write failed: $e');
          }
        }
      }

      final readyCount = nextPipeline
          .where((j) => j.category == JobCategory.ready)
          .length;
      final inputCount = nextPipeline
          .where((j) => j.category == JobCategory.inputNeeded)
          .length;
      final explorationCount = nextPipeline
          .where((j) => j.category == JobCategory.exploration)
          .length;

      _markFirstActivityDone();
      state = state.copyWith(
        pipeline: nextPipeline,
        status: AgentBriefStatus.done,
        lastBriefAt: DateTime.now(),
        lastMessage: 'Brief complete · ${nextPipeline.length} roles scored',
      );
      _pushActivity(
        AgentActivityStep(
          tool: 'BriefPipeline',
          detail:
              'Found $readyCount ready · $inputCount need input · $explorationCount strategic.',
          status: 'done',
          createdAt: DateTime.now(),
        ),
      );
    } on AnthropicException catch (e) {
      _markFirstActivityDone();
      state = state.copyWith(
        status: AgentBriefStatus.error,
        lastError: e.message,
        lastMessage: 'Brief failed: ${e.message}',
      );
      _pushActivity(
        AgentActivityStep(
          tool: 'Claude Haiku',
          detail: 'Brief failed: ${e.message}',
          status: 'waiting',
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

  List<Job> _applyResults(List<Job> jobs, List<MatcherResult> results) {
    final byId = {for (final r in results) r.jobId: r};
    return jobs.map((job) {
      final r = byId[job.id];
      if (r == null) return job;
      final action = switch (r.category) {
        JobCategory.ready => 'Ready to send',
        JobCategory.inputNeeded => 'Missing requirement',
        JobCategory.exploration => 'Strategic pivot',
      };
      return Job(
        id: job.id,
        title: job.title,
        company: job.company,
        location: job.location,
        salary: job.salary,
        category: r.category,
        matchScore: r.matchScore,
        agentAction: action,
        agentJustification: r.justification.isEmpty
            ? job.agentJustification
            : r.justification,
        skills: job.skills,
        missingSkills: r.missingSkills.isEmpty
            ? job.missingSkills
            : r.missingSkills,
        why: job.why,
      );
    }).toList();
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

  /// Reads the latest manual resume's cached structured JSON for brief
  /// scoring. Returns `null` when the user has no parsed resume yet — the
  /// brief then lists candidates unscored rather than inventing a resume.
  Future<Map<String, dynamic>?> _loadResumeJsonForBrief(String uid) async {
    try {
      final snap = await FirestorePaths(
        FirebaseFirestore.instance,
      ).resumes(uid).orderBy('uploaded_at', descending: true).limit(10).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['source'] == 'manual' && data['resume_json'] is Map) {
          return (data['resume_json'] as Map).cast<String, dynamic>();
        }
      }
    } catch (e) {
      debugPrint('brief resume load failed: $e');
    }
    return null;
  }
}

final passiveAgentProvider =
    NotifierProvider<PassiveAgentNotifier, PassiveAgentState>(
      PassiveAgentNotifier.new,
    );

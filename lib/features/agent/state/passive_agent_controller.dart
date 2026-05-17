import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/pipeline_repository.dart';
import '../../../fixtures/mock_agent_steps.dart';
import '../../../fixtures/mock_jobs.dart';
import '../../../data/models/job.dart';
import '../../auth/state/auth_controller.dart';
import '../data/fake_resume.dart';
import '../services/anthropic_service.dart';

/// Lifecycle of the agent's passive job-discovery brief.
///
/// Mirrors the backend brief states described in `backend/README.md`:
/// idle → scanning sources → matching → done. Now wired to call
/// Anthropic's Claude (Haiku) directly when an API key is configured.
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

class PassiveAgentController extends ChangeNotifier {
  PassiveAgentController({
    AuthController? auth,
    AnthropicService? service,
    JobsRepository? jobsRepository,
    PipelineRepository? pipelineRepository,
  })  : _auth = auth,
        _service = service ?? AnthropicService(),
        _jobsRepository = jobsRepository ?? JobsRepository(),
        _pipelineRepository = pipelineRepository ?? PipelineRepository() {
    _seedFromMocks();
  }

  final AuthController? _auth;
  final AnthropicService _service;
  final JobsRepository _jobsRepository;
  final PipelineRepository _pipelineRepository;

  AgentBriefStatus _status = AgentBriefStatus.idle;
  DateTime? _lastBriefAt;
  List<Job> _pipeline = const [];
  final List<AgentActivityStep> _activity = [];
  String? _briefId;
  String? _lastMessage;
  String? _lastError;
  bool _morningBriefShown = false;

  AgentBriefStatus get status => _status;
  DateTime? get lastBriefAt => _lastBriefAt;
  List<Job> get pipeline => List.unmodifiable(_pipeline);
  List<AgentActivityStep> get activity => List.unmodifiable(_activity);
  String? get briefId => _briefId;
  String? get lastError => _lastError;

  /// True after the user has seen and dismissed the morning brief once this
  /// session. The router uses this to send fresh sign-ins to the brief
  /// first, but never twice.
  bool get morningBriefShown => _morningBriefShown;

  /// True once the agent has produced at least one pipeline.
  bool get hasPipeline => _pipeline.isNotEmpty;

  /// Whether the service is configured with a real Anthropic key. UI uses
  /// this to surface a "running in mock mode" hint.
  bool get isLiveModeEnabled => _service.hasApiKey;

  bool get isRunning =>
      _status == AgentBriefStatus.scanning ||
      _status == AgentBriefStatus.matching;

  int get readyCount =>
      _pipeline.where((j) => j.category == JobCategory.ready).length;
  int get inputNeededCount =>
      _pipeline.where((j) => j.category == JobCategory.inputNeeded).length;
  int get explorationCount =>
      _pipeline.where((j) => j.category == JobCategory.exploration).length;

  /// Top "ready" pipeline card, or the highest scored card overall. Used
  /// by the morning brief page to highlight the agent's best find.
  Job? get topMatch {
    if (_pipeline.isEmpty) return null;
    final ranked = [..._pipeline]
      ..sort((a, b) => b.matchScore.compareTo(a.matchScore));
    return ranked.firstWhere(
      (j) => j.category == JobCategory.ready,
      orElse: () => ranked.first,
    );
  }

  String? consumeMessage() {
    final m = _lastMessage;
    _lastMessage = null;
    return m;
  }

  void markMorningBriefShown() {
    if (_morningBriefShown) return;
    _morningBriefShown = true;
    notifyListeners();
  }

  /// Kicks off a fresh agent brief. If an Anthropic API key is set
  /// (`--dart-define=ANTHROPIC_API_KEY=…`), this hits the live Messages API
  /// using a baked-in fake resume. Otherwise it runs the simulated flow so
  /// the demo UX still works.
  Future<void> runBrief() async {
    if (isRunning) return;

    _briefId = 'brief_${DateTime.now().millisecondsSinceEpoch}';
    _status = AgentBriefStatus.scanning;
    _lastError = null;
    notifyListeners();

    // 1. Pull candidate jobs from Firestore. Fall back to mocks if empty.
    List<Job> candidates = const [];
    try {
      candidates = await _jobsRepository.fetchAll();
    } catch (e) {
      debugPrint('jobs fetch failed: $e');
    }
    if (candidates.isEmpty) {
      candidates = List.of(MockJobs.all);
    }

    _activity.insert(
      0,
      AgentActivityStep(
        tool: 'Firestore',
        detail: 'Scanning ${candidates.length} candidate roles…',
        status: 'active',
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 400));
    _markFirstActivityDone();
    _status = AgentBriefStatus.matching;
    _activity.insert(
      0,
      AgentActivityStep(
        tool: _service.hasApiKey ? 'Claude Haiku' : 'MatchAnalyzer (mock)',
        detail: _service.hasApiKey
            ? 'Asking Claude Haiku to score each role against your resume…'
            : 'Scoring matches using local rubric (no API key set)…',
        status: 'active',
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();

    try {
      if (_service.hasApiKey) {
        final results = await _service.scoreJobs(
          resume: kFakeResumeJson,
          jobs: candidates,
        );
        if (results != null) {
          _pipeline = _applyResults(candidates, results);
        } else {
          _pipeline = List.of(candidates);
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 900));
        _pipeline = List.of(candidates);
      }

      // 2. Persist scored cards into Firestore so the jobs page sees them.
      final uid = _auth?.appUser?.uid;
      final isGuest = _auth?.appUser?.isGuest ?? true;
      if (uid != null && !isGuest && _pipeline.isNotEmpty) {
        for (final j in _pipeline) {
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

      _lastBriefAt = DateTime.now();
      _status = AgentBriefStatus.done;
      _markFirstActivityDone();
      _activity.insert(
        0,
        AgentActivityStep(
          tool: 'BriefPipeline',
          detail:
              'Found $readyCount ready · $inputNeededCount need input · $explorationCount strategic.',
          status: 'done',
          createdAt: DateTime.now(),
        ),
      );
      _lastMessage = 'Brief complete · ${_pipeline.length} roles scored';
    } on AnthropicException catch (e) {
      _status = AgentBriefStatus.error;
      _lastError = e.message;
      _markFirstActivityDone();
      _activity.insert(
        0,
        AgentActivityStep(
          tool: 'Claude Haiku',
          detail: 'Brief failed: ${e.message}',
          status: 'waiting',
          createdAt: DateTime.now(),
        ),
      );
      _lastMessage = 'Brief failed: ${e.message}';
    } catch (e) {
      _status = AgentBriefStatus.error;
      _lastError = e.toString();
      _markFirstActivityDone();
      _activity.insert(
        0,
        AgentActivityStep(
          tool: 'BriefPipeline',
          detail: 'Brief failed: $e',
          status: 'waiting',
          createdAt: DateTime.now(),
        ),
      );
      _lastMessage = 'Brief failed unexpectedly';
    }

    notifyListeners();
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
        agentJustification:
            r.justification.isEmpty ? job.agentJustification : r.justification,
        skills: job.skills,
        missingSkills: r.missingSkills.isEmpty ? job.missingSkills : r.missingSkills,
        why: job.why,
      );
    }).toList();
  }

  void _markFirstActivityDone() {
    if (_activity.isEmpty) return;
    final first = _activity.first;
    if (first.status != 'active') return;
    _activity[0] = AgentActivityStep(
      tool: first.tool,
      detail: first.detail,
      status: 'done',
      createdAt: first.createdAt,
      undoable: true,
    );
  }

  void _seedFromMocks() {
    final now = DateTime.now();
    for (final step in MockAgentSteps.activityFeed) {
      _activity.add(
        AgentActivityStep(
          tool: step['tool'] ?? '',
          detail: step['detail'] ?? '',
          status: step['status'] ?? 'done',
          createdAt: now,
          undoable: step['undoable'] == 'true',
        ),
      );
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}

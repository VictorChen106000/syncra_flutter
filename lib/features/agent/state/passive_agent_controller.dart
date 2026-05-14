import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/mock/mock_agent_steps.dart';
import '../../../data/mock/mock_jobs.dart';
import '../../../data/models/job.dart';

/// Lifecycle of the agent's passive job-discovery brief.
///
/// Mirrors the backend brief states described in `backend/README.md`:
/// idle → scanning sources → matching → done. UI ready, hookup site
/// for `POST /agent/brief` → poll `GET /agent/brief/{id}` → `GET /agent/pipeline`.
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
  PassiveAgentController() {
    _seedFromMocks();
  }

  AgentBriefStatus _status = AgentBriefStatus.idle;
  DateTime? _lastBriefAt;
  List<Job> _pipeline = const [];
  final List<AgentActivityStep> _activity = [];
  String? _briefId;
  Timer? _pollTimer;
  String? _lastMessage;

  AgentBriefStatus get status => _status;
  DateTime? get lastBriefAt => _lastBriefAt;
  List<Job> get pipeline => List.unmodifiable(_pipeline);
  List<AgentActivityStep> get activity => List.unmodifiable(_activity);
  String? get briefId => _briefId;
  bool get isRunning =>
      _status == AgentBriefStatus.scanning ||
      _status == AgentBriefStatus.matching;
  int get readyCount =>
      _pipeline.where((j) => j.category == JobCategory.ready).length;
  int get inputNeededCount =>
      _pipeline.where((j) => j.category == JobCategory.inputNeeded).length;
  int get explorationCount =>
      _pipeline.where((j) => j.category == JobCategory.exploration).length;

  String? consumeMessage() {
    final m = _lastMessage;
    _lastMessage = null;
    return m;
  }

  /// Kicks off a fresh agent brief. Wire to `POST /agent/brief` and replace
  /// the simulated polling below.
  Future<void> runBrief() async {
    if (isRunning) return;

    _briefId = 'brief_${DateTime.now().millisecondsSinceEpoch}';
    _status = AgentBriefStatus.scanning;
    _activity.insert(
      0,
      AgentActivityStep(
        tool: 'JobScraperAPI',
        detail: 'Scanning job boards for matches...',
        status: 'active',
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();

    _pollTimer?.cancel();
    var ticks = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 900), (timer) {
      ticks += 1;
      if (ticks == 2) {
        _status = AgentBriefStatus.matching;
        _markFirstActivityDone();
        _activity.insert(
          0,
          AgentActivityStep(
            tool: 'MatchAnalyzer',
            detail: 'Scoring fit on ${MockJobs.all.length} candidate roles...',
            status: 'active',
            createdAt: DateTime.now(),
          ),
        );
        notifyListeners();
      } else if (ticks >= 4) {
        timer.cancel();
        _markFirstActivityDone();
        _pipeline = List.of(MockJobs.all);
        _lastBriefAt = DateTime.now();
        _status = AgentBriefStatus.done;
        _activity.insert(
          0,
          AgentActivityStep(
            tool: 'BriefPipeline',
            detail:
                'Found $readyCount ready · $inputNeededCount need input · $explorationCount strategic.',
            status: 'done',
            createdAt: DateTime.now(),
            undoable: false,
          ),
        );
        _lastMessage = 'Brief complete · ${_pipeline.length} roles scored';
        notifyListeners();
      }
    });
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
    // Show prior activity so the page is never empty on first view.
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
    _pollTimer?.cancel();
    super.dispose();
  }
}

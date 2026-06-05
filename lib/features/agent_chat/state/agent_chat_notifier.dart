import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/router/route_names.dart';
import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/resumes_repository.dart';
import '../../../data/models/job.dart';
import '../../../shared/state/running_task_notifier.dart';
import '../../auth/state/auth_notifier.dart';
import '../../notifications/models/app_notification.dart';
import '../../notifications/state/notifications_notifier.dart';
import '../../jobs/state/jobs_notifier.dart';
import '../../resumes/services/resume_parser_service.dart';
import '../../resumes/services/resume_tailor_orchestrator.dart';
import '../../resumes/state/resume_notifier.dart';
import '../models/agent_block.dart';
import '../models/chat_message.dart';
import '../models/conversation_summary.dart';
import '../services/agent_service.dart';
import '../services/anthropic_chat_service.dart';
import '../services/chat_history_repository.dart';
import '../tools/builtin_tools.dart';
import '../tools/tool_registry.dart';
import 'dart:typed_data';

/// The active [AgentService] for the app — Claude via the tool-use loop.
/// Requires an `ANTHROPIC_API_KEY`; without one the agent surfaces an error
/// at call time rather than falling back to scripted responses.
final agentServiceProvider = Provider<AgentService>((ref) {
  final registry = ToolRegistry();
  registerBuiltinTools(registry);
  return AnthropicChatService(registry: registry);
});

/// Persists the recoverable full chat UI snapshot so chats survive app
/// restarts. Scoped to the signed-in user's Firestore subtree.
final chatHistoryRepositoryProvider = Provider<ChatHistoryRepository>(
  (ref) => ChatHistoryRepository(),
);

/// Live list of saved conversations for the history drawer. Empty for guests
/// — they have no Firestore subtree to read.
final conversationListProvider =
    StreamProvider.autoDispose<List<ConversationSummary>>((ref) {
      final repo = ref.watch(chatHistoryRepositoryProvider);
      final user = ref.watch(authProvider).appUser;
      if (user == null || user.isGuest) {
        return Stream.value(const <ConversationSummary>[]);
      }
      return repo.watchConversations(user.uid);
    });

/// One-slot "draft" handed from a prompt card to the chat composer. A prompt
/// card (on the dashboard or in the chat's empty state) drops its prompt here
/// and routes to the chat; [ChatInputBar] picks it up, pre-fills the field,
/// and clears this — nothing sends until the user taps Send. This is what lets
/// the user attach a resume before the prompt actually runs.
final composerDraftProvider = StateProvider<String?>((ref) => null);

@immutable
class AgentChatState {
  const AgentChatState({
    required this.items,
    required this.conversationId,
    this.isStreaming = false,
    this.threadJob,
  });

  final List<ChatItem> items;

  /// Firestore document id this transcript persists to. Switching chats from
  /// the history drawer swaps this; "New chat" mints a fresh one.
  final String conversationId;

  final bool isStreaming;

  /// When set, the chat is scoped to a single job — surfaces a context chip
  /// in the header and gates the opening message to that role.
  final Job? threadJob;

  AgentChatState copyWith({
    List<ChatItem>? items,
    String? conversationId,
    bool? isStreaming,
    Job? threadJob,
    bool clearThreadJob = false,
  }) {
    return AgentChatState(
      items: items ?? this.items,
      conversationId: conversationId ?? this.conversationId,
      isStreaming: isStreaming ?? this.isStreaming,
      threadJob: clearThreadJob ? null : (threadJob ?? this.threadJob),
    );
  }
}

class AgentChatNotifier extends Notifier<AgentChatState> {
  late AgentService _service;
  late ChatHistoryRepository _history;
  late ResumesRepository _resumesRepository;
  late ResumeTailorOrchestrator _orchestrator;
  StreamSubscription<AgentEvent>? _activeSub;
  AgentTurn? _activeTurn;
  Timer? _persistDebounce;
  int _seq = 0;
  bool _hydrating = false;
  bool _serviceReady = false;
  bool _threadPipelineMarkedComplete = false;

  @override
  AgentChatState build() {
    _service = ref.watch(agentServiceProvider);
    _serviceReady = true;
    _history = ref.watch(chatHistoryRepositoryProvider);
    _resumesRepository = ResumesRepository();
    _orchestrator = ResumeTailorOrchestrator(
      resumesRepository: _resumesRepository,
      jobsRepository: JobsRepository(),
      parser: ResumeParserService(),
    );
    _seq = 0;
    _threadPipelineMarkedComplete = false;
    ref.onDispose(() {
      _serviceReady = false;
      _activeSub?.cancel();
      _persistDebounce?.cancel();
    });

    // Hydrate the most recent saved conversation in the background. We start
    // from a fresh opener and replace once the load completes, *iff* the user
    // hasn't already started a new conversation in the meantime.
    _hydrateFromFirestore();

    return AgentChatState(
      items: [_buildOpener(null)],
      conversationId: _newConversationId(),
    );
  }

  /// Mints a unique Firestore document id for a new conversation.
  String _newConversationId() =>
      'conv-${DateTime.now().microsecondsSinceEpoch}';

  String? get _uid {
    final user = ref.read(authProvider).appUser;
    if (user == null || user.isGuest) return null;
    return user.uid;
  }

  /// The global running-task banner. Driven so a prompt's progress stays
  /// visible from any page once the user navigates away from the chat.
  RunningTaskNotifier get _runningTask =>
      ref.read(runningTaskProvider.notifier);

  Future<void> _hydrateFromFirestore() async {
    final uid = _uid;
    if (uid == null) return;
    _hydrating = true;
    try {
      final convos = await _history.listConversations(uid);
      if (convos.isEmpty) return;
      // Only apply hydration if the user hasn't already typed or opened a
      // thread since build() — otherwise we'd clobber their in-progress work.
      final current = state;
      final isUntouched =
          current.items.length == 1 &&
          current.items.first is AgentTurn &&
          current.threadJob == null;
      if (!isUntouched) return;
      final mostRecent = convos.first;
      final saved = await _history.loadConversation(uid, mostRecent.id);
      if (saved.items.isEmpty) return;
      state = AgentChatState(
        items: _restoreHistoryItems(saved.items),
        conversationId: mostRecent.id,
        threadJob: saved.threadJob,
      );
      // Make sure subsequent IDs don't collide with hydrated ones.
      _seq = saved.items.length + 1;
      ref
          .read(resumeProvider.notifier)
          .setSelectedResumes(_resumeIdsFromHistory(saved.items));
      _service.restoreConversationContext(
        saved.items,
        threadJob: saved.threadJob,
      );
      unawaited(_restorePreviewBytesFromStorage());
    } catch (_) {
      // Best-effort hydration; failures are silent so a flaky network never
      // blocks the chat from working.
    } finally {
      _hydrating = false;
    }
  }

  /// Debounced snapshot write for high-frequency UI changes such as streamed
  /// blocks, tool completion updates, and card-state transitions.
  void _schedulePersist() {
    if (_hydrating) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 450), _persistNow);
  }

  /// Immediate snapshot write for durable boundaries: user sends a prompt,
  /// a turn ends/fails/stops, or the user settles a card/action.
  void _persistNow() {
    _persistDebounce?.cancel();
    _persistDebounce = null;

    if (_hydrating) return;
    final uid = _uid;
    if (uid == null) return;

    final items = _itemsForHistory(state.items);
    if (items.isEmpty) return;

    // Fire-and-forget; UI doesn't wait on persistence.
    unawaited(
      _history.save(
        uid,
        state.conversationId,
        items: items,
        title: _deriveTitle(items, fallbackJob: state.threadJob),
        threadJob: state.threadJob,
      ),
    );
  }

  Future<void> _storePreviewBytes(AgentBlock block, List<int> bytes) async {
    final uid = _uid;
    if (uid == null || bytes.isEmpty) return;

    try {
      final path = await _resumesRepository.uploadConversationPreview(
        uid: uid,
        conversationId: state.conversationId,
        blockId: block.id,
        bytes: Uint8List.fromList(bytes),
      );

      switch (block) {
        case ProposedEditsBlock():
          block.previewStoragePath = path;
        case ResumeDraftBlock():
          block.previewStoragePath = path;
        default:
          return;
      }
    } catch (e) {
      debugPrint('chat preview upload failed: $e');
    }
  }

  Future<void> _restorePreviewBytesFromStorage() async {
    final uid = _uid;
    if (uid == null) return;

    var changed = false;

    for (final item in state.items) {
      if (item is! AgentTurn) continue;

      for (final block in item.blocks) {
        if (block is ProposedEditsBlock) {
          final path = block.previewStoragePath;
          if (block.previewBytes != null || path == null || path.isEmpty) {
            continue;
          }

          final bytes = await _resumesRepository.downloadConversationPreview(
            path,
          );
          if (bytes == null || bytes.isEmpty) continue;

          block.previewBytes = bytes;
          changed = true;
          continue;
        }

        if (block is ResumeDraftBlock) {
          final path = block.previewStoragePath;
          if (block.previewBytes != null || path == null || path.isEmpty) {
            continue;
          }

          final bytes = await _resumesRepository.downloadConversationPreview(
            path,
          );
          if (bytes == null || bytes.isEmpty) continue;

          block.previewBytes = bytes;
          changed = true;
        }
      }
    }

    if (!changed) return;
    state = state.copyWith(items: [...state.items]);
  }

  List<ChatItem> _itemsForHistory(List<ChatItem> items) {
    if (items.isEmpty) return const <ChatItem>[];

    final start = items.indexWhere((item) {
      if (item is! AgentTurn) return true;
      return !item.id.startsWith('turn-opener') &&
          item.id != 'turn-history-notice';
    });

    if (start < 0) return const <ChatItem>[];
    return items.sublist(start);
  }

  /// A short conversation label drawn from the first user message — what the
  /// history drawer shows for the row.
  /// A short conversation label for the history drawer.
  String _deriveTitle(List<ChatItem> items, {Job? fallbackJob}) {
    if (fallbackJob != null) {
      final title = fallbackJob.title.trim();
      final company = fallbackJob.company.trim();

      if (title.isNotEmpty && company.isNotEmpty) {
        return '$title · $company';
      }
      if (title.isNotEmpty) return title;
      if (company.isNotEmpty) return company;
    }

    for (final item in items) {
      if (item is UserMessage) {
        final text = item.text.trim();
        if (text.isEmpty) continue;
        return text.length <= 60 ? text : '${text.substring(0, 60).trim()}…';
      }
    }

    for (final item in items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is TextBlock) {
          final text = block.text.trim();
          if (text.isEmpty) continue;
          return text.length <= 60 ? text : '${text.substring(0, 60).trim()}…';
        }
      }
    }

    return 'Saved transcript';
  }

  /// Builds the first agent turn shown when the chat opens. Adapts to the
  /// optional [job] so a thread opened from a pipeline card lands on a
  /// contextual message + a relevant action proposal instead of the
  /// generic welcome.
  AgentTurn _buildOpener(Job? job) {
    if (job == null) {
      // No greeting bubble: the fresh-chat experience is the empty state
      // ("How can I help today?"). The opener stays as an empty turn purely so
      // the single-agent-item check that triggers the empty state keeps
      // working; it's filtered out of the rendered transcript.
      return AgentTurn(id: 'turn-opener', isStreaming: false);
    }

    final blocks = <AgentBlock>[];
    switch (job.category) {
      case JobCategory.ready:
        blocks.add(
          TextBlock(
            id: 'opener-text-${job.id}',
            text:
                "I drafted your application for ${job.title} at "
                "${job.company} — ${job.matchLabel.toLowerCase()}. "
                "${job.agentJustification}\n\n"
                "Ready to send it out?",
          ),
        );
        blocks.add(
          ActionProposalBlock(
            id: 'opener-action-${job.id}',
            icon: Icons.send_rounded,
            title: 'Prepare application for ${job.company}',
            description:
                'Tailored resume + outreach draft · user reviews before send',
            acceptLabel: 'Prepare draft',
            editLabel: 'Make changes',
            continuationPrompt:
                '''
      The user approved preparing an application for this matched job.

      Job:
      - job_id: ${job.id}
      - title: ${job.title}
      - company: ${job.company}
      - location: ${job.location}

      Continue the application workflow from here.
      Use tools for safe next steps, such as reading the resume, tailoring if needed, or drafting outreach.
      Do not call send_email. Sending still requires the email review UI and explicit confirmation token.
      ''',
          ),
        );
        break;
      case JobCategory.inputNeeded:
        blocks.add(
          TextBlock(
            id: 'opener-text-${job.id}',
            text: "Before I can draft this one — ${job.agentJustification}",
          ),
        );
        final missingSkill = job.missingSkills.isEmpty
            ? 'the missing context'
            : job.missingSkills.first;

        blocks.add(
          InputRequestBlock(
            id: 'opener-input-${job.id}',
            question: job.missingSkills.isEmpty
                ? 'Your answer'
                : 'Do you have ${job.missingSkills.first} experience?',
            suggestions: job.missingSkills.isEmpty
                ? const ['Tell me more', "I'm interested", 'Skip this one']
                : [
                    'Yes, ${job.missingSkills.first} experience',
                    "No, I haven't used ${job.missingSkills.first}",
                    'Tell me more',
                  ],
            continuationPrompt:
                '''
        The user answered the missing-information question for this pipeline job.

        Job:
        - job_id: ${job.id}
        - title: ${job.title}
        - company: ${job.company}
        - location: ${job.location}
        - match: ${job.matchLabel}
        - missing_skill: $missingSkill
        - agent_justification: ${job.agentJustification}

        Use the user's answer to decide whether this job can move forward.
        If the answer confirms relevant experience, continue the application workflow from here.
        If the answer says they do not have the experience, explain the gap briefly and suggest a safer next step.
        Do not call send_email. Sending still requires explicit user approval.
        ''',
          ),
        );
        break;
      case JobCategory.exploration:
        blocks.add(
          TextBlock(
            id: 'opener-text-${job.id}',
            text:
                "Worth considering: ${job.title} at ${job.company}. "
                "${job.agentJustification}",
          ),
        );
        blocks.add(
          ActionProposalBlock(
            id: 'opener-action-${job.id}',
            icon: Icons.auto_awesome_rounded,
            title: 'Draft a pitch for ${job.company}',
            description: 'I\'ll tailor your resume + draft outreach',
            acceptLabel: 'Draft it',
            editLabel: 'Pass on this',
            continuationPrompt:
                '''
      The user approved exploring this job and drafting a pitch.

      Job:
      - job_id: ${job.id}
      - title: ${job.title}
      - company: ${job.company}
      - location: ${job.location}

      Continue the workflow from here.
      First make sure the user's resume context is available.
      If tailoring is useful, propose resume edits and stop for the diff viewer.
      If outreach is the next safe step, draft the email.
      Do not call send_email. Sending still requires explicit user approval.
      ''',
          ),
        );
        break;
    }

    return AgentTurn(
      id: 'turn-opener-${job.id}',
      blocks: blocks,
      isStreaming: false,
    );
  }

  List<ChatItem> _restoreHistoryItems(List<ChatItem> saved) {
    if (saved.isEmpty) return [_buildOpener(null)];
    return [...saved];
  }

  /// Scopes the chat to [job] and replaces the opener with a contextual
  /// turn. Called by the pipeline when a card is tapped — the chatbot is
  /// the single thread for every agentic interaction.
  void openJobThread(Job job) {
    final currentThreadJob = state.threadJob;

    if (currentThreadJob != null && currentThreadJob.id == job.id) {
      return;
    }

    _persistNow();
    _service.resetConversation();
    _threadPipelineMarkedComplete = false;
    state = AgentChatState(
      items: [_buildOpener(job)],
      conversationId: _newConversationId(),
      threadJob: job,
    );
  }

  /// Starts a fresh, generic conversation. The previous one is already saved
  /// to history (if it had content), so nothing is lost — no confirm needed.
  void newConversation() {
    if (state.isStreaming) return;
    _persistNow();
    _service.resetConversation();
    _threadPipelineMarkedComplete = false;
    state = AgentChatState(
      items: [_buildOpener(null)],
      conversationId: _newConversationId(),
    );
  }

  /// Loads a saved conversation from history into the live transcript.
  Future<void> switchConversation(String conversationId) async {
    if (state.isStreaming) return;
    if (conversationId == state.conversationId) return;
    final uid = _uid;
    if (uid == null) return;
    _persistNow();
    _service.resetConversation();
    _threadPipelineMarkedComplete = false;
    final saved = await _history.loadConversation(uid, conversationId);
    state = AgentChatState(
      items: _restoreHistoryItems(saved.items),
      conversationId: conversationId,
      threadJob: saved.threadJob,
    );
    // Make sure subsequent IDs don't collide with loaded ones.
    _seq = saved.items.length + 1;
    // Continue the chat with the resume it was already using — sync the
    // attachment selection to that conversation's latest user message so
    // the "RESUME IN USE" card (and the next send) stay consistent.
    ref
        .read(resumeProvider.notifier)
        .setSelectedResumes(_resumeIdsFromHistory(saved.items));
    _service.restoreConversationContext(
      saved.items,
      threadJob: saved.threadJob,
    );
    unawaited(_restorePreviewBytesFromStorage());
  }

  /// Resume ids attached to the most recent [UserMessage] in a loaded
  /// transcript — empty if that conversation used no resume.
  Set<String> _resumeIdsFromHistory(List<ChatItem> items) {
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item is UserMessage) {
        return item.attachments.map((a) => a.id).toSet();
      }
    }
    return const {};
  }

  /// Permanently deletes a saved conversation. If it's the one on screen,
  /// drops to a fresh chat.
  Future<void> deleteConversation(String conversationId) async {
    final uid = _uid;
    if (uid == null) return;
    await _history.delete(uid, conversationId);
    if (conversationId == state.conversationId) {
      _service.resetConversation();
      _threadPipelineMarkedComplete = false;
      state = AgentChatState(
        items: [_buildOpener(null)],
        conversationId: _newConversationId(),
      );
    }
  }

  Future<void> renameConversation(String conversationId, String title) async {
    final uid = _uid;
    final cleanTitle = title.trim();
    if (uid == null || cleanTitle.isEmpty) return;
    await _history.rename(uid, conversationId, title: cleanTitle);
  }

  Future<void> setConversationPinned(
    String conversationId, {
    required bool pinned,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _history.setPinned(uid, conversationId, pinned: pinned);
  }

  String _nextId(String prefix) {
    _seq += 1;
    return '$prefix-$_seq';
  }

  void sendPrompt({
    required String prompt,
    List<ChatAttachment> attachments = const [],
  }) {
    final clean = prompt.trim();
    if (clean.isEmpty || state.isStreaming) return;

    final next = [
      ...state.items,
      UserMessage(id: _nextId('user'), text: clean, attachments: attachments),
    ];
    final turn = AgentTurn(id: _nextId('turn'));
    _activeTurn = turn;
    state = state.copyWith(items: [...next, turn], isStreaming: true);
    _persistNow();
    _runningTask.start(
      'Prompt is running…',
      // Stay quiet on the agent chat and the resume-flow surfaces — the user
      // can already see the work inline there. The pill reappears the moment
      // they navigate to a different surface.
      originRoutes: const {
        RouteNames.agentChat,
        RouteNames.resumes,
        RouteNames.resumePreview,
      },
    );

    _activeSub = _service
        .runPrompt(prompt: clean, attachments: attachments)
        .listen(
          _handleEvent,
          onDone: _finishTurn,
          onError: (Object e) => _failActiveTurn('Something went wrong. $e'),
        );
  }

  void _startContinuationPrompt(String prompt) {
    final clean = prompt.trim();
    if (clean.isEmpty) return;
    if (state.isStreaming) return;
    if (!_serviceReady) return;

    final turn = AgentTurn(id: _nextId('turn'));
    _activeTurn = turn;

    state = state.copyWith(items: [...state.items, turn], isStreaming: true);
    _persistNow();

    _activeSub = _service
        .runPrompt(prompt: clean, threaded: true)
        .listen(_handleEvent, onDone: _finishTurn);
  }

  void _continueAfterSavedResume(ProposedEditsBlock block) {
    final tailoredResumeId = block.savedResumeId;
    if (tailoredResumeId == null || tailoredResumeId.isEmpty) return;

    final sourceResumeId =
        block.resolvedResumeId ?? block.resumeId ?? 'unknown';
    final jobId = block.jobId ?? 'unknown';

    _startContinuationPrompt('''
The user approved the proposed resume edits and saved the tailored resume.

Approval result:
- source_resume_id: $sourceResumeId
- tailored_resume_id: $tailoredResumeId
- job_id: $jobId
- applied_count: ${block.appliedCount}
- skipped_count: ${block.skippedCount}

Continue the original application workflow from here without asking the user to repeat the task.
Use tailored_resume_id as the resume_id for the next steps.
Now offer outreach: call ask_user to ask whether they want you to draft recruiter outreach for this role, with
chips like ["Draft recruiter outreach", "Not yet", "Save for later"]. Only call draft_email after the user confirms.
If they confirm and recipient information is missing, call lookup_hiring_manager or ask_user.
Do not call send_email. Sending still requires explicit user approval.
''');
  }

  void _handleEvent(AgentEvent event) {
    final turn = _activeTurn;
    if (turn == null) return;
    switch (event) {
      case BlockAdded(:final block):
        turn.blocks.add(block);
        _reflectRunningTask(block);
        // A freshly-tailored edits card arrives already "applied" but with no
        // rendered PDF — render it now so its preview has bytes to show.
        if (block is ProposedEditsBlock &&
            block.state == ProposedEditsState.applied &&
            block.previewBytes == null) {
          unawaited(_autoRenderAppliedEdits(block));
        }
        // A from-scratch resume draft lands with no rendered PDF — render it
        // now so its preview has bytes to show.
        if (block is ResumeDraftBlock &&
            block.state == ResumeDraftState.rendering &&
            block.previewBytes == null) {
          unawaited(_autoRenderResumeDraft(block));
        }
      case ToolCallCompleted(
        :final blockId,
        :final summary,
        :final status,
        :final detail,
      ):
        for (final b in turn.blocks) {
          if (b is ToolCallBlock && b.id == blockId) {
            b.status = status;
            b.resultSummary = summary;
            if (detail != null) b.detail = detail;
            break;
          }
        }
      case JobsBlockUpdated(:final blockId, :final jobs):
        // match_jobs re-scored the rail search_jobs already rendered — swap in
        // the scored roles in place so the same roles don't appear twice.
        for (final b in turn.blocks) {
          if (b is JobsBlock && b.id == blockId) {
            b.jobs = jobs;
            break;
          }
        }
      case TurnCompleted():
        _finishTurn();
        return;
      case TurnFailed(:final message):
        _failActiveTurn(message);
        return;
    }
    // Mirror the event to the notifications inbox with tool-aware copy and
    // Accept/Make-changes affordances for proposals, so the user can settle
    // a block from the banner without opening the chat.
    _mirrorToInbox(event, turn);
    // Rebuild the outer items list so Riverpod sees a new reference.
    state = state.copyWith(items: [...state.items]);
    _schedulePersist();
  }

  /// Mirrors *actionable* agent events onto the inbox. Only events that
  /// genuinely need the user — `ask_user` (intercept) and Accept/Make-changes
  /// proposals — produce a notification. Plain tool completions are visible
  /// via the running pill's "Task completed" state; we deliberately don't
  /// pile "Open chat" rows on top of that.
  void _mirrorToInbox(AgentEvent event, AgentTurn turn) {
    final inbox = ref.read(notificationsProvider.notifier);
    switch (event) {
      case BlockAdded(:final block) when block is InputRequestBlock:
        inbox.add(
          AppNotification(
            id: 'n-input-${block.id}',
            kind: NotificationKind.intercept,
            title: 'Agent needs your input',
            body: block.question,
            timestamp: 'Just now',
            actionLabel: 'Answer',
            targetBlockId: block.id,
          ),
        );
      case BlockAdded(:final block) when block is ActionProposalBlock:
        inbox.add(
          AppNotification(
            id: 'n-prop-${block.id}',
            kind: NotificationKind.proposal,
            title: block.title,
            body: block.description,
            timestamp: 'Just now',
            actionLabel: block.acceptLabel,
            secondaryActionLabel: block.editLabel,
            targetBlockId: block.id,
          ),
        );
      case _:
        break;
    }
  }

  /// Mirrors the agent's progress onto the global running-task banner so it
  /// stays meaningful from any page: each tool call relabels the banner with
  /// that tool's UI label ("Tailoring resume…", "Searching jobs…"), and an
  /// `ask_user` pause flips it to a waiting state.
  void _reflectRunningTask(AgentBlock block) {
    if (block is ToolCallBlock) {
      _runningTask.update(block.label);
    } else if (block is InputRequestBlock) {
      _runningTask.update('Waiting for your input…');
    }
  }

  void _ensureNextStepChoiceAfterPipelineSave(AgentTurn turn) {
    if (_turnAlreadyNeedsUserChoice(turn)) return;
    if (!_turnSavedToPipeline(turn)) return;

    final rankedJobs = _latestRankedJobsForNextStep(turn);
    final input = InputRequestBlock(
      id: _nextId('input'),
      question: 'Saved to Pipeline. What should I do next?',
      suggestions: const [
        'Tailor for the strongest saved role',
        'Open Pipeline',
        'Search more roles',
      ],
      continuationPrompt: _pipelineSavedNextStepPrompt(rankedJobs),
    );

    turn.blocks.add(input);
    _mirrorToInbox(BlockAdded(input), turn);
  }

  bool _turnSavedToPipeline(AgentTurn turn) {
    for (final block in turn.blocks) {
      if (block is ToolCallBlock &&
          block.name == 'save_to_pipeline' &&
          block.status == ToolCallStatus.done) {
        return true;
      }
    }
    return false;
  }

  List<Job> _latestRankedJobsForNextStep(AgentTurn activeTurn) {
    for (final block in activeTurn.blocks.reversed) {
      if (block is JobsBlock && block.jobs.isNotEmpty) {
        return _rankJobsForNextStep(block.jobs);
      }
    }

    for (var i = state.items.length - 1; i >= 0; i--) {
      final item = state.items[i];
      if (item is! AgentTurn) continue;

      for (final block in item.blocks.reversed) {
        if (block is JobsBlock && block.jobs.isNotEmpty) {
          return _rankJobsForNextStep(block.jobs);
        }
      }
    }

    return const [];
  }

  String _pipelineSavedNextStepPrompt(List<Job> rankedJobs) {
    final topJobs = rankedJobs.take(5).toList(growable: false);

    if (topJobs.isEmpty) {
      return '''
The user just saved roles to Pipeline.

Use the user's answer to continue:
- If they choose "Tailor for the strongest saved role", ask which saved role they want to tailor for with 2-3 short suggestion chips.
- If they choose "Open Pipeline", briefly tell them Pipeline now contains the saved roles and they can open it from the Jobs tab.
- If they choose "Search more roles", call search_jobs and then continue the standard job-search sequence.
- Do not show numeric match scores in user-visible text.
- Do not call send_email.
- If the next action needs approval or missing information, call ask_user with 2-3 clear suggestion chips.
''';
    }

    final topRole = topJobs.first;
    final jobContext = topJobs.map(_jobContextLine).join('\n');

    return '''
The user just saved roles to Pipeline.

Saved/matched job context, sorted strongest-first:
$jobContext

Recommended strongest saved role:
- job_id: ${topRole.id}
- title: ${topRole.title}
- company: ${topRole.company}

Use the user's answer to continue:
- If they choose "Tailor for the strongest saved role", call read_resume if needed, then call tailor_resume for the recommended strongest saved role.
- If they choose "Open Pipeline", briefly tell them Pipeline now contains these saved roles and they can open it from the Jobs tab. Do not call tools for this.
- If they choose "Search more roles", call search_jobs with a related query based on the saved roles, then continue the standard job-search sequence.
- Do not show numeric match scores in user-visible text.
- Do not call draft_email until after a tailored resume is saved or the user directly asks for outreach.
- Do not call send_email.
- If the next action needs approval or missing information, call ask_user with 2-3 clear suggestion chips.
''';
  }

  void _ensureNextStepChoiceAfterJobResults(AgentTurn turn) {
    if (_turnAlreadyNeedsUserChoice(turn)) return;

    JobsBlock? latestJobsBlock;
    for (final block in turn.blocks.reversed) {
      if (block is JobsBlock && block.jobs.isNotEmpty) {
        latestJobsBlock = block;
        break;
      }
    }

    final jobsBlock = latestJobsBlock;
    if (jobsBlock == null) return;

    final rankedJobs = _rankJobsForNextStep(jobsBlock.jobs);
    if (rankedJobs.isEmpty) return;

    final input = InputRequestBlock(
      id: _nextId('input'),
      question: 'What should I do with these matches next?',
      suggestions: const [
        'Save top 3 to Pipeline',
        'Tailor for the top role',
        'Explore one role',
      ],
      continuationPrompt: _jobResultsNextStepPrompt(rankedJobs),
    );

    turn.blocks.add(input);
    _mirrorToInbox(BlockAdded(input), turn);
  }

  bool _turnAlreadyNeedsUserChoice(AgentTurn turn) {
    for (final block in turn.blocks) {
      if (block is InputRequestBlock &&
          block.state == InputRequestState.pending) {
        return true;
      }
      if (block is ActionProposalBlock && block.state == ActionState.pending) {
        return true;
      }
      if (block is ProposedEditsBlock &&
          block.state != ProposedEditsState.dismissed) {
        return true;
      }
      if (block is EmailDraftBlock &&
          block.status == EmailDraftStatus.reviewing) {
        return true;
      }
      if (block is ResumeDraftBlock && !block.isSaved) {
        return true;
      }
    }
    return false;
  }

  List<Job> _rankJobsForNextStep(List<Job> jobs) {
    final ranked = [...jobs];
    ranked.sort((a, b) {
      final categoryCompare = _jobCategoryPriority(
        a.category,
      ).compareTo(_jobCategoryPriority(b.category));
      if (categoryCompare != 0) return categoryCompare;

      // Internal-only sort signal. The UI still shows qualitative labels only.
      return b.matchScore.compareTo(a.matchScore);
    });
    return ranked;
  }

  int _jobCategoryPriority(JobCategory category) {
    return switch (category) {
      JobCategory.ready => 0,
      JobCategory.inputNeeded => 1,
      JobCategory.exploration => 2,
    };
  }

  String _jobResultsNextStepPrompt(List<Job> rankedJobs) {
    final topJobs = rankedJobs.take(5).toList(growable: false);
    final topThreeIds = topJobs.take(3).map((job) => job.id).join(', ');
    final topRole = topJobs.first;
    final jobContext = topJobs.map(_jobContextLine).join('\n');

    return '''
The user reviewed the matched job results and chose a next step.

Available matched jobs, already sorted strongest-first:
$jobContext

Recommended top role:
- job_id: ${topRole.id}
- title: ${topRole.title}
- company: ${topRole.company}

Top 3 job_ids:
$topThreeIds

Use the user's answer to continue:
- If they choose "Save top 3 to Pipeline", call save_to_pipeline for the top 3 job_ids.
- If they choose "Tailor for the top role", call tailor_resume for the recommended top role.
- If they choose "Explore one role", compare the strongest roles briefly and ask which one they want to continue with if needed.
- Do not show numeric match scores in user-visible text.
- Do not call send_email.
- If the next action needs approval or missing information, call ask_user with 2-3 clear suggestion chips.
''';
  }

  String _jobContextLine(Job job) {
    final reason = job.agentJustification.trim().isNotEmpty
        ? job.agentJustification.trim()
        : job.why.trim();
    final matched = job.skills.isEmpty ? 'none listed' : job.skills.join(', ');
    final gaps = job.missingSkills.isEmpty
        ? 'none listed'
        : job.missingSkills.join(', ');

    return '''
- job_id: ${job.id}
  title: ${job.title}
  company: ${job.company}
  location: ${job.location}
  match_label: ${job.matchLabel}
  reason: ${reason.isEmpty ? 'Not provided' : reason}
  matched_signals: $matched
  gaps: $gaps''';
  }

  void _finishTurn() {
    final turn = _activeTurn;
    if (turn != null && turn.status == AgentTurnStatus.streaming) {
      _ensureNextStepChoiceAfterPipelineSave(turn);
      _ensureNextStepChoiceAfterJobResults(turn);
      turn.status = AgentTurnStatus.done;
    }
    _activeTurn = null;
    _activeSub?.cancel();
    _activeSub = null;
    state = state.copyWith(items: [...state.items], isStreaming: false);
    _runningTask.complete();
    _persistNow();
  }

  void _failActiveTurn(String message) {
    final turn = _activeTurn;
    if (turn != null) {
      turn.status = AgentTurnStatus.failed;
      turn.errorMessage = message;
    }
    _activeTurn = null;
    _activeSub?.cancel();
    _activeSub = null;
    state = state.copyWith(items: [...state.items], isStreaming: false);
    _runningTask.fail();
    _persistNow();
  }

  void stopStreaming() {
    if (!state.isStreaming) return;
    final turn = _activeTurn;
    if (turn != null) turn.status = AgentTurnStatus.stopped;
    _activeTurn = null;
    _activeSub?.cancel();
    _activeSub = null;
    state = state.copyWith(items: [...state.items], isStreaming: false);
    _runningTask.dismiss();
    _persistNow();
  }

  /// Drops the most recent [AgentTurn] and re-runs the user prompt that
  /// triggered it. No-op if there is no preceding user message (e.g. only the
  /// opener turn is present) or if a stream is already in flight.
  void regenerateLastTurn() {
    if (state.isStreaming) return;
    final items = state.items;
    int lastTurnIdx = -1;
    for (var i = items.length - 1; i >= 0; i--) {
      if (items[i] is AgentTurn) {
        lastTurnIdx = i;
        break;
      }
    }
    if (lastTurnIdx <= 0) return;
    final priorUser = items[lastTurnIdx - 1];
    if (priorUser is! UserMessage) return;

    state = state.copyWith(items: items.sublist(0, lastTurnIdx - 1));
    sendPrompt(prompt: priorUser.text, attachments: priorUser.attachments);
  }

  void acceptProposal(String blockId) {
    final block = _findProposal(blockId);
    if (block == null) return;
    if (block.state != ActionState.pending) return;

    block.state = ActionState.accepted;
    ref.read(notificationsProvider.notifier).markReadByTargetBlock(blockId);
    state = state.copyWith(items: [...state.items]);
    _persistNow();

    _continueAfterAcceptedProposal(block);
  }

  void _continueAfterAcceptedProposal(ActionProposalBlock block) {
    if (!_serviceReady) return;

    final explicit = block.continuationPrompt?.trim();
    final prompt = (explicit != null && explicit.isNotEmpty)
        ? explicit
        : '''
  The user accepted this proposed agent action.

  Accepted proposal:
  - title: ${block.title}
  - description: ${block.description}
  - accepted_label: ${block.acceptLabel}

  Continue the original workflow from here without asking the user to repeat the task.
  Use tools for safe next steps.
  Pause again if you need missing user information or if the next action requires approval.
  Do not call send_email unless the app provides an explicit user-confirmation token or says the user tapped Send in the email review UI.
  ''';

    _startContinuationPrompt(prompt);
  }

  void _continueAfterInputAnswer(InputRequestBlock block, String answer) {
    if (!_serviceReady) return;

    final continuation = block.continuationPrompt?.trim();
    if (continuation == null || continuation.isEmpty) return;

    _startContinuationPrompt('''
  $continuation

  User answered:
  - question: ${block.question}
  - answer: $answer

  Continue the original workflow from here without asking the user to repeat the task.
  Use the user's answer as context for the next decision.
  Use tools for safe next steps.
  If tailoring is useful, propose resume edits and stop for the diff viewer.
  If outreach is the next safe step, draft the email only; do not send.
  Never call send_email unless the app provides an explicit user-confirmation token or says the user tapped Send.
  ''');
  }

  void dismissProposal(String blockId) {
    final block = _findProposal(blockId);
    if (block == null) return;
    block.state = ActionState.dismissed;
    ref.read(notificationsProvider.notifier).markReadByTargetBlock(blockId);
    state = state.copyWith(items: [...state.items]);
    _persistNow();
  }

  ActionProposalBlock? _findProposal(String blockId) {
    for (final item in state.items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is ActionProposalBlock && block.id == blockId) return block;
      }
    }
    return null;
  }

  /// Public lookup for a [ProposedEditsBlock] by id — used by the preview
  /// screen to read the rendered bytes / saved state reactively.
  ProposedEditsBlock? proposedEditsBlock(String blockId) =>
      _findProposedEdits(blockId);

  ProposedEditsBlock? _findProposedEdits(String blockId) {
    for (final item in state.items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is ProposedEditsBlock && block.id == blockId) return block;
      }
    }
    return null;
  }

  /// Settles an [EmailDraftBlock] once the user has saved it to Gmail Drafts
  /// from the review sheet. UI-only — the draft itself was already created by
  /// the review sheet; this just flips the card to its "saved" state so it
  /// can't be re-saved into a duplicate.
  void markEmailDraftSaved(String blockId, String? draftId) {
    final block = _findEmailDraft(blockId);
    if (block == null) return;
    if (block.status == EmailDraftStatus.saved) return;

    block.status = EmailDraftStatus.saved;
    block.savedDraftId = draftId;

    state = state.copyWith(items: [...state.items]);

    _markPipelineDraftProcessed(block);
    _persistNow();
  }

  void _markPipelineDraftProcessed(EmailDraftBlock block) {
    final jobId = (block.jobId ?? state.threadJob?.id)?.trim();
    if (jobId == null || jobId.isEmpty) return;

    final threadJobId = state.threadJob?.id;
    final isThreadJob = threadJobId != null && threadJobId == jobId;

    if (isThreadJob) {
      if (_threadPipelineMarkedComplete) return;
      _threadPipelineMarkedComplete = true;
    }

    unawaited(
      ref
          .read(jobsProvider.notifier)
          .markDraftedByJobId(jobId, resumeId: block.attachmentResumeId),
    );

    if (isThreadJob) {
      state = state.copyWith(clearThreadJob: true);
    }
  }

  EmailDraftBlock? _findEmailDraft(String blockId) {
    for (final item in state.items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is EmailDraftBlock && block.id == blockId) return block;
      }
    }
    return null;
  }

  /// Records the user's Accept/Reject choice for a single edit inside a
  /// [ProposedEditsBlock]. UI-only — nothing is applied to the resume until
  /// [applyProposedEdits] runs. No-ops once the card has settled.
  void setEditDecision(String blockId, int editIndex, EditDecision decision) {
    final block = _findProposedEdits(blockId);
    if (block == null) return;
    if (block.state != ProposedEditsState.reviewing) return;
    if (editIndex < 0 || editIndex >= block.decisions.length) return;
    if (block.decisions[editIndex] == decision) return;
    block.decisions[editIndex] = decision;
    state = state.copyWith(items: [...state.items]);
    _schedulePersist();
  }

  /// Renders the tailored PDF for the accepted edits and moves the card into a
  /// preview-ready state — **without** saving it to the resume library yet.
  /// The user previews the result and then either saves it
  /// ([savePreviewedResume]) or keeps editing by replying in the chat.
  Future<void> applyProposedEdits(String blockId) async {
    final block = _findProposedEdits(blockId);
    if (block == null) return;
    if (block.state != ProposedEditsState.reviewing) return;
    if (block.acceptedCount == 0) return;

    // Unit tests can override build() with a seeded transcript and skip the real
    // Firebase-backed service/orchestrator setup. In that case, preserve the old
    // state-only behavior so notifier/UI tests don't need Firebase initialization.
    if (!_serviceReady) {
      block.appliedCount = block.acceptedCount;
      block.skippedCount = 0;
      block.applyError = null;
      block.state = ProposedEditsState.applied;
      state = state.copyWith(items: [...state.items]);
      _persistNow();
      return;
    }

    final uid = _uid;
    if (uid == null) {
      block.applyError = 'Sign in to apply resume edits.';
      state = state.copyWith(items: [...state.items]);
      _persistNow();
      return;
    }

    block.state = ProposedEditsState.applying;
    block.applyError = null;
    state = state.copyWith(items: [...state.items]);
    _schedulePersist();

    final error = await _renderEditsPreview(block, uid);
    if (error == null) {
      block.state = ProposedEditsState.applied;
    } else {
      // Roll back to reviewing so the user can adjust and retry; the error
      // surfaces inline above the action buttons.
      block.state = ProposedEditsState.reviewing;
      block.applyError = error;
    }
    state = state.copyWith(items: [...state.items]);
    _persistNow();
  }

  /// Renders the tailored PDF for [block]'s accepted edits and stores the
  /// result on the block ([ProposedEditsBlock.previewBytes] et al.). Returns
  /// `null` on success or a short, user-facing message on failure. The caller
  /// owns the surrounding state transitions and the re-emit. Shared by the
  /// user-driven [applyProposedEdits] and the auto-applied tailor path
  /// ([_autoRenderAppliedEdits]).
  Future<String?> _renderEditsPreview(
    ProposedEditsBlock block,
    String uid,
  ) async {
    try {
      var resumeId = block.resumeId;
      if (resumeId == null || resumeId.isEmpty) {
        resumeId = await _orchestrator.latestManualResumeId(uid);
      }
      if (resumeId == null || resumeId.isEmpty) {
        throw const TailorOrchestratorException(
          'No source resume found — upload one first.',
        );
      }

      final rendered = await _orchestrator.renderEdits(
        uid: uid,
        resumeId: resumeId,
        acceptedEdits: block.acceptedEdits,
      );

      block.previewBytes = rendered.bytes;
      block.previewResume = rendered.resume;
      block.appliedCount = rendered.appliedCount;
      block.skippedCount = rendered.skippedCount;
      block.resolvedResumeId = resumeId;
      await _storePreviewBytes(block, rendered.bytes);
      return null;
    } catch (e) {
      return _shortError(e);
    }
  }

  /// Renders the preview PDF for an auto-applied tailor card the instant it
  /// lands in the chat. `tailor_resume` surfaces its edits as an already-
  /// `applied`, read-only diff (see `_proposedEditsBlockFromData`), but the
  /// card carries no rendered PDF — without this the preview screen would have
  /// no bytes and show "Preview unavailable". Keeps the card in [applying]
  /// (the "Rendering…" spinner) while the PDF builds so the preview button
  /// only appears once there are bytes behind it; on failure it falls back to
  /// [reviewing] so the user can retry via "Apply N edits".
  Future<void> _autoRenderAppliedEdits(ProposedEditsBlock block) async {
    if (!_serviceReady) return;
    if (block.previewBytes != null) return;
    if (block.acceptedEdits.isEmpty) return;

    final uid = _uid;
    if (uid == null) {
      // Guests have no resume library to render against; leave the read-only
      // diff in place without a preview.
      return;
    }

    block.state = ProposedEditsState.applying;
    block.applyError = null;
    state = state.copyWith(items: [...state.items]);
    _schedulePersist();

    final error = await _renderEditsPreview(block, uid);
    if (error == null) {
      block.state = ProposedEditsState.applied;
    } else {
      block.state = ProposedEditsState.reviewing;
      block.applyError = error;
    }
    state = state.copyWith(items: [...state.items]);
    _persistNow();
  }

  // -------------------------------------------------------------------------
  // From-scratch resume drafts (build_resume → ResumeDraftBlock)
  // -------------------------------------------------------------------------

  /// Public lookup for a [ResumeDraftBlock] by id — used by the draft preview
  /// screen to read the rendered bytes / saved state reactively.
  ResumeDraftBlock? resumeDraftBlock(String blockId) =>
      _findResumeDraft(blockId);

  ResumeDraftBlock? _findResumeDraft(String blockId) {
    for (final item in state.items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is ResumeDraftBlock && block.id == blockId) return block;
      }
    }
    return null;
  }

  /// Renders the preview PDF for a from-scratch resume the instant its draft
  /// card lands. `build_resume` carries the structured resume but no PDF — this
  /// renders one (a pure template render, no Firestore) so the preview screen
  /// has bytes to show. On failure it surfaces the error inline on the card.
  Future<void> _autoRenderResumeDraft(ResumeDraftBlock block) async {
    if (!_serviceReady) return;
    if (block.previewBytes != null) return;

    try {
      final bytes = await _orchestrator.renderResume(block.resume);
      block.previewBytes = bytes;
      await _storePreviewBytes(block, bytes);
      block.error = null;
    } catch (e) {
      block.error = _shortError(e);
    }
    block.state = ResumeDraftState.ready;
    state = state.copyWith(items: [...state.items]);
    _persistNow();
  }

  /// Persists a previewed from-scratch resume as a new `source: manual` base
  /// resume. No-op until the draft has rendered ([previewBytes] set) and only
  /// saves once. Seeds the byte cache so opening it from the list is instant.
  Future<void> saveBuiltResume(String blockId) async {
    final block = _findResumeDraft(blockId);
    if (block == null) return;
    if (block.previewBytes == null) return;
    if (block.isSaved) return;

    final uid = _uid;
    if (uid == null) {
      block.error = 'Sign in to save resumes.';
      state = state.copyWith(items: [...state.items]);
      _persistNow();
      return;
    }

    try {
      final saved = await _orchestrator.saveBuiltResume(
        uid: uid,
        bytes: block.previewBytes!,
        resume: block.resume,
        name: block.fileName,
      );
      block.savedResumeId = saved.id;
      block.error = null;
      ref
          .read(resumeProvider.notifier)
          .primeBytes(saved.id, block.previewBytes!);
      state = state.copyWith(items: [...state.items]);
      _persistNow();
    } catch (e) {
      block.error = _shortError(e);
      state = state.copyWith(items: [...state.items]);
      _persistNow();
    }
  }

  /// Persists the previewed tailored PDF to the resume library so it appears
  /// in the user's resumes / profile. No-op until the card has rendered a
  /// preview ([ProposedEditsState.applied]) and only saves once.
  Future<void> savePreviewedResume(String blockId) async {
    final block = _findProposedEdits(blockId);
    if (block == null) return;
    if (block.state != ProposedEditsState.applied) return;
    if (block.previewBytes == null || block.previewResume == null) return;
    if (block.isSaved) return;

    final uid = _uid;
    if (uid == null) {
      block.applyError = 'Sign in to save resumes.';
      state = state.copyWith(items: [...state.items]);
      _persistNow();
      return;
    }

    try {
      final saved = await _orchestrator.saveRenderedResume(
        uid: uid,
        bytes: block.previewBytes!,
        resume: block.previewResume!,
        parentResumeId: block.resolvedResumeId,
        jobId: block.jobId,
      );
      block.savedResumeId = saved.id;
      block.applyError = null;
      // Seed the bytes cache so opening it from the resume list is instant.
      ref
          .read(resumeProvider.notifier)
          .primeBytes(saved.id, block.previewBytes!);
      state = state.copyWith(items: [...state.items]);
      _persistNow();

      _continueAfterSavedResume(block);
    } catch (e) {
      block.applyError = _shortError(e);
      state = state.copyWith(items: [...state.items]);
      _persistNow();
    }
  }

  String _shortError(Object e) {
    final raw = e
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('TailorOrchestratorException: ', '')
        .trim();
    if (raw.isEmpty) return 'Something went wrong.';
    return raw.length > 120 ? '${raw.substring(0, 120)}…' : raw;
  }

  /// Dismisses a [ProposedEditsBlock] without applying anything.
  void dismissProposedEdits(String blockId) {
    final block = _findProposedEdits(blockId);
    if (block == null) return;
    if (block.state != ProposedEditsState.reviewing) return;
    block.state = ProposedEditsState.dismissed;
    state = state.copyWith(items: [...state.items]);
    _persistNow();
  }

  InputRequestBlock? _findInputRequest(String blockId) {
    for (final item in state.items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is InputRequestBlock && block.id == blockId) return block;
      }
    }
    return null;
  }

  /// Called when the user submits an answer to an inline `ask_user` prompt.
  void submitInputAnswer(String blockId, String answer) {
    final block = _findInputRequest(blockId);
    if (block == null) return;
    if (block.state == InputRequestState.answered) return;

    final trimmed = answer.trim();
    if (trimmed.isEmpty) return;

    block.state = InputRequestState.answered;
    block.answer = trimmed;
    ref.read(notificationsProvider.notifier).markReadByTargetBlock(blockId);
    state = state.copyWith(items: [...state.items]);
    _persistNow();

    final continuation = block.continuationPrompt?.trim();
    if (continuation != null && continuation.isNotEmpty) {
      _continueAfterInputAnswer(block, trimmed);
      return;
    }

    _service.provideUserAnswer(blockId, trimmed);
  }
}

final agentChatProvider = NotifierProvider<AgentChatNotifier, AgentChatState>(
  AgentChatNotifier.new,
);

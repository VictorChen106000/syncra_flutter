import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/resumes_repository.dart';
import '../../../data/models/job.dart';
import '../../auth/state/auth_notifier.dart';
import '../../notifications/state/notifications_notifier.dart';
import '../../resumes/services/resume_parser_service.dart';
import '../../resumes/services/resume_tailor_orchestrator.dart';
import '../../resumes/services/resume_tailor_service.dart';
import '../../resumes/state/resume_notifier.dart';
import '../models/agent_block.dart';
import '../models/chat_message.dart';
import '../models/conversation_summary.dart';
import '../services/agent_service.dart';
import '../services/anthropic_chat_service.dart';
import '../services/chat_history_repository.dart';
import '../tools/builtin_tools.dart';
import '../tools/tool_registry.dart';

/// The active [AgentService] for the app — Claude via the tool-use loop.
/// Requires an `ANTHROPIC_API_KEY`; without one the agent surfaces an error
/// at call time rather than falling back to scripted responses.
final agentServiceProvider = Provider<AgentService>((ref) {
  final registry = ToolRegistry();
  registerBuiltinTools(registry);
  return AnthropicChatService(registry: registry);
});

/// Persists the text-only transcript so chats survive app restarts. Scoped
/// to the signed-in user's Firestore subtree.
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
  late final AgentService _service;
  late final ChatHistoryRepository _history;
  late final ResumeTailorOrchestrator _orchestrator;
  StreamSubscription<AgentEvent>? _activeSub;
  AgentTurn? _activeTurn;
  int _seq = 0;
  bool _hydrating = false;
  bool _serviceReady = false;

  @override
  AgentChatState build() {
  _service = ref.watch(agentServiceProvider);
  _serviceReady = true;
  _history = ref.watch(chatHistoryRepositoryProvider);
    _orchestrator = ResumeTailorOrchestrator(
      resumesRepository: ResumesRepository(),
      jobsRepository: JobsRepository(),
      parser: ResumeParserService(),
      tailor: ResumeTailorService(),
    );
    ref.onDispose(() {
      _serviceReady = false;
      _activeSub?.cancel();
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
      final isUntouched = current.items.length == 1 &&
          current.items.first is AgentTurn &&
          current.threadJob == null;
      if (!isUntouched) return;
      final mostRecent = convos.first;
      final saved = await _history.load(uid, mostRecent.id);
      if (saved.isEmpty) return;
      state = AgentChatState(
        items: [_buildOpener(null), ...saved],
        conversationId: mostRecent.id,
      );
      // Make sure subsequent IDs don't collide with hydrated ones.
      _seq = saved.length + 1;
    } catch (_) {
      // Best-effort hydration; failures are silent so a flaky network never
      // blocks the chat from working.
    } finally {
      _hydrating = false;
    }
  }

  void _persist() {
    if (_hydrating) return;
    final uid = _uid;
    if (uid == null) return;
    // Drop the opener turn from the persisted payload — it's reconstructed
    // locally on every cold start and writing it would just bloat the doc.
    final items = state.items.length > 1
        ? state.items.sublist(1)
        : const <ChatItem>[];
    if (items.isEmpty) return;
    // Fire-and-forget; UI doesn't wait on persistence.
    unawaited(_history.save(
      uid,
      state.conversationId,
      items: items,
      title: _deriveTitle(items),
    ));
  }

  /// A short conversation label drawn from the first user message — what the
  /// history drawer shows for the row.
  String _deriveTitle(List<ChatItem> items) {
    for (final item in items) {
      if (item is UserMessage) {
        final text = item.text.trim();
        if (text.isEmpty) continue;
        return text.length <= 60 ? text : '${text.substring(0, 60).trim()}…';
      }
    }
    return 'New chat';
  }

  /// Builds the first agent turn shown when the chat opens. Adapts to the
  /// optional [job] so a thread opened from a pipeline card lands on a
  /// contextual message + a relevant action proposal instead of the
  /// generic welcome.
  AgentTurn _buildOpener(Job? job) {
    if (job == null) {
      return AgentTurn(
        id: 'turn-opener',
        blocks: [
          TextBlock(
            id: 'opener-text',
            text: AppStrings.chatInitialMessage,
          ),
        ],
        isStreaming: false,
      );
    }

    final blocks = <AgentBlock>[];
    switch (job.category) {
      case JobCategory.ready:
        blocks.add(TextBlock(
          id: 'opener-text-${job.id}',
          text: "I drafted your application for ${job.title} at "
              "${job.company} — match score ${job.matchScore}%. "
              "${job.agentJustification}\n\n"
              "Ready to send it out?",
        ));
        blocks.add(ActionProposalBlock(
          id: 'opener-action-${job.id}',
          icon: Icons.send_rounded,
          title: 'Send to ${job.company}',
          description: 'Tailored resume + cover letter · sends via Gmail',
          acceptLabel: 'Send now',
          editLabel: 'Edit draft',
        ));
        break;
      case JobCategory.inputNeeded:
        blocks.add(TextBlock(
          id: 'opener-text-${job.id}',
          text: "Before I can draft this one — ${job.agentJustification}",
        ));
        blocks.add(InputRequestBlock(
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
        ));
        break;
      case JobCategory.exploration:
        blocks.add(TextBlock(
          id: 'opener-text-${job.id}',
          text: "Worth considering: ${job.title} at ${job.company}. "
              "${job.agentJustification}",
        ));
        blocks.add(ActionProposalBlock(
          id: 'opener-action-${job.id}',
          icon: Icons.auto_awesome_rounded,
          title: 'Draft a pitch for ${job.company}',
          description: 'I\'ll tailor your resume + draft outreach',
          acceptLabel: 'Draft it',
          editLabel: 'Pass on this',
        ));
        break;
    }

    return AgentTurn(
      id: 'turn-opener-${job.id}',
      blocks: blocks,
      isStreaming: false,
    );
  }

  /// Scopes the chat to [job] and replaces the opener with a contextual
  /// turn. Called by the pipeline when a card is tapped — the chatbot is
  /// the single thread for every agentic interaction.
  void openJobThread(Job job) {
    _service.resetConversation();
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
    _service.resetConversation();
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
    _service.resetConversation();
    final saved = await _history.load(uid, conversationId);
    state = AgentChatState(
      items: [_buildOpener(null), ...saved],
      conversationId: conversationId,
    );
    // Make sure subsequent IDs don't collide with loaded ones.
    _seq = saved.length + 1;
    // Continue the chat with the resume it was already using — sync the
    // attachment selection to that conversation's latest user message so
    // the "RESUME IN USE" card (and the next send) stay consistent.
    ref
        .read(resumeProvider.notifier)
        .setSelectedResumes(_resumeIdsFromHistory(saved));
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
      newConversation();
    }
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
      UserMessage(
        id: _nextId('user'),
        text: clean,
        attachments: attachments,
      ),
    ];
    final turn = AgentTurn(id: _nextId('turn'));
    _activeTurn = turn;
    state = state.copyWith(
      items: [...next, turn],
      isStreaming: true,
    );

    _activeSub = _service
        .runPrompt(prompt: clean, attachments: attachments)
        .listen(
          _handleEvent,
          onDone: _finishTurn,
          onError: (Object e) =>
              _failActiveTurn('Something went wrong. $e'),
        );
  }

  void _startContinuationPrompt(String prompt) {
  final clean = prompt.trim();
  if (clean.isEmpty) return;
  if (state.isStreaming) return;
  if (!_serviceReady) return;

  final turn = AgentTurn(id: _nextId('turn'));
  _activeTurn = turn;

  state = state.copyWith(
    items: [...state.items, turn],
    isStreaming: true,
  );

  _activeSub = _service
      .runPrompt(
        prompt: clean,
        threaded: true,
      )
      .listen(_handleEvent, onDone: _finishTurn);
}

void _continueAfterSavedResume(ProposedEditsBlock block) {
  final tailoredResumeId = block.savedResumeId;
  if (tailoredResumeId == null || tailoredResumeId.isEmpty) return;

  final sourceResumeId = block.resolvedResumeId ?? block.resumeId ?? 'unknown';
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
If the next safe step is outreach, call draft_email.
If recipient information is missing, call lookup_hiring_manager or ask_user.
Do not call send_email. Sending still requires explicit user approval.
''');
}

  void _handleEvent(AgentEvent event) {
    final turn = _activeTurn;
    if (turn == null) return;
    switch (event) {
      case BlockAdded(:final block):
        turn.blocks.add(block);
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
      case TurnCompleted():
        _finishTurn();
        return;
      case TurnFailed(:final message):
        _failActiveTurn(message);
        return;
    }
    // Mirror the event to the notifications inbox. NotificationsNotifier
    // decides which events warrant an entry (ask_user, completed tools, …).
    ref.read(notificationsProvider.notifier).onAgentEvent(event);
    // Rebuild the outer items list so Riverpod sees a new reference.
    state = state.copyWith(items: [...state.items]);
  }

  void _finishTurn() {
    final turn = _activeTurn;
    if (turn != null && turn.status == AgentTurnStatus.streaming) {
      turn.status = AgentTurnStatus.done;
    }
    _activeTurn = null;
    _activeSub?.cancel();
    _activeSub = null;
    state = state.copyWith(items: [...state.items], isStreaming: false);
    _persist();
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
    _persist();
  }

  void stopStreaming() {
    if (!state.isStreaming) return;
    final turn = _activeTurn;
    if (turn != null) turn.status = AgentTurnStatus.stopped;
    _activeTurn = null;
    _activeSub?.cancel();
    _activeSub = null;
    state = state.copyWith(items: [...state.items], isStreaming: false);
    _persist();
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
    sendPrompt(
      prompt: priorUser.text,
      attachments: priorUser.attachments,
    );
  }

  void acceptProposal(String blockId) {
    final block = _findProposal(blockId);
    if (block == null) return;
    block.state = ActionState.accepted;
    state = state.copyWith(items: [...state.items]);
  }

  void dismissProposal(String blockId) {
    final block = _findProposal(blockId);
    if (block == null) return;
    block.state = ActionState.dismissed;
    state = state.copyWith(items: [...state.items]);
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
      return;
    }

    final uid = _uid;
    if (uid == null) {
      block.applyError = 'Sign in to apply resume edits.';
      state = state.copyWith(items: [...state.items]);
      return;
    }

    block.state = ProposedEditsState.applying;
    block.applyError = null;
    state = state.copyWith(items: [...state.items]);

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
      block.state = ProposedEditsState.applied;
      state = state.copyWith(items: [...state.items]);
    } catch (e) {
      // Roll back to reviewing so the user can adjust and retry; the error
      // surfaces inline above the action buttons.
      block.state = ProposedEditsState.reviewing;
      block.applyError = _shortError(e);
      state = state.copyWith(items: [...state.items]);
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
      ref.read(resumeProvider.notifier).primeBytes(saved.id, block.previewBytes!);
      state = state.copyWith(items: [...state.items]);

      _continueAfterSavedResume(block);
    } catch (e) {
      block.applyError = _shortError(e);
      state = state.copyWith(items: [...state.items]);
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
    state = state.copyWith(items: [...state.items]);
    _service.provideUserAnswer(blockId, trimmed);
  }
}

final agentChatProvider =
    NotifierProvider<AgentChatNotifier, AgentChatState>(AgentChatNotifier.new);

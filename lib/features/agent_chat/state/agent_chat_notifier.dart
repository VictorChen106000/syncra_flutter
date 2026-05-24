import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/job.dart';
import '../../../fixtures/mock_agent_service.dart';
import '../../../shared/state/running_task_notifier.dart';
import '../../auth/state/auth_notifier.dart';
import '../../notifications/models/app_notification.dart';
import '../../notifications/state/notifications_notifier.dart';
import '../models/agent_block.dart';
import '../models/chat_message.dart';
import '../models/conversation_summary.dart';
import '../services/agent_service.dart';
import '../services/anthropic_chat_service.dart';
import '../services/chat_history_repository.dart';
import '../tools/builtin_tools.dart';
import '../tools/tool_registry.dart';

/// The active [AgentService] for the app. Backed by Claude when an
/// `ANTHROPIC_API_KEY` is configured, otherwise a deterministic mock.
final agentServiceProvider = Provider<AgentService>((ref) {
  final registry = ToolRegistry();
  registerBuiltinTools(registry);
  final anthropic = AnthropicChatService(registry: registry);
  return anthropic.hasApiKey ? anthropic : MockAgentService();
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
  StreamSubscription<AgentEvent>? _activeSub;
  AgentTurn? _activeTurn;
  int _seq = 0;
  bool _hydrating = false;

  @override
  AgentChatState build() {
    _service = ref.watch(agentServiceProvider);
    _history = ref.watch(chatHistoryRepositoryProvider);
    ref.onDispose(() {
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
    _runningTask.start(
      'Prompt is running…',
      // Stay quiet on the agent chat and the resume-flow surfaces — the user
      // can already see the work inline there. The pill reappears the moment
      // they navigate to a different surface.
      originRoutes: const {
        RouteNames.agentChat,
        RouteNames.tailor,
        RouteNames.review,
        RouteNames.submitted,
        RouteNames.resumes,
        RouteNames.resumePreview,
      },
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

  void _handleEvent(AgentEvent event) {
    final turn = _activeTurn;
    if (turn == null) return;
    switch (event) {
      case BlockAdded(:final block):
        turn.blocks.add(block);
        _reflectRunningTask(block);
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
    // Mirror the event to the notifications inbox with tool-aware copy and
    // Accept/Make-changes affordances for proposals, so the user can settle
    // a block from the banner without opening the chat.
    _mirrorToInbox(event, turn);
    // Rebuild the outer items list so Riverpod sees a new reference.
    state = state.copyWith(items: [...state.items]);
  }

  /// Maps the latest agent event onto an inbox entry. Producers without
  /// tool-level context (e.g. the passive morning-brief loop) fall back to
  /// the notifier's generic [NotificationsNotifier.onAgentEvent]; the chat
  /// owns its own mirror so it can emit proposals + per-tool labels.
  void _mirrorToInbox(AgentEvent event, AgentTurn turn) {
    final inbox = ref.read(notificationsProvider.notifier);
    switch (event) {
      case BlockAdded(:final block) when block is InputRequestBlock:
        inbox.add(AppNotification(
          id: 'n-input-${block.id}',
          kind: NotificationKind.intercept,
          title: 'Agent needs your input',
          body: block.question,
          timestamp: 'Just now',
          actionLabel: 'Answer',
          targetBlockId: block.id,
        ));
      case BlockAdded(:final block) when block is ActionProposalBlock:
        inbox.add(AppNotification(
          id: 'n-prop-${block.id}',
          kind: NotificationKind.proposal,
          title: block.title,
          body: block.description,
          timestamp: 'Just now',
          actionLabel: block.acceptLabel,
          secondaryActionLabel: block.editLabel,
          targetBlockId: block.id,
        ));
      case ToolCallCompleted(:final blockId, :final summary, :final status)
          when status == ToolCallStatus.done && summary.isNotEmpty:
        final tool = _toolBlockInTurn(turn, blockId);
        final (title, body) = _toolCompletionCopy(tool, summary);
        inbox.add(AppNotification(
          id: 'n-tool-$blockId',
          kind: NotificationKind.drafted,
          title: title,
          body: body,
          timestamp: 'Just now',
          actionLabel: 'Open chat',
        ));
      case _:
        break;
    }
  }

  ToolCallBlock? _toolBlockInTurn(AgentTurn turn, String blockId) {
    for (final b in turn.blocks) {
      if (b is ToolCallBlock && b.id == blockId) return b;
    }
    return null;
  }

  /// Inbox copy for a completed tool call. Tailors the resume-tailor flow
  /// explicitly per product ask; everything else uses the tool's own UI label
  /// as the title so an entry like "Searching jobs" reads cleanly.
  (String title, String body) _toolCompletionCopy(
    ToolCallBlock? tool,
    String summary,
  ) {
    if (tool == null) return ('Agent finished a task', summary);
    return switch (tool.name) {
      'tailor_resume' => ('Tailored resume ready', summary),
      'apply_resume_edits' => ('Tailored resume saved', summary),
      'draft_email' => ('Draft email ready', summary),
      'send_email' => ('Email sent', summary),
      _ => (tool.label.replaceAll('…', '').trim(), summary),
    };
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

  void _finishTurn() {
    final turn = _activeTurn;
    if (turn != null && turn.status == AgentTurnStatus.streaming) {
      turn.status = AgentTurnStatus.done;
    }
    _activeTurn = null;
    _activeSub?.cancel();
    _activeSub = null;
    state = state.copyWith(items: [...state.items], isStreaming: false);
    _runningTask.complete();
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
    _runningTask.fail();
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
    _runningTask.dismiss();
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
    ref
        .read(notificationsProvider.notifier)
        .markReadByTargetBlock(blockId);
    state = state.copyWith(items: [...state.items]);
  }

  void dismissProposal(String blockId) {
    final block = _findProposal(blockId);
    if (block == null) return;
    block.state = ActionState.dismissed;
    ref
        .read(notificationsProvider.notifier)
        .markReadByTargetBlock(blockId);
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

  /// Applies the accepted edits in a [ProposedEditsBlock] and settles the card.
  ///
  /// This is the handoff point to the resume-apply logic: the accepted edits
  /// (with the block's [ProposedEditsBlock.resumeId] / [ProposedEditsBlock.jobId])
  /// are everything that layer needs to mutate the resume and re-render it.
  /// Wiring that call is task #2's sibling; for now we settle the UI so the
  /// diff viewer can be built and demoed against it.
  void applyProposedEdits(String blockId) {
    final block = _findProposedEdits(blockId);
    if (block == null) return;
    if (block.state != ProposedEditsState.reviewing) return;
    if (block.acceptedCount == 0) return;
    // ignore: unused_local_variable
    final accepted = block.acceptedEdits; // TODO: hand off to resume-apply logic.
    block.state = ProposedEditsState.applied;
    state = state.copyWith(items: [...state.items]);
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
    ref
        .read(notificationsProvider.notifier)
        .markReadByTargetBlock(blockId);
    state = state.copyWith(items: [...state.items]);
    _service.provideUserAnswer(blockId, trimmed);
  }
}

final agentChatProvider =
    NotifierProvider<AgentChatNotifier, AgentChatState>(AgentChatNotifier.new);

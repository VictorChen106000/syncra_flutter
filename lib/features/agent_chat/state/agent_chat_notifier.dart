import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../data/models/job.dart';
import '../../../fixtures/mock_agent_service.dart';
import '../../auth/state/auth_notifier.dart';
import '../../notifications/state/notifications_notifier.dart';
import '../models/agent_block.dart';
import '../models/chat_message.dart';
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

@immutable
class AgentChatState {
  const AgentChatState({
    required this.items,
    this.isStreaming = false,
    this.threadJob,
  });

  final List<ChatItem> items;
  final bool isStreaming;

  /// When set, the chat is scoped to a single job — surfaces a context chip
  /// in the header and gates the opening message to that role.
  final Job? threadJob;

  AgentChatState copyWith({
    List<ChatItem>? items,
    bool? isStreaming,
    Job? threadJob,
    bool clearThreadJob = false,
  }) {
    return AgentChatState(
      items: items ?? this.items,
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

    // Hydrate from Firestore in the background. We start from the default
    // opener and replace once the load completes, *iff* the user hasn't
    // already started a new conversation in the meantime.
    _hydrateFromFirestore();

    return AgentChatState(
      items: [_buildOpener(null)],
    );
  }

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
      final saved = await _history.load(uid);
      if (saved.isEmpty) return;
      // Only apply hydration if the user hasn't already typed or opened a
      // thread since build() — otherwise we'd clobber their in-progress work.
      final current = state;
      final isUntouched = current.items.length == 1 &&
          current.items.first is AgentTurn &&
          current.threadJob == null;
      if (!isUntouched) return;
      state = AgentChatState(
        items: [_buildOpener(null), ...saved],
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
    // Fire-and-forget; UI doesn't wait on persistence.
    unawaited(_history.save(uid, items));
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
    state = AgentChatState(
      items: [_buildOpener(job)],
      threadJob: job,
    );
  }

  /// Closes the current job thread and resets to the generic welcome. Also
  /// wipes the persisted history so a "New chat" tap genuinely starts over.
  void clearThread() {
    state = AgentChatState(
      items: [_buildOpener(null)],
    );
    final uid = _uid;
    if (uid != null) unawaited(_history.clear(uid));
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

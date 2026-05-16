import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_strings.dart';
import '../models/agent_block.dart';
import '../models/chat_message.dart';
import '../services/agent_service.dart';

class AgentChatController extends ChangeNotifier {
  AgentChatController({required AgentService service})
      : _service = service,
        _items = [
          AgentTurn(
            id: 'turn-initial',
            blocks: [
              TextBlock(
                id: 'initial-text',
                text: AppStrings.chatInitialMessage,
              ),
            ],
            isStreaming: false,
          ),
        ];

  final AgentService _service;
  final List<ChatItem> _items;
  StreamSubscription<AgentEvent>? _activeSub;
  AgentTurn? _activeTurn;
  int _seq = 0;

  List<ChatItem> get items => List.unmodifiable(_items);
  bool get isStreaming => _activeTurn != null;

  String _nextId(String prefix) {
    _seq += 1;
    return '$prefix-$_seq';
  }

  void sendPrompt({
    required String prompt,
    List<ChatAttachment> attachments = const [],
  }) {
    final clean = prompt.trim();
    if (clean.isEmpty || isStreaming) return;

    _items.add(
      UserMessage(
        id: _nextId('user'),
        text: clean,
        attachments: attachments,
      ),
    );
    final turn = AgentTurn(id: _nextId('turn'));
    _activeTurn = turn;
    _items.add(turn);
    notifyListeners();

    _activeSub = _service
        .runPrompt(prompt: clean, attachments: attachments)
        .listen(_handleEvent, onDone: _finishTurn);
  }

  void _handleEvent(AgentEvent event) {
    final turn = _activeTurn;
    if (turn == null) return;
    switch (event) {
      case BlockAdded(:final block):
        turn.blocks.add(block);
      case ToolCallCompleted(:final blockId, :final summary, :final status):
        for (final b in turn.blocks) {
          if (b is ToolCallBlock && b.id == blockId) {
            b.status = status;
            b.resultSummary = summary;
            break;
          }
        }
      case TurnCompleted():
        _finishTurn();
        return;
    }
    notifyListeners();
  }

  void _finishTurn() {
    _activeTurn?.isStreaming = false;
    _activeTurn = null;
    _activeSub?.cancel();
    _activeSub = null;
    notifyListeners();
  }

  void acceptProposal(String blockId) {
    final block = _findProposal(blockId);
    if (block == null) return;
    block.state = ActionState.accepted;
    notifyListeners();
  }

  void dismissProposal(String blockId) {
    final block = _findProposal(blockId);
    if (block == null) return;
    block.state = ActionState.dismissed;
    notifyListeners();
  }

  ActionProposalBlock? _findProposal(String blockId) {
    for (final item in _items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is ActionProposalBlock && block.id == blockId) return block;
      }
    }
    return null;
  }

  InputRequestBlock? _findInputRequest(String blockId) {
    for (final item in _items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is InputRequestBlock && block.id == blockId) return block;
      }
    }
    return null;
  }

  /// Called when the user submits an answer to an inline `ask_user` prompt.
  /// Resolves the paused agent loop with the typed answer.
  void submitInputAnswer(String blockId, String answer) {
    final block = _findInputRequest(blockId);
    if (block == null) return;
    if (block.state == InputRequestState.answered) return;
    final trimmed = answer.trim();
    if (trimmed.isEmpty) return;
    block.state = InputRequestState.answered;
    block.answer = trimmed;
    notifyListeners();
    _service.provideUserAnswer(blockId, trimmed);
  }

  @override
  void dispose() {
    _activeSub?.cancel();
    super.dispose();
  }
}

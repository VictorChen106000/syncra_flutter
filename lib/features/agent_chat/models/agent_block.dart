import 'package:flutter/material.dart';

/// One unit of agent output inside an [AgentTurn].
///
/// A turn is a sequence of blocks (thinking → tool calls → text → proposals).
/// New block types can be added without touching the controller — just
/// implement a render branch in `agent_turn_view.dart`.
sealed class AgentBlock {
  AgentBlock({required this.id});
  final String id;
}

/// The agent's internal reasoning. Shown collapsed by default, like Claude's
/// "Thinking" disclosure.
class ThinkingBlock extends AgentBlock {
  ThinkingBlock({required super.id, required this.content});
  final String content;
}

enum ToolCallStatus { running, done, failed }

/// A tool the agent invoked. While [status] is [ToolCallStatus.running] the
/// UI shows a spinner; once [status] flips to [ToolCallStatus.done] the
/// [resultSummary] is rendered as a one-line outcome.
class ToolCallBlock extends AgentBlock {
  ToolCallBlock({
    required super.id,
    required this.name,
    required this.label,
    required this.icon,
    this.status = ToolCallStatus.running,
    this.resultSummary,
  });

  final String name;
  final String label;
  final IconData icon;
  ToolCallStatus status;
  String? resultSummary;
}

/// Plain prose from the agent (markdown-free for now).
class TextBlock extends AgentBlock {
  TextBlock({required super.id, required this.text});
  final String text;
}

enum InputRequestState { pending, answered }

/// The agent paused mid-loop because it needs information only the user can
/// provide. Renders as an inline text field (plus optional suggestion chips)
/// inside the chat transcript. Once the user submits an answer, the agent
/// loop resumes with that answer as the `ask_user` tool result.
class InputRequestBlock extends AgentBlock {
  InputRequestBlock({
    required super.id,
    required this.question,
    this.suggestions = const [],
    this.state = InputRequestState.pending,
    this.answer,
  });

  final String question;
  final List<String> suggestions;
  InputRequestState state;
  String? answer;
}

enum ActionState { pending, accepted, dismissed }

/// A concrete action the agent wants to take. Surfaces Accept / Make changes
/// buttons so the user stays in control.
class ActionProposalBlock extends AgentBlock {
  ActionProposalBlock({
    required super.id,
    required this.icon,
    required this.title,
    required this.description,
    this.acceptLabel = 'Accept',
    this.editLabel = 'Make changes',
    this.state = ActionState.pending,
  });

  final IconData icon;
  final String title;
  final String description;
  final String acceptLabel;
  final String editLabel;
  ActionState state;
}

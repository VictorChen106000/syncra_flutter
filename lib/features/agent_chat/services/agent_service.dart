import '../models/agent_block.dart';
import '../models/chat_message.dart';

/// An event emitted while the agent is responding.
///
/// The service streams these so the controller can incrementally update the
/// current turn (append a new block, then later mark a tool call done).
sealed class AgentEvent {
  const AgentEvent();
}

/// A new block should be appended to the current turn.
class BlockAdded extends AgentEvent {
  const BlockAdded(this.block);
  final AgentBlock block;
}

/// A tool call already in the turn finished. Look it up by [blockId] and
/// flip its status / fill in the [resultSummary].
class ToolCallCompleted extends AgentEvent {
  const ToolCallCompleted({
    required this.blockId,
    required this.summary,
    this.status = ToolCallStatus.done,
  });

  final String blockId;
  final String summary;
  final ToolCallStatus status;
}

/// The streaming response is done.
class TurnCompleted extends AgentEvent {
  const TurnCompleted();
}

/// Boundary the chat controller talks to. Swap [MockAgentService] for a
/// real backend-backed impl without touching the controller or UI.
abstract class AgentService {
  Stream<AgentEvent> runPrompt({
    required String prompt,
    List<ChatAttachment> attachments = const [],
  });

  /// Called by the controller when the user submits an answer to an
  /// `ask_user` prompt. Implementations that don't support tool use can
  /// no-op (default).
  void provideUserAnswer(String blockId, String answer) {}
}

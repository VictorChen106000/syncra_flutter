import '../../../data/models/job.dart';
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
/// flip its status / fill in the [resultSummary] and [detail].
class ToolCallCompleted extends AgentEvent {
  const ToolCallCompleted({
    required this.blockId,
    required this.summary,
    this.status = ToolCallStatus.done,
    this.detail,
  });

  final String blockId;
  final String summary;
  final ToolCallStatus status;

  /// Full inputs + outputs for the tool-call drill-down. Null leaves whatever
  /// [detail] the block was constructed with (its input args) untouched.
  final String? detail;
}

/// An existing [JobsBlock] should have its jobs replaced in place. Emitted when
/// `match_jobs` re-scores the roles a prior `search_jobs` already rendered, so
/// the rail updates with accurate match badges instead of a second, duplicate
/// rail being appended below it.
class JobsBlockUpdated extends AgentEvent {
  const JobsBlockUpdated({required this.blockId, required this.jobs});
  final String blockId;
  final List<Job> jobs;
}

/// The streaming response is done.
class TurnCompleted extends AgentEvent {
  const TurnCompleted();
}

/// The service couldn't complete the turn (network, API error, timeout). The
/// notifier flips the active turn into [AgentTurnStatus.failed] and surfaces
/// [message] in the retry banner.
class TurnFailed extends AgentEvent {
  const TurnFailed(this.message);
  final String message;
}

/// Boundary the chat controller talks to. Implemented by `AnthropicChatService`;
/// any alternate impl can be swapped in without touching the controller or UI.
abstract class AgentService {
  Stream<AgentEvent> runPrompt({
    required String prompt,
    List<ChatAttachment> attachments = const [],
    bool threaded = true,
  });

  /// Called by the controller when the user submits an answer to an
  /// `ask_user` prompt. Implementations that don't support tool use can
  /// no-op (default).
  bool provideUserAnswer(String blockId, String answer) => false;

  /// Restores a compact model-readable context from a saved chat UI snapshot.
  ///
  /// This does not replay exact Anthropic tool-use messages. It gives the
  /// next prompt enough context to continue naturally after an app restart or
  /// history switch.
  void restoreConversationContext(List<ChatItem> items, {Job? threadJob}) {}

  /// Clears any retained conversation history so the next [runPrompt] starts
  /// a fresh context. Called when the user starts a new chat or switches job
  /// threads. Stateless implementations can no-op.
  void resetConversation() {}

  /// Sets a per-turn directive describing the user's active autonomy level
  /// (Assist / Auto-draft / Autopilot). Injected as a secondary system block
  /// that overrides the static prompt's default chaining/gate behavior. The
  /// controller sets this before each [runPrompt]. No-op by default.
  void setAutonomyDirective(String directive) {}
}

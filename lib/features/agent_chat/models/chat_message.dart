import 'agent_block.dart';

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

/// A single entry in the chat transcript. Either a [UserMessage] (what the
/// user typed) or an [AgentTurn] (the agent's streamed response composed of
/// one or more [AgentBlock]s).
sealed class ChatItem {
  ChatItem({required this.id});
  final String id;
}

class UserMessage extends ChatItem {
  UserMessage({
    required super.id,
    required this.text,
    this.attachments = const [],
  });

  final String text;
  final List<ChatAttachment> attachments;
}

enum AgentTurnStatus {
  /// Tokens / tool events are still streaming in.
  streaming,

  /// The turn finished cleanly.
  done,

  /// The service errored before completing. [AgentTurn.errorMessage] holds
  /// the short human-readable reason; the UI surfaces a Retry button.
  failed,

  /// The user pressed Stop. Whatever blocks streamed in stay visible, but
  /// the UI tags the turn as cancelled.
  stopped,
}

class AgentTurn extends ChatItem {
  AgentTurn({
    required super.id,
    List<AgentBlock>? blocks,
    AgentTurnStatus? status,
    bool? isStreaming,
    this.errorMessage,
  })  : blocks = blocks ?? <AgentBlock>[],
        status = status ??
            ((isStreaming ?? true)
                ? AgentTurnStatus.streaming
                : AgentTurnStatus.done);

  final List<AgentBlock> blocks;
  AgentTurnStatus status;
  String? errorMessage;

  bool get isStreaming => status == AgentTurnStatus.streaming;
  set isStreaming(bool value) {
    status = value ? AgentTurnStatus.streaming : AgentTurnStatus.done;
  }
}

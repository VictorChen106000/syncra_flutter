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

class AgentTurn extends ChatItem {
  AgentTurn({
    required super.id,
    List<AgentBlock>? blocks,
    this.isStreaming = true,
  }) : blocks = blocks ?? <AgentBlock>[];

  final List<AgentBlock> blocks;
  bool isStreaming;
}

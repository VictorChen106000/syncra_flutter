enum ChatSender { ai, user }

enum ChatMessageType { text, resultCards }

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

class ChatMessage {
  const ChatMessage({
    required this.sender,
    required this.type,
    this.text = '',
    this.attachments = const [],
  });

  final ChatSender sender;
  final ChatMessageType type;
  final String text;
  final List<ChatAttachment> attachments;
}

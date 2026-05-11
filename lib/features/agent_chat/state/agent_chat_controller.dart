import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_strings.dart';
import '../models/chat_message.dart';

class AgentChatController extends ChangeNotifier {
  AgentChatController()
      : _messages = const [
          ChatMessage(sender: ChatSender.ai, type: ChatMessageType.text, text: AppStrings.chatInitialMessage),
        ];

  final List<Timer> _timers = [];
  final List<ChatMessage> _messages;
  bool _isTyping = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isTyping => _isTyping;

  void sendPrompt({
    required String prompt,
    List<ChatAttachment> attachments = const [],
  }) {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty || _isTyping) return;

    _messages.add(
      ChatMessage(
        sender: ChatSender.user,
        type: ChatMessageType.text,
        text: cleanPrompt,
        attachments: attachments,
      ),
    );
    _isTyping = true;
    notifyListeners();

    _timers.add(Timer(const Duration(milliseconds: 1600), () {
      _isTyping = false;
      _messages.add(
        const ChatMessage(
          sender: ChatSender.ai,
          type: ChatMessageType.text,
          text:
              "I found a strong fit at Linear. I tailored your project wording to highlight Design Systems and prepared a cold outreach draft with recent company context.",
        ),
      );
      _messages.add(const ChatMessage(sender: ChatSender.ai, type: ChatMessageType.resultCards));
      notifyListeners();
    }));
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }
}

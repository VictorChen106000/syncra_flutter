import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/file_formatter.dart';
import '../../models/chat_message.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
  });

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isAi = message.sender == ChatSender.ai;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isAi ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isAi) ...[
            const CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.ink,
              child: Icon(Icons.star_rounded, color: AppColors.accent, size: 15),
            ),
            const SizedBox(width: 9),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isAi ? AppColors.surface : AppColors.ink,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(22),
                  topRight: const Radius.circular(22),
                  bottomLeft: Radius.circular(isAi ? 4 : 22),
                  bottomRight: Radius.circular(isAi ? 22 : 4),
                ),
                border: isAi ? Border.all(color: Colors.white.withOpacity( 0.60)) : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity( 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isAi && message.attachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: message.attachments.map((attachment) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity( 0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.description_rounded, color: AppColors.accent, size: 14),
                                const SizedBox(width: 5),
                                Text(
                                  FileFormatter.cleanName(attachment.name),
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  Text(
                    message.text,
                    style: TextStyle(
                      color: isAi ? AppColors.ink : Colors.white,
                      fontSize: 14.5,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

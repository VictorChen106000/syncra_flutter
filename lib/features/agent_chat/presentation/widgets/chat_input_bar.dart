import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../resumes/presentation/widgets/resume_attachment_chips.dart';
import '../../../resumes/presentation/widgets/select_resumes_bottom_sheet.dart';
import '../../../resumes/state/resume_controller.dart';
import '../../models/chat_message.dart';
import '../../state/agent_chat_controller.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _send(BuildContext context) {
    final resumeController = context.read<ResumeController>();
    final attachments = resumeController.selectedResumes
        .map((resume) => ChatAttachment(id: resume.id, name: resume.name))
        .toList();

    context.read<AgentChatController>().sendPrompt(
          prompt: _textController.text,
          attachments: attachments,
        );
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ResumeController, AgentChatController>(
      builder: (context, resumeController, chatController, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          color: AppColors.scaffold,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.40),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ResumeAttachmentChips(
                  resumes: resumeController.selectedResumes,
                  onRemove: resumeController.removeSelectedResume,
                ),
                Row(
                  children: [
                    InkResponse(
                      onTap: chatController.isTyping
                          ? null
                          : () => SelectResumesBottomSheet.show(context),
                      radius: 24,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.scaffold,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.add_rounded,
                          color: chatController.isTyping
                              ? AppColors.textSoft
                              : AppColors.ink,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        enabled: !chatController.isTyping,
                        onSubmitted: (_) => _send(context),
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: chatController.isTyping
                              ? 'Syncra is executing plan...'
                              : AppStrings.askSyncra,
                          hintStyle: const TextStyle(
                            color: AppColors.textSoft,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    InkResponse(
                      onTap: chatController.isTyping
                          ? null
                          : () => _send(context),
                      radius: 24,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.white.withValues(
                            alpha: chatController.isTyping ? 0.4 : 1,
                          ),
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

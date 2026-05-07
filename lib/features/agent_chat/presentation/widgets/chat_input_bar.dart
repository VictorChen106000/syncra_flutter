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
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.scaffold.withOpacity( 0.10),
                AppColors.scaffold,
              ],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity( 0.76),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity( 0.12),
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
                    IconButton(
                      onPressed: chatController.isTyping ? null : () => SelectResumesBottomSheet.show(context),
                      icon: const Icon(Icons.add_rounded),
                      style: IconButton.styleFrom(backgroundColor: AppColors.scaffold),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        enabled: !chatController.isTyping,
                        onSubmitted: (_) => _send(context),
                        decoration: InputDecoration(
                          hintText: chatController.isTyping ? 'Syncra is executing plan...' : AppStrings.askSyncra,
                          hintStyle: const TextStyle(color: AppColors.textSoft, fontWeight: FontWeight.w600),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: chatController.isTyping ? null : () => _send(context),
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      style: IconButton.styleFrom(backgroundColor: AppColors.ink),
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

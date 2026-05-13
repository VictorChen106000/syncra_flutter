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
        final isTyping = chatController.isTyping;
        final hasText = _textController.text.trim().isNotEmpty;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          color: AppColors.scaffold,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ResumeAttachmentChips(
                  resumes: resumeController.selectedResumes,
                  onRemove: resumeController.removeSelectedResume,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _IconButton(
                      icon: Icons.add_rounded,
                      onTap: isTyping
                          ? null
                          : () => SelectResumesBottomSheet.show(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: TextField(
                          controller: _textController,
                          enabled: !isTyping,
                          maxLines: 5,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _send(context),
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                            height: 1.35,
                          ),
                          decoration: InputDecoration(
                            hintText: isTyping
                                ? 'Syncra is thinking…'
                                : AppStrings.askSyncra,
                            hintStyle: const TextStyle(
                              color: AppColors.textSoft,
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _SendButton(
                      enabled: !isTyping && hasText,
                      onTap: () => _send(context),
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

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            icon,
            color: enabled ? AppColors.ink : AppColors.textSoft,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: enabled ? AppColors.ink : AppColors.border,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: const SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              Icons.arrow_upward_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../resumes/presentation/widgets/resume_attachment_chips.dart';
import '../../../resumes/presentation/widgets/select_resumes_bottom_sheet.dart';
import '../../../resumes/state/resume_controller.dart';
import '../../models/chat_message.dart';
import '../../state/agent_chat_controller.dart';

/// Claude-style composer. Large rounded surface with the text field on top
/// and a clean action row beneath (attach · model pill · send). Subtle
/// focus halo and crisp send affordance.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus != _focused) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
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
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ResumeController, AgentChatController>(
      builder: (context, resumeController, chatController, _) {
        final streaming = chatController.isStreaming;
        final hasText = _textController.text.trim().isNotEmpty;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          color: AppColors.surface,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: _focused
                    ? AppColors.ink.withValues(alpha: 0.55)
                    : AppColors.border,
                width: _focused ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: _focused ? 0.10 : 0.05,
                  ),
                  blurRadius: _focused ? 28 : 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (resumeController.selectedResumes.isNotEmpty) ...[
                  ResumeAttachmentChips(
                    resumes: resumeController.selectedResumes,
                    onRemove: resumeController.removeSelectedResume,
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  enabled: !streaming,
                  maxLines: 6,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  cursorColor: AppColors.ink,
                  cursorWidth: 1.4,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    height: 1.4,
                    letterSpacing: -0.1,
                  ),
                  decoration: InputDecoration(
                    hintText: streaming
                        ? 'Syncra is working…'
                        : 'Message Syncra',
                    hintStyle: const TextStyle(
                      color: AppColors.textSoft,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      letterSpacing: -0.1,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _CircleAction(
                      icon: Icons.add_rounded,
                      tooltip: 'Attach resume',
                      onTap: streaming
                          ? null
                          : () => SelectResumesBottomSheet.show(context),
                    ),
                    const SizedBox(width: 6),
                    _CircleAction(
                      icon: Icons.mic_none_rounded,
                      tooltip: 'Voice input',
                      onTap: streaming ? null : () {},
                    ),
                    const SizedBox(width: 8),
                    const _ModelPill(),
                    const Spacer(),
                    _SendButton(
                      enabled: !streaming && hasText,
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

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.softSurface,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: enabled ? AppColors.ink : AppColors.textSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelPill extends StatelessWidget {
  const _ModelPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: AppColors.softSurface,
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.auto_awesome_rounded, size: 13, color: AppColors.ink),
          SizedBox(width: 6),
          Text(
            'Syncra 2.5',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              letterSpacing: -0.1,
            ),
          ),
          SizedBox(width: 2),
          Icon(
            Icons.expand_more_rounded,
            size: 14,
            color: AppColors.textMuted,
          ),
        ],
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: enabled ? AppColors.ink : AppColors.softSurface,
        shape: BoxShape.circle,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: Icon(
            Icons.arrow_upward_rounded,
            color: enabled ? Colors.white : AppColors.textSoft,
            size: 20,
          ),
        ),
      ),
    );
  }
}

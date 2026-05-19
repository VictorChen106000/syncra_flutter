import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../../resumes/presentation/widgets/resume_attachment_chips.dart';
import '../../../resumes/presentation/widgets/select_resumes_bottom_sheet.dart';
import '../../../resumes/state/resume_notifier.dart';
import '../../models/chat_message.dart';
import '../../state/agent_chat_notifier.dart';

class ChatInputBar extends ConsumerStatefulWidget {
  const ChatInputBar({super.key});

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;
  late final AnimationController _bounceController;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 320,
    damping: 11,
  );

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController.unbounded(
      vsync: this,
      value: 1.0,
    );
    _focusNode.addListener(() {
      if (_focusNode.hasFocus != _focused) {
        setState(() => _focused = _focusNode.hasFocus);
        if (_focusNode.hasFocus) _bounce(from: 0.96);
      }
    });
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _bounce({required double from}) {
    _bounceController.stop();
    _bounceController.value = from;
    _bounceController.animateWith(
      SpringSimulation(_spring, from, 1.0, 0),
    );
  }

  void _send() {
    final resumeState = ref.read(resumeProvider);
    final attachments = resumeState.selectedResumes
        .map((resume) => ChatAttachment(id: resume.id, name: resume.name))
        .toList();

    ref.read(agentChatProvider.notifier).sendPrompt(
          prompt: _textController.text,
          attachments: attachments,
        );
    _textController.clear();
    _bounce(from: 1.06);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final resumeState = ref.watch(resumeProvider);
    final resumeNotifier = ref.read(resumeProvider.notifier);
    final chatState = ref.watch(agentChatProvider);
    final streaming = chatState.isStreaming;
    final hasText = _textController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      color: brand.surface,
      child: AnimatedBuilder(
        animation: _bounceController,
        builder: (context, child) => Transform.scale(
          scale: _bounceController.value,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: _focused
                  ? brand.ink.withValues(alpha: 0.55)
                  : brand.border,
              width: _focused ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: brand.shadow.withValues(
                  alpha: _focused ? 0.32 : 0.16,
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
              if (resumeState.selectedResumes.isNotEmpty) ...[
                ResumeAttachmentChips(
                  resumes: resumeState.selectedResumes,
                  onRemove: resumeNotifier.removeSelectedResume,
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
                cursorColor: brand.ink,
                cursorWidth: 1.4,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  color: brand.ink,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  height: 1.4,
                  letterSpacing: -0.1,
                ),
                decoration: InputDecoration(
                  hintText: streaming ? 'Syncra is working…' : 'Message Syncra',
                  hintStyle: TextStyle(
                    color: brand.textSoft,
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
                    onTap: _send,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
    final brand = context.brand;
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
              color: brand.surfaceMuted,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: enabled ? brand.ink : brand.textSoft,
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
    final brand = context.brand;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: brand.surfaceMuted,
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 13, color: brand.ink),
          const SizedBox(width: 6),
          Text(
            'Syncra 2.5',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: brand.ink,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.expand_more_rounded,
            size: 14,
            color: brand.textMuted,
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
    final brand = context.brand;
    return Semantics(
      label: 'Send message',
      button: true,
      enabled: enabled,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled ? brand.ink : brand.surfaceMuted,
          shape: BoxShape.circle,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: brand.ink.withValues(alpha: 0.22),
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
            excludeFromSemantics: true,
            child: Icon(
              Icons.arrow_upward_rounded,
              color: enabled ? brand.inkInverse : brand.textSoft,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

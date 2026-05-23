import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../../../core/utils/motion.dart';
import '../../../resumes/presentation/widgets/resume_attachment_chips.dart';
import '../../../resumes/presentation/widgets/select_resumes_bottom_sheet.dart';
import '../../../resumes/state/resume_notifier.dart';
import '../../models/chat_message.dart';
import '../../state/agent_chat_notifier.dart';

/// Keyboard intent fired by Cmd+Enter / Ctrl+Enter to submit the composer.
class _SendIntent extends Intent {
  const _SendIntent();
}

class ChatInputBar extends ConsumerStatefulWidget {
  const ChatInputBar({super.key, this.autofocus = false});

  /// When true, the composer grabs focus on first build — used when the user
  /// arrives from the dashboard's "Ask Syncra" bar intending to type straight
  /// away.
  final bool autofocus;

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
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
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
    final chatState = ref.watch(agentChatProvider);
    final streaming = chatState.isStreaming;
    final hasText = _textController.text.trim().isNotEmpty;
    // Before the first message is sent, an attached resume is "pending" —
    // we preview it inside the composer. Once the chat is underway it's
    // promoted to the persistent context card up top, so drop it here.
    final hasSentMessage = chatState.items.any((i) => i is UserMessage);
    final resumeState = ref.watch(resumeProvider);
    final resumeNotifier = ref.read(resumeProvider.notifier);
    final showComposerResumes =
        !hasSentMessage && resumeState.selectedResumes.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        6,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
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
              if (showComposerResumes) ...[
                ResumeAttachmentChips(
                  resumes: resumeState.selectedResumes,
                  onRemove: resumeNotifier.removeSelectedResume,
                ),
                const SizedBox(height: 8),
              ],
              // Cmd/Ctrl+Enter submits even though Enter inserts a newline.
              // Keeps mobile/IME behavior intact while making the input feel
              // native on desktop and web.
              Shortcuts(
                shortcuts: <ShortcutActivator, Intent>{
                  const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                      const _SendIntent(),
                  const SingleActivator(LogicalKeyboardKey.enter, control: true):
                      const _SendIntent(),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    _SendIntent: CallbackAction<_SendIntent>(
                      onInvoke: (_) {
                        if (!streaming && hasText) _send();
                        return null;
                      },
                    ),
                  },
                  child: TextField(
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
                      hintText:
                          streaming ? 'Syncra is working…' : 'Message Syncra',
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
                  const SizedBox(width: 8),
                  _ModelChip(streaming: streaming),
                  const Spacer(),
                  _SendButton(
                    streaming: streaming,
                    enabled: streaming || hasText,
                    onTap: streaming
                        ? ref.read(agentChatProvider.notifier).stopStreaming
                        : _send,
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

/// Active-model pill that lives in the composer, beside the attach button —
/// the chat's single "which model am I talking to" indicator. The dot pulses
/// while the agent is streaming a response.
class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.streaming});

  final bool streaming;

  static const _modelLabel = 'Syncra Opus';

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Semantics(
      label: streaming
          ? '$_modelLabel, generating response'
          : '$_modelLabel, idle',
      container: true,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: brand.surfaceMuted,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MiniPulseDot(active: streaming, color: brand.accent),
            const SizedBox(width: 7),
            Text(
              _modelLabel,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: brand.ink,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPulseDot extends StatelessWidget {
  const _MiniPulseDot({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!active) return dot;
    return dot
        .animate(onPlay: repeatIfMotion(context, reverse: true))
        .fadeIn(begin: 0.45, duration: 700.ms);
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

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.streaming,
    required this.enabled,
    required this.onTap,
  });

  final bool streaming;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final active = enabled;
    return Semantics(
      label: streaming ? 'Stop generating' : 'Send message',
      button: true,
      enabled: active,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active ? brand.ink : brand.surfaceMuted,
          shape: BoxShape.circle,
          boxShadow: active
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
            onTap: active ? onTap : null,
            customBorder: const CircleBorder(),
            excludeFromSemantics: true,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: streaming
                  ? Icon(
                      Icons.stop_rounded,
                      key: const ValueKey('stop'),
                      color: brand.inkInverse,
                      size: 20,
                    )
                  : Icon(
                      Icons.arrow_upward_rounded,
                      key: const ValueKey('send'),
                      color: active ? brand.inkInverse : brand.textSoft,
                      size: 20,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

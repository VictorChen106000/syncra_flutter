import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../../resumes/presentation/widgets/resume_attachment_chips.dart';
import '../../../resumes/presentation/widgets/select_resumes_bottom_sheet.dart';
import '../../../resumes/state/resume_notifier.dart';
import '../../models/agent_block.dart';
import '../../models/chat_message.dart';
import '../../state/agent_chat_notifier.dart';

/// Keyboard intent fired by Cmd+Enter / Ctrl+Enter to submit the composer.
class _SendIntent extends Intent {
  const _SendIntent();
}

class ChatInputBar extends ConsumerStatefulWidget {
  const ChatInputBar({super.key, this.autofocus = false, this.onJumpToBlock});

  /// When true, the composer grabs focus on first build — used when the user
  /// arrives from the dashboard's "Ask Syncra" bar intending to type straight
  /// away.
  final bool autofocus;

  /// Scrolls the transcript to the artifact block with the given id. Supplied
  /// by [AiChatbotPage], which owns the scroll controller. The second argument
  /// is the block's rough ordinal position in the item list (0–1), used to
  /// coarse-jump toward lazily-built blocks before settling. When null, the
  /// "Jump to section" chip renders disabled.
  final void Function(String blockId, double ordinalFraction)? onJumpToBlock;

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
    _bounceController = AnimationController.unbounded(vsync: this, value: 1.0);
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
    // A prompt card may have parked a draft for us (e.g. the user tapped a
    // dashboard suggestion). Pre-fill it so they can attach a resume and edit
    // before sending — nothing fires until they tap Send.
    final draft = ref.read(composerDraftProvider);
    if (draft != null && draft.trim().isNotEmpty) _fillFromDraft(draft);
  }

  /// Drops [text] into the composer, parks the cursor at the end, focuses, and
  /// clears the shared draft slot — without sending.
  void _fillFromDraft(String text) {
    _textController.text = text;
    _textController.selection = TextSelection.collapsed(offset: text.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      ref.read(composerDraftProvider.notifier).state = null;
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
    _bounceController.animateWith(SpringSimulation(_spring, from, 1.0, 0));
  }

  void _send() {
    final resumeState = ref.read(resumeProvider);
    final attachments = resumeState.selectedResumes
        .map((resume) => ChatAttachment(id: resume.id, name: resume.name))
        .toList();

    ref
        .read(agentChatProvider.notifier)
        .sendPrompt(prompt: _textController.text, attachments: attachments);
    _textController.clear();
    _bounce(from: 1.06);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    // A draft arriving while the composer is already on screen (e.g. tapping a
    // suggestion in the chat's empty state) — load it the same way.
    ref.listen<String?>(composerDraftProvider, (_, next) {
      if (next == null || next.trim().isEmpty) return;
      _fillFromDraft(next);
      setState(() {});
    });
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
                color: brand.shadow.withValues(alpha: _focused ? 0.32 : 0.16),
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
                  const SingleActivator(
                    LogicalKeyboardKey.enter,
                    control: true,
                  ): const _SendIntent(),
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
                      hintText: streaming
                          ? 'Syncra is working…'
                          : 'Message Syncra',
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
                    tooltip: 'Upload or attach resume',
                    onTap: streaming
                        ? null
                        : () => SelectResumesBottomSheet.show(context),
                  ),
                  const SizedBox(width: 8),
                  _JumpToSectionChip(onJump: widget.onJumpToBlock),
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

/// A jumpable artifact in the transcript — a job rail, tailored-resume card,
/// resume draft, or outreach email. Built from the live chat state and listed
/// in the "Jump to section" sheet so the user can leap straight to it.
class _ChatSection {
  const _ChatSection({
    required this.blockId,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.ordinalFraction,
  });

  final String blockId;
  final IconData icon;
  final String label;
  final String subtitle;

  /// Rough position of the owning item in the transcript (0 = top, 1 = bottom),
  /// handed to [AiChatbotPage] to coarse-jump toward lazily-built blocks.
  final double ordinalFraction;
}

/// Walks the chat transcript and pulls out the artifact blocks worth jumping
/// to, in transcript order. Plain text / tool-call / thinking blocks are
/// skipped — only the cards a user would want to revisit make the list.
List<_ChatSection> _collectSections(AgentChatState state) {
  final items = state.items;
  final denom = items.length > 1 ? items.length - 1 : 1;
  final sections = <_ChatSection>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item is! AgentTurn) continue;
    final fraction = i / denom;
    for (final block in item.blocks) {
      switch (block) {
        case JobsBlock():
          final n = block.jobs.length;
          sections.add(
            _ChatSection(
              blockId: block.id,
              icon: Icons.travel_explore_rounded,
              label: 'Job matches',
              subtitle: '$n role${n == 1 ? '' : 's'}',
              ordinalFraction: fraction,
            ),
          );
        case ProposedEditsBlock():
          final n = block.edits.length;
          sections.add(
            _ChatSection(
              blockId: block.id,
              icon: Icons.auto_awesome_rounded,
              label: 'Tailored resume',
              subtitle: '$n edit${n == 1 ? '' : 's'}',
              ordinalFraction: fraction,
            ),
          );
        case ResumeDraftBlock():
          sections.add(
            _ChatSection(
              blockId: block.id,
              icon: Icons.description_outlined,
              label: 'Resume draft',
              subtitle: block.fileName,
              ordinalFraction: fraction,
            ),
          );
        case EmailDraftBlock():
          sections.add(
            _ChatSection(
              blockId: block.id,
              icon: Icons.mail_outline_rounded,
              label: 'Outreach email',
              subtitle: block.subject.trim().isNotEmpty
                  ? block.subject.trim()
                  : block.recipient,
              ordinalFraction: fraction,
            ),
          );
        default:
          break;
      }
    }
  }
  return sections;
}

/// Composer pill that opens a sheet of the chat's key sections (job matches,
/// tailored resumes, drafts, outreach) and scrolls straight to the one tapped.
/// Renders disabled until the conversation has produced something to jump to.
class _JumpToSectionChip extends ConsumerWidget {
  const _JumpToSectionChip({required this.onJump});

  final void Function(String blockId, double ordinalFraction)? onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final sections = _collectSections(ref.watch(agentChatProvider));
    final enabled = sections.isNotEmpty && onJump != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Jump to a section of this chat',
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: brand.surfaceMuted,
          borderRadius: BorderRadius.circular(99),
          child: InkWell(
            onTap: enabled ? () => _open(context, sections) : null,
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.double_arrow_rounded, size: 16, color: brand.ink),
                  const SizedBox(width: 6),
                  Text(
                    'Jump to',
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
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, List<_ChatSection> sections) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: context.brand.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) => _JumpSectionsSheet(
        sections: sections,
        onSelect: (section) {
          Navigator.of(sheetContext).pop();
          onJump?.call(section.blockId, section.ordinalFraction);
        },
      ),
    );
  }
}

/// Bottom sheet listing the chat's jumpable sections. Tapping a row closes the
/// sheet and scrolls the transcript to that artifact.
class _JumpSectionsSheet extends StatelessWidget {
  const _JumpSectionsSheet({required this.sections, required this.onSelect});

  final List<_ChatSection> sections;
  final ValueChanged<_ChatSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Jump to section',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: brand.ink,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: brand.ink),
                  style: IconButton.styleFrom(backgroundColor: brand.border),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: brand.border),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: sections.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _SectionTile(
                section: sections[i],
                onTap: () => onSelect(sections[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section, required this.onTap});

  final _ChatSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: brand.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: brand.surfaceMuted,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(section.icon, size: 18, color: brand.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: brand.ink,
                        letterSpacing: -0.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      section.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: brand.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: brand.textSoft,
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
    final button = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: brand.surfaceMuted,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: enabled ? brand.ink : brand.textSoft),
    );
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: button,
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
          // Lime primary action when it can be tapped; falls back to a muted
          // grey circle while disabled. No glow.
          color: active ? brand.accent : brand.surfaceMuted,
          shape: BoxShape.circle,
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
                      color: brand.onAccent,
                      size: 20,
                    )
                  : Icon(
                      Icons.arrow_upward_rounded,
                      key: const ValueKey('send'),
                      color: active ? brand.onAccent : brand.textSoft,
                      size: 20,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

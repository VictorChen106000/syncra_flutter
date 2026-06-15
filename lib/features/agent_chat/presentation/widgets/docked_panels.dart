import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../models/agent_block.dart';
import '../../state/agent_chat_notifier.dart';

/// Panels that dock directly above the composer — the single place the agent
/// surfaces anything that needs the user before it can continue.
///
/// Both an [ActionProposalBlock] awaiting Accept and a pending
/// [InputRequestBlock] awaiting an answer are hoisted out of the transcript
/// and pinned here, Claude-Code style: the question never scrolls away, and
/// the answer lives one thumb-reach from the keyboard.

/// Shared visual shell for a docked panel. Solid (not frosted) so it reads as
/// one stacked sheet with the composer beneath it, with a layered shadow that
/// lifts it off the transcript.
class _DockedShell extends StatelessWidget {
  const _DockedShell({required this.eyebrow, required this.child});

  final String eyebrow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: brand.border, width: 1),
        boxShadow: [
          // Tight contact shadow + a soft diffuse one — the layered pair reads
          // as a physically lifted sheet rather than a flat drop shadow.
          BoxShadow(
            color: brand.shadow.withValues(alpha: 0.10),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: brand.shadow.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Eyebrow(label: eyebrow),
          const SizedBox(height: 11),
          child,
        ],
      ),
    );
  }
}

/// Micro-label with a single accent dot — the lone splash of colour. Replaces
/// the old accent-filled badge: minimal, but the glowing dot still says
/// "this one's on you".
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: brand.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: brand.accent.withValues(alpha: 0.5),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            color: brand.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Pending [ActionProposalBlock] hoisted into the docked island above the
/// composer — the "Accept changes" pill.
class DockedActionProposal extends ConsumerWidget {
  const DockedActionProposal({super.key, required this.block});

  final ActionProposalBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final notifier = ref.read(agentChatProvider.notifier);
    return _DockedShell(
          eyebrow: 'PROPOSED ACTION',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ink tile + accent icon — the app's established premium
                  // pairing (see ProposedEditsBlock, the thread hero).
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: brand.ink,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(block.icon, size: 16, color: brand.accent),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          block.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: brand.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          block.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: brand.textMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _DockedButton(
                      label: block.editLabel,
                      filled: false,
                      onTap: () => notifier.dismissProposal(block.id),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DockedButton(
                      label: block.acceptLabel,
                      icon: Icons.arrow_forward_rounded,
                      filled: true,
                      onTap: () => notifier.acceptProposal(block.id),
                    ),
                  ),
                ],
              ),
            ],
          ),
        )
        .animate(key: ValueKey(block.id))
        .fadeIn(duration: 220.ms)
        .moveY(begin: 14, end: 0, duration: 240.ms, curve: Curves.easeOutCubic);
  }
}

/// Pending [InputRequestBlock] hoisted into the docked island. The agent
/// loop is paused on `ask_user`; this is the only place to answer. Once
/// submitted the block flips to answered and settles back into the
/// transcript as a Q&A record.
class DockedInputRequest extends ConsumerStatefulWidget {
  const DockedInputRequest({super.key, required this.block});

  final InputRequestBlock block;

  @override
  ConsumerState<DockedInputRequest> createState() => _DockedInputRequestState();
}

class _DockedInputRequestState extends ConsumerState<DockedInputRequest> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.block.answer ?? '',
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    ref
        .read(agentChatProvider.notifier)
        .submitInputAnswer(widget.block.id, trimmed);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hasText = _controller.text.trim().isNotEmpty;
    return _DockedShell(
          eyebrow: 'NEEDS YOUR INPUT',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.block.question,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                  height: 1.4,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 4, 5, 4),
                decoration: BoxDecoration(
                  color: brand.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: brand.border, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: _submit,
                        cursorColor: brand.ink,
                        cursorWidth: 1.4,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: brand.ink,
                          height: 1.4,
                          letterSpacing: -0.1,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Type your answer…',
                          hintStyle: TextStyle(
                            color: brand.textSoft,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            letterSpacing: -0.1,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: _AnswerSendButton(
                        enabled: hasText,
                        onTap: () => _submit(_controller.text),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.block.suggestions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in widget.block.suggestions)
                      _SuggestionChip(label: s, onTap: () => _submit(s)),
                  ],
                ),
              ],
            ],
          ),
        )
        .animate(key: ValueKey(widget.block.id))
        .fadeIn(duration: 220.ms)
        .moveY(begin: 14, end: 0, duration: 240.ms, curve: Curves.easeOutCubic);
  }
}

/// Ghost / filled action button used by the docked proposal.
class _DockedButton extends StatelessWidget {
  const _DockedButton({
    required this.label,
    required this.filled,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final fg = filled ? brand.inkInverse : brand.ink;
    return Material(
      color: filled ? brand.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: filled ? brand.ink : brand.border,
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: -0.1,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 6),
                Icon(icon, size: 15, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact send button living inside the docked answer field.
class _AnswerSendButton extends StatelessWidget {
  const _AnswerSendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Semantics(
      label: 'Send answer',
      button: true,
      enabled: enabled,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled ? brand.ink : brand.surface,
          shape: BoxShape.circle,
          border: enabled ? null : Border.all(color: brand.border, width: 1),
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
              size: 18,
              color: enabled ? brand.inkInverse : brand.textSoft,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tappable answer shortcut — fills the answer in one tap.
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.surfaceMuted,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: brand.border, width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: brand.ink,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

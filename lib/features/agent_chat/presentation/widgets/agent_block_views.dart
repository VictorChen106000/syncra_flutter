import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../../../core/utils/motion.dart';
import '../../models/agent_block.dart';
import '../../state/agent_chat_notifier.dart';

class AgentBlockView extends StatelessWidget {
  const AgentBlockView({super.key, required this.block});

  final AgentBlock block;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      ThinkingBlock(:final content) => ThinkingBlockView(content: content),
      ToolCallBlock() => ToolCallBlockView(block: block as ToolCallBlock),
      TextBlock(:final text) => _TextBlockView(text: text),
      InputRequestBlock() =>
        InputRequestView(block: block as InputRequestBlock),
      ActionProposalBlock() =>
        ActionProposalView(block: block as ActionProposalBlock),
    };
  }
}

class InputRequestView extends ConsumerStatefulWidget {
  const InputRequestView({super.key, required this.block});

  final InputRequestBlock block;

  @override
  ConsumerState<InputRequestView> createState() => _InputRequestViewState();
}

class _InputRequestViewState extends ConsumerState<InputRequestView> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.block.answer ?? '');
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
    final answered = widget.block.state == InputRequestState.answered;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: answered ? brand.surfaceMuted : brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: answered ? brand.border : brand.accent,
          width: answered ? 1 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                answered
                    ? Icons.check_circle_rounded
                    : Icons.question_answer_rounded,
                size: 16,
                color: answered ? brand.textMuted : brand.ink,
              ),
              const SizedBox(width: 8),
              Text(
                'AGENT NEEDS YOUR INPUT',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: brand.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.block.question,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: brand.ink,
              height: 1.4,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 12),
          if (answered)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: brand.border),
              ),
              child: Text(
                widget.block.answer ?? '',
                style: TextStyle(
                  fontSize: 13.5,
                  color: brand.ink,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            )
          else ...[
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: _submit,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: brand.ink,
              ),
              decoration: InputDecoration(
                hintText: 'Type your answer…',
                hintStyle: TextStyle(
                  color: brand.textSoft,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: brand.surfaceMuted,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  color: brand.ink,
                  onPressed: () => _submit(_controller.text),
                ),
              ),
            ),
            if (widget.block.suggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in widget.block.suggestions)
                    _SuggestionChip(
                      label: s,
                      onTap: () {
                        _controller.text = s;
                        _submit(s);
                      },
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.surface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: brand.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: brand.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _TextBlockView extends StatelessWidget {
  const _TextBlockView({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    // Agent prose renders in a serif (Source Serif 4) to set the AI's
    // "voice" apart from the all-Inter UI chrome — the same chrome/serif
    // split Claude's mobile app uses.
    final body = GoogleFonts.sourceSerif4(
      color: brand.ink,
      fontSize: 16,
      height: 1.62,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    );
    return MarkdownBody(
      data: text,
      selectable: true,
      shrinkWrap: true,
      onTapLink: (text, href, title) {
        // Links are non-actionable for now; surfacing them via launchUrl can
        // be wired through the router later. Swallowing keeps the chat from
        // throwing on stray markdown URLs in agent output.
      },
      styleSheet: MarkdownStyleSheet(
        p: body,
        strong: body.copyWith(fontWeight: FontWeight.w800),
        em: body.copyWith(fontStyle: FontStyle.italic),
        a: body.copyWith(
          color: brand.accent,
          decoration: TextDecoration.underline,
        ),
        h1: body.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          height: 1.3,
          letterSpacing: -0.3,
        ),
        h2: body.copyWith(
          fontSize: 17.5,
          fontWeight: FontWeight.w800,
          height: 1.3,
          letterSpacing: -0.2,
        ),
        h3: body.copyWith(
          fontSize: 15.5,
          fontWeight: FontWeight.w800,
          height: 1.35,
          letterSpacing: -0.15,
        ),
        listBullet: body,
        code: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Courier'],
          fontSize: 13.5,
          color: brand.ink,
          backgroundColor: brand.surfaceMuted,
          height: 1.4,
        ),
        codeblockDecoration: BoxDecoration(
          color: brand.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: brand.border, width: 0.6),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquote: body.copyWith(
          color: brand.textMuted,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          color: brand.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: brand.border, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        blockSpacing: 10,
        h1Padding: const EdgeInsets.only(top: 6, bottom: 2),
        h2Padding: const EdgeInsets.only(top: 6, bottom: 2),
        h3Padding: const EdgeInsets.only(top: 4, bottom: 2),
      ),
    );
  }
}

class ThinkingBlockView extends StatefulWidget {
  const ThinkingBlockView({super.key, required this.content});
  final String content;

  @override
  State<ThinkingBlockView> createState() => _ThinkingBlockViewState();
}

class _ThinkingBlockViewState extends State<ThinkingBlockView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ShimmerText(
                    text: 'Thought for a moment',
                    active: !_expanded,
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 180),
                    turns: _expanded ? 0.5 : 0,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 16,
                      color: brand.textSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: brand.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.content,
                      style: TextStyle(
                        color: brand.textMuted,
                        fontSize: 13.5,
                        height: 1.6,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        letterSpacing: -0.05,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShimmerText extends StatelessWidget {
  const _ShimmerText({required this.text, required this.active});
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final base = Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: brand.textMuted,
        letterSpacing: -0.1,
      ),
    );
    if (!active) return base;
    return base
        .animate(onPlay: repeatIfMotion(context))
        .shimmer(
          duration: 1600.ms,
          color: brand.ink.withValues(alpha: 0.55),
        );
  }
}

class ToolCallBlockView extends StatelessWidget {
  const ToolCallBlockView({super.key, required this.block});

  final ToolCallBlock block;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final running = block.status == ToolCallStatus.running;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: running
                    ? const _Spinner()
                    : Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: brand.textMuted,
                      ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: running
                    ? _ShimmerText(text: block.label, active: true)
                    : Text(
                        block.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: brand.textMuted,
                          letterSpacing: -0.1,
                        ),
                      ),
              ),
            ],
          ),
          if (!running && block.resultSummary != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                block.resultSummary!,
                style: TextStyle(
                  color: brand.textSoft,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Icon(
      Icons.refresh_rounded,
      size: 14,
      color: brand.textMuted.withValues(alpha: 0.85),
    )
        .animate(onPlay: repeatIfMotion(context))
        .rotate(duration: 900.ms, curve: Curves.linear);
  }
}

class ActionProposalView extends StatelessWidget {
  const ActionProposalView({super.key, required this.block});

  final ActionProposalBlock block;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final accepted = block.state == ActionState.accepted;
    final dismissed = block.state == ActionState.dismissed;
    final settled = accepted || dismissed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accepted ? brand.ink : brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accepted ? brand.ink : brand.border,
        ),
        boxShadow: accepted
            ? [
                BoxShadow(
                  color: brand.ink.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accepted ? brand.accent : brand.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  block.icon,
                  size: 18,
                  color: accepted ? brand.onAccent : brand.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      block.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: accepted ? brand.inkInverse : brand.ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      block.description,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: accepted
                            ? brand.inkInverse.withValues(alpha: 0.78)
                            : brand.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (settled)
            _SettledFooter(accepted: accepted)
          else
            _ActionRow(block: block),
        ],
      ),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.block});

  final ActionProposalBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: _ProposalButton(
            label: block.editLabel,
            icon: Icons.tune_rounded,
            filled: false,
            onTap: () =>
                ref.read(agentChatProvider.notifier).dismissProposal(block.id),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ProposalButton(
            label: block.acceptLabel,
            icon: Icons.check_rounded,
            filled: true,
            onTap: () =>
                ref.read(agentChatProvider.notifier).acceptProposal(block.id),
          ),
        ),
      ],
    );
  }
}

class _SettledFooter extends StatelessWidget {
  const _SettledFooter({required this.accepted});
  final bool accepted;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      children: [
        Icon(
          accepted ? Icons.check_circle_rounded : Icons.history_rounded,
          size: 14,
          color: accepted ? brand.accent : brand.textMuted,
        ),
        const SizedBox(width: 6),
        Text(
          accepted ? 'Accepted · running now' : 'Reverted — tell me how to adjust',
          style: TextStyle(
            color: accepted
                ? brand.inkInverse.withValues(alpha: 0.88)
                : brand.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

class _ProposalButton extends StatelessWidget {
  const _ProposalButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final bg = filled ? brand.ink : Colors.transparent;
    final fg = filled ? brand.inkInverse : brand.ink;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: filled ? brand.ink : brand.border,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

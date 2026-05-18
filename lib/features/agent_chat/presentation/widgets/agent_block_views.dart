import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/motion.dart';
import '../../models/agent_block.dart';
import '../../state/agent_chat_notifier.dart';

/// Routes an [AgentBlock] to its renderer. Add a new branch here when a new
/// block type lands.
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

// ---------------------------------------------------------------------------
// Input request — inline text field + suggestion chips. Surfaces when the
// agent calls `ask_user` mid-loop and is paused waiting for the answer.
// ---------------------------------------------------------------------------

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
    final answered = widget.block.state == InputRequestState.answered;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: answered ? AppColors.softSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: answered ? AppColors.border : AppColors.accent,
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
                color: answered ? AppColors.textMuted : AppColors.ink,
              ),
              const SizedBox(width: 8),
              const Text(
                'AGENT NEEDS YOUR INPUT',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.block.question,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.4,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 12),
          if (answered)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                widget.block.answer ?? '',
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.ink,
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
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
              ),
              decoration: InputDecoration(
                hintText: 'Type your answer…',
                hintStyle: const TextStyle(
                  color: AppColors.textSoft,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppColors.softSurface,
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
                  color: AppColors.ink,
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
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

class _TextBlockView extends StatelessWidget {
  const _TextBlockView({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      text,
      style: const TextStyle(
        color: AppColors.ink,
        fontSize: 15.5,
        height: 1.6,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.05,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thinking — Claude-style inline disclosure. No card; just a tap-to-expand
// row with a dim left rule revealing italic chain-of-thought underneath.
// ---------------------------------------------------------------------------

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
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 16,
                      color: AppColors.textSoft,
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
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.content,
                      style: const TextStyle(
                        color: AppColors.textMuted,
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
    final base = Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
        letterSpacing: -0.1,
      ),
    );
    if (!active) return base;
    return base
        .animate(onPlay: repeatIfMotion(context))
        .shimmer(
          duration: 1600.ms,
          color: AppColors.ink.withValues(alpha: 0.55),
        );
  }
}

// ---------------------------------------------------------------------------
// Tool call — Claude-style inline status line. Running shows a small spinner
// + dim label; finished collapses to a checkmark + label and an optional
// italic result summary.
// ---------------------------------------------------------------------------

class ToolCallBlockView extends StatelessWidget {
  const ToolCallBlockView({super.key, required this.block});

  final ToolCallBlock block;

  @override
  Widget build(BuildContext context) {
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
                        color: AppColors.textMuted,
                      ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: running
                    ? _ShimmerText(text: block.label, active: true)
                    : Text(
                        block.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
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
                style: const TextStyle(
                  color: AppColors.textSoft,
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
    return Icon(
      Icons.refresh_rounded,
      size: 14,
      color: AppColors.textMuted.withValues(alpha: 0.85),
    )
        .animate(onPlay: repeatIfMotion(context))
        .rotate(duration: 900.ms, curve: Curves.linear);
  }
}

// ---------------------------------------------------------------------------
// Action proposal — accept / make changes
// ---------------------------------------------------------------------------

class ActionProposalView extends StatelessWidget {
  const ActionProposalView({super.key, required this.block});

  final ActionProposalBlock block;

  @override
  Widget build(BuildContext context) {
    final accepted = block.state == ActionState.accepted;
    final dismissed = block.state == ActionState.dismissed;
    final settled = accepted || dismissed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accepted ? AppColors.ink : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accepted ? AppColors.ink : AppColors.border,
        ),
        boxShadow: accepted
            ? [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.18),
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
                  color: accepted
                      ? AppColors.accent
                      : AppColors.softSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  block.icon,
                  size: 18,
                  color: AppColors.ink,
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
                        color: accepted ? Colors.white : AppColors.ink,
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
                            ? Colors.white.withValues(alpha: 0.78)
                            : AppColors.textMuted,
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
    return Row(
      children: [
        Icon(
          accepted ? Icons.check_circle_rounded : Icons.history_rounded,
          size: 14,
          color: accepted
              ? AppColors.accent
              : AppColors.textMuted,
        ),
        const SizedBox(width: 6),
        Text(
          accepted ? 'Accepted · running now' : 'Reverted — tell me how to adjust',
          style: TextStyle(
            color: accepted
                ? Colors.white.withValues(alpha: 0.88)
                : AppColors.textMuted,
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
    final bg = filled ? AppColors.ink : Colors.transparent;
    final fg = filled ? Colors.white : AppColors.ink;
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
              color: filled ? AppColors.ink : AppColors.border,
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

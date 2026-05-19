import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../../../core/utils/motion.dart';
import '../../models/agent_block.dart';
import '../../models/chat_message.dart';
import 'agent_block_views.dart';

/// Reasoning steps that render inside the vertical timeline rail (dot + line).
/// Plain text output and inline input requests render below the timeline.
bool _isTimelineStep(AgentBlock b) => b is ThinkingBlock || b is ToolCallBlock;

/// Action proposals are hoisted out of the turn into a docked island above
/// the input bar — see [AiChatbotPage]. Skip rendering them here.
bool _isDocked(AgentBlock b) => b is ActionProposalBlock;

class AgentTurnView extends StatelessWidget {
  const AgentTurnView({super.key, required this.turn});

  final AgentTurn turn;

  @override
  Widget build(BuildContext context) {
    final visible = turn.blocks.where((b) => !_isDocked(b)).toList();
    final timeline = visible.where(_isTimelineStep).toList();
    final output = visible.where((b) => !_isTimelineStep(b)).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 28, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (timeline.isNotEmpty)
            _ReasoningTimeline(
              steps: timeline,
              streaming: turn.isStreaming && output.isEmpty,
            ),
          if (output.isNotEmpty) ...[
            if (timeline.isNotEmpty) const SizedBox(height: 18),
            for (var i = 0; i < output.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              AgentBlockView(block: output[i])
                  .animate()
                  .fadeIn(duration: 220.ms)
                  .moveY(
                    begin: 6,
                    end: 0,
                    duration: 220.ms,
                    curve: Curves.easeOutCubic,
                  ),
            ],
          ],
          if (turn.isStreaming && timeline.isEmpty && output.isEmpty) ...[
            const SizedBox(height: 4),
            const _BouncingDots(),
          ],
        ],
      ),
    );
  }
}

/// Vertical rail of reasoning steps. Each step has a dot on the left and a
/// connecting line down to the next dot — Claude Code / Cursor agent style.
class _ReasoningTimeline extends StatelessWidget {
  const _ReasoningTimeline({required this.steps, required this.streaming});

  final List<AgentBlock> steps;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            step: steps[i],
            isFirst: i == 0,
            isLast: i == steps.length - 1 && !streaming,
            isActive: streaming && i == steps.length - 1,
          )
              .animate()
              .fadeIn(duration: 220.ms)
              .moveY(
                begin: 4,
                end: 0,
                duration: 220.ms,
                curve: Curves.easeOutCubic,
              ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.step,
    required this.isFirst,
    required this.isLast,
    required this.isActive,
  });

  final AgentBlock step;
  final bool isFirst;
  final bool isLast;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Rail column: 7px dot centered on a 2px vertical line.
          SizedBox(
            width: 18,
            child: Column(
              children: [
                SizedBox(
                  height: isFirst ? 6 : 0,
                  child: isFirst
                      ? const SizedBox.shrink()
                      : Center(
                          child: Container(width: 2, color: brand.border),
                        ),
                ),
                _TimelineDot(active: isActive),
                Expanded(
                  child: isLast
                      ? const SizedBox.shrink()
                      : Center(
                          child: Container(width: 2, color: brand.border),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TimelineStepBody(block: step, active: isActive),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final dot = Container(
      width: active ? 9 : 7,
      height: active ? 9 : 7,
      decoration: BoxDecoration(
        color: active ? brand.accent : brand.ink,
        shape: BoxShape.circle,
        border: active
            ? Border.all(color: brand.ink, width: 1.5)
            : null,
      ),
    );
    if (!active) return dot;
    return dot
        .animate(onPlay: repeatIfMotion(context, reverse: true))
        .scale(
          begin: const Offset(0.85, 0.85),
          end: const Offset(1.1, 1.1),
          duration: 900.ms,
          curve: Curves.easeInOut,
        );
  }
}

/// Renders a reasoning step's content with a consistent compact treatment so
/// the timeline reads as a uniform list rather than a stack of mixed cards.
class _TimelineStepBody extends StatelessWidget {
  const _TimelineStepBody({required this.block, required this.active});

  final AgentBlock block;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      ThinkingBlock(:final content) => _TimelineThinking(
          content: content,
          active: active,
        ),
      ToolCallBlock() => _TimelineToolCall(
          block: block as ToolCallBlock,
          active: active,
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Tool-call row stripped of its own status icon — the rail dot already
/// signals running/done state, so we just render the label + optional result.
class _TimelineToolCall extends StatelessWidget {
  const _TimelineToolCall({required this.block, required this.active});

  final ToolCallBlock block;
  final bool active;

  static final _fileRe = RegExp(
    r'\b[\w.\-]+\.(pdf|docx?|csv|json|md|txt)\b',
    caseSensitive: false,
  );

  List<String> _detectFiles() {
    final hits = <String>{};
    for (final m in _fileRe.allMatches(block.label)) {
      hits.add(m.group(0)!);
    }
    final summary = block.resultSummary;
    if (summary != null) {
      for (final m in _fileRe.allMatches(summary)) {
        hits.add(m.group(0)!);
      }
    }
    return hits.toList();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final files = _detectFiles();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToolNameChip(name: block.name, active: active),
        const SizedBox(height: 6),
        active
            ? _ThinkingLabel(text: block.label, active: true)
            : Text(
                block.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: brand.textMuted,
                  letterSpacing: -0.1,
                ),
              ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in files) _FileChip(name: f),
            ],
          ),
        ],
        if (block.resultSummary != null) ...[
          const SizedBox(height: 4),
          Text(
            block.resultSummary!,
            style: TextStyle(
              color: brand.textSoft,
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.italic,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }
}

/// Monospace-style pill showing the tool identifier (e.g. `analyze_resume`).
/// Active runs swap to an accent fill so the eye lands on the live tool.
class _ToolNameChip extends StatelessWidget {
  const _ToolNameChip({required this.name, required this.active});

  final String name;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final bg = active ? brand.accent : brand.surfaceMuted;
    final fg = active ? brand.onAccent : brand.ink;
    final border = active ? brand.accent : brand.border;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal_rounded,
            size: 11,
            color: fg.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Courier', 'Menlo'],
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline file reference chip — surfaces "which resume.pdf is the agent
/// touching" directly in the reasoning timeline.
class _FileChip extends StatelessWidget {
  const _FileChip({required this.name});

  final String name;

  IconData get _icon {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf_rounded,
      'doc' || 'docx' => Icons.description_rounded,
      'csv' => Icons.grid_on_rounded,
      'json' => Icons.data_object_rounded,
      'md' || 'txt' => Icons.notes_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
      decoration: BoxDecoration(
        color: brand.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: brand.accent.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 12, color: brand.ink),
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: brand.ink,
              letterSpacing: -0.1,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineThinking extends StatefulWidget {
  const _TimelineThinking({required this.content, required this.active});
  final String content;
  final bool active;

  @override
  State<_TimelineThinking> createState() => _TimelineThinkingState();
}

class _TimelineThinkingState extends State<_TimelineThinking> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ThinkingLabel(
                    text: widget.active ? 'Thinking…' : 'Thought for a moment',
                    active: widget.active,
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 180),
                    turns: _expanded ? 0.5 : 0,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 14,
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
            padding: const EdgeInsets.only(top: 6, right: 4),
            child: Text(
              widget.content,
              style: TextStyle(
                color: brand.textMuted,
                fontSize: 13,
                height: 1.55,
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
                letterSpacing: -0.05,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThinkingLabel extends StatelessWidget {
  const _ThinkingLabel({required this.text, required this.active});
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

class _BouncingDots extends StatelessWidget {
  const _BouncingDots();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Padding(
          padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: brand.textMuted.withValues(alpha: 0.55),
            ),
          )
              .animate(
                onPlay: repeatIfMotion(context),
                delay: (i * 180).ms,
              )
              .moveY(begin: 0, end: -3, duration: 380.ms, curve: Curves.easeOut)
              .then()
              .moveY(begin: -3, end: 0, duration: 380.ms, curve: Curves.easeIn),
        );
      }),
    );
  }
}

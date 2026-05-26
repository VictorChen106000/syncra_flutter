import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../../../core/utils/motion.dart';
import '../../../../shared/widgets/reasoning_gooey.dart';
import '../../models/agent_block.dart';
import '../../models/chat_message.dart';
import '../../state/agent_chat_notifier.dart';
import 'agent_block_views.dart';

/// Reasoning steps that render inside the vertical timeline rail (dot + line).
/// Plain text output and inline input requests render below the timeline.
bool _isTimelineStep(AgentBlock b) => b is ThinkingBlock || b is ToolCallBlock;

/// Blocks hoisted out of the turn into the docked island above the input bar
/// — see [AiChatbotPage]. Action proposals always dock; an input request
/// docks only while pending, then settles back inline as a Q&A record once
/// the user has answered.
bool _isDocked(AgentBlock b) =>
    b is ActionProposalBlock ||
    (b is InputRequestBlock && b.state == InputRequestState.pending);

/// One renderable chunk of a turn — see [AgentTurnView._segmentize].
sealed class _Segment {
  const _Segment();
}

/// A run of consecutive timeline steps (tool calls / thinking) drawn as one
/// vertical rail.
class _TimelineSegment extends _Segment {
  const _TimelineSegment(this.steps);
  final List<AgentBlock> steps;
}

/// A single non-timeline block (text / input request) drawn on its own.
class _OutputSegment extends _Segment {
  const _OutputSegment(this.block);
  final AgentBlock block;
}

class AgentTurnView extends StatelessWidget {
  const AgentTurnView({super.key, required this.turn});

  final AgentTurn turn;

  /// Returns the concatenated prose of a turn — used for the copy action.
  /// Tool calls / thinking / proposals are excluded; only [TextBlock] content
  /// makes it to the clipboard.
  static String plainTextOf(AgentTurn turn) {
    final buf = StringBuffer();
    for (final block in turn.blocks) {
      if (block is TextBlock) {
        if (buf.isNotEmpty) buf.write('\n\n');
        buf.write(block.text);
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final visible = turn.blocks.where((b) => !_isDocked(b)).toList();
    final segments = _segmentize(visible);
    final hasText = turn.blocks.any((b) => b is TextBlock);
    final lastIdx = segments.length - 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 28, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Blocks render in emission order; consecutive tool/thinking steps
          // collapse into one rail. A think → tool → text → tool turn now
          // reads chronologically instead of "all tools, then all text".
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0)
              SizedBox(
                height: (segments[i] is _TimelineSegment ||
                        segments[i - 1] is _TimelineSegment)
                    ? 18
                    : 14,
              ),
            _segmentView(
              segments[i],
              turnStreaming: turn.isStreaming,
              isLast: i == lastIdx,
            ),
          ],
          if (turn.isStreaming && segments.isEmpty) ...[
            const SizedBox(height: 8),
            const Center(child: ReasoningGooey()),
          ],
          if (turn.status == AgentTurnStatus.failed) ...[
            const SizedBox(height: 10),
            _TurnErrorBanner(
              message: turn.errorMessage ?? 'Something went wrong.',
            ),
          ],
          if (turn.status == AgentTurnStatus.stopped) ...[
            const SizedBox(height: 8),
            const _StoppedPill(),
          ],
          if (!turn.isStreaming && (hasText || turn.status == AgentTurnStatus.failed)) ...[
            const SizedBox(height: 10),
            _TurnActionRow(turn: turn),
          ],
        ],
      ),
    );
  }

  /// Groups [blocks] into ordered segments: runs of consecutive timeline
  /// steps (tool calls / thinking) become one [_TimelineSegment]; every other
  /// block becomes its own [_OutputSegment]. Preserves emission order.
  static List<_Segment> _segmentize(List<AgentBlock> blocks) {
    final segs = <_Segment>[];
    List<AgentBlock>? run;
    for (final b in blocks) {
      if (_isTimelineStep(b)) {
        (run ??= <AgentBlock>[]).add(b);
      } else {
        if (run != null) {
          segs.add(_TimelineSegment(run));
          run = null;
        }
        segs.add(_OutputSegment(b));
      }
    }
    if (run != null) segs.add(_TimelineSegment(run));
    return segs;
  }

  Widget _segmentView(
    _Segment seg, {
    required bool turnStreaming,
    required bool isLast,
  }) {
    switch (seg) {
      case _TimelineSegment(:final steps):
        return _ReasoningTimeline(
          // The rail only "streams" (pulsing last dot) when it's the final
          // segment — a rail followed by text is already settled.
          steps: steps,
          streaming: turnStreaming && isLast,
        );
      case _OutputSegment(:final block):
        return AgentBlockView(
          block: block,
          // Only the last block of a still-streaming turn types itself in.
          animateText: turnStreaming && isLast,
        )
            .animate()
            .fadeIn(duration: 220.ms)
            .moveY(
              begin: 6,
              end: 0,
              duration: 220.ms,
              curve: Curves.easeOutCubic,
            );
    }
  }
}

/// Inline error card that replaces the silent failure mode. Surfaces the
/// service's error message plus a Retry pill that re-runs the user prompt
/// that triggered this turn.
class _TurnErrorBanner extends ConsumerWidget {
  const _TurnErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: Colors.red.shade400,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: brand.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
                letterSpacing: -0.1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: brand.ink,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () =>
                  ref.read(agentChatProvider.notifier).regenerateLastTurn(),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.refresh_rounded,
                      size: 13,
                      color: brand.inkInverse,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Retry',
                      style: TextStyle(
                        color: brand.inkInverse,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle "Stopped by you" pill shown beneath a user-cancelled turn so the
/// transcript clearly distinguishes interrupted from completed turns.
class _StoppedPill extends StatelessWidget {
  const _StoppedPill();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: brand.surfaceMuted,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: brand.border, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stop_circle_rounded, size: 12, color: brand.textMuted),
              const SizedBox(width: 5),
              Text(
                'Stopped by you',
                style: TextStyle(
                  color: brand.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Copy + regenerate actions surfaced under a completed agent turn. Only the
/// most recent turn shows the regenerate affordance — re-running an older
/// turn would silently delete every turn that came after it.
class _TurnActionRow extends ConsumerWidget {
  const _TurnActionRow({required this.turn});

  final AgentTurn turn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(agentChatProvider);
    final isLatestTurn = _isLatestTurn(chat);
    final canRegenerate = isLatestTurn && !chat.isStreaming;
    return Row(
      children: [
        _TurnActionButton(
          icon: Icons.copy_rounded,
          tooltip: 'Copy response',
          onTap: () => _copy(context),
        ),
        if (canRegenerate) ...[
          const SizedBox(width: 4),
          _TurnActionButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Regenerate response',
            onTap: () =>
                ref.read(agentChatProvider.notifier).regenerateLastTurn(),
          ),
        ],
      ],
    );
  }

  bool _isLatestTurn(AgentChatState chat) {
    for (var i = chat.items.length - 1; i >= 0; i--) {
      final item = chat.items[i];
      if (item is AgentTurn) return item.id == turn.id;
    }
    return false;
  }

  Future<void> _copy(BuildContext context) async {
    final text = AgentTurnView.plainTextOf(turn);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
      ));
  }
}

class _TurnActionButton extends StatelessWidget {
  const _TurnActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Icon(icon, size: 15, color: brand.textMuted),
          ),
        ),
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
/// signals running/done state. Renders the label + optional result, and when
/// the call carries [ToolCallBlock.detail] it becomes tappable to reveal the
/// tool's inputs/outputs inline.
class _TimelineToolCall extends StatefulWidget {
  const _TimelineToolCall({required this.block, required this.active});

  final ToolCallBlock block;
  final bool active;

  @override
  State<_TimelineToolCall> createState() => _TimelineToolCallState();
}

class _TimelineToolCallState extends State<_TimelineToolCall> {
  bool _expanded = false;

  static final _fileRe = RegExp(
    r'\b[\w.\-]+\.(pdf|docx?|csv|json|md|txt)\b',
    caseSensitive: false,
  );

  List<String> _detectFiles() {
    final hits = <String>{};
    for (final m in _fileRe.allMatches(widget.block.label)) {
      hits.add(m.group(0)!);
    }
    final summary = widget.block.resultSummary;
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
    final block = widget.block;
    final active = widget.active;
    final files = _detectFiles();
    final detail = block.detail?.trim();
    final hasDetail = detail != null && detail.isNotEmpty;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolNameChip(name: block.name, active: active),
            // Chevron only when there's a drill-down to open.
            if (hasDetail) ...[
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
          ],
        ),
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
        if (hasDetail)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ToolDetailBox(text: detail),
            ),
          ),
      ],
    );

    if (!hasDetail) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(8),
        child: content,
      ),
    );
  }
}

/// Monospace drill-down panel showing a tool call's inputs/outputs.
class _ToolDetailBox extends StatelessWidget {
  const _ToolDetailBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: brand.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: brand.border, width: 0.6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Courier'],
          fontSize: 11.5,
          height: 1.5,
          letterSpacing: -0.1,
          color: brand.textMuted,
        ),
      ),
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


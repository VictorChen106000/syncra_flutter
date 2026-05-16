import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/app_colors.dart';
import '../../models/agent_block.dart';
import '../../models/chat_message.dart';
import 'agent_block_views.dart';

/// Inline status blocks (thinking + tool calls) flow tightly together;
/// text and action proposals need more breathing room.
double _gapBefore(List<AgentBlock> blocks, int i) {
  final prev = blocks[i - 1];
  final curr = blocks[i];
  final bothInline =
      _isInlineStatus(prev) && _isInlineStatus(curr);
  return bothInline ? 6 : 14;
}

bool _isInlineStatus(AgentBlock b) => b is ThinkingBlock || b is ToolCallBlock;

/// Renders one agent turn — a tiny Syncra mark followed by a vertical stack
/// of blocks. While the turn is streaming, a typing indicator sits at the end.
class AgentTurnView extends StatelessWidget {
  const AgentTurnView({super.key, required this.turn});

  final AgentTurn turn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(streaming: turn.isStreaming),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < turn.blocks.length; i++) ...[
                    if (i > 0) SizedBox(height: _gapBefore(turn.blocks, i)),
                    AgentBlockView(block: turn.blocks[i])
                        .animate()
                        .fadeIn(duration: 220.ms)
                        .moveY(
                          begin: 6,
                          end: 0,
                          duration: 220.ms,
                          curve: Curves.easeOutCubic,
                        ),
                  ],
                  if (turn.isStreaming) ...[
                    if (turn.blocks.isNotEmpty) const SizedBox(height: 14),
                    const _BouncingDots(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.streaming});
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.ink,
        shape: BoxShape.circle,
        boxShadow: streaming
            ? [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.auto_awesome_rounded,
        color: AppColors.accent,
        size: 14,
      ),
    );

    if (!streaming) return dot;
    return dot
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(
          begin: const Offset(1, 1),
          end: const Offset(1.06, 1.06),
          duration: 900.ms,
          curve: Curves.easeInOut,
        );
  }
}

class _BouncingDots extends StatelessWidget {
  const _BouncingDots();

  @override
  Widget build(BuildContext context) {
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
              color: AppColors.textMuted.withValues(alpha: 0.55),
            ),
          )
              .animate(
                onPlay: (c) => c.repeat(),
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

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_theme.dart';
import '../state/running_task_notifier.dart';
import 'gooey_orb.dart';

/// "The agent is thinking" indicator — a small [GooeyOrb] with a live tagline
/// pulled from [runningTaskProvider]. Used in place of a static spinner /
/// bouncing-dots indicator so reasoning states across the app share the same
/// visual language as the dashboard's empty-state hero orb.
///
/// The tagline tracks the running task's `label` (e.g. "Searching jobs…",
/// "Reading your resume…") so the user always sees *what* the agent is
/// working on, not just *that* it's working. Falls back to [fallbackLabel]
/// when no task is running — happens when the chat is mid-turn but the
/// agent hasn't called a tool yet.
class ReasoningGooey extends ConsumerWidget {
  const ReasoningGooey({
    super.key,
    this.size = 72,
    this.fallbackLabel = 'Reasoning…',
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  });

  /// Orb diameter. Defaults to a chat-inline size; pass ~120 for a hero
  /// reasoning surface (e.g. a future full-bleed loading state).
  final double size;

  /// Tagline used when [runningTaskProvider] has no active label.
  final String fallbackLabel;

  /// Outer padding around the gooey + tagline pair.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final taskLabel = ref.watch(
      runningTaskProvider.select((s) => s.label),
    );
    final label = taskLabel.trim().isEmpty ? fallbackLabel : taskLabel.trim();
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GooeyOrb(size: size),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: brand.textMuted,
              letterSpacing: -0.1,
            ),
          )
              .animate(
                onPlay: (c) => c.repeat(reverse: true),
                key: ValueKey(label),
              )
              .fadeIn(begin: 0.55, duration: 900.ms),
        ],
      ),
    );
  }
}

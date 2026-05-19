import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../core/utils/motion.dart';
import '../../../data/models/job.dart';
import '../../../fixtures/mock_agent_service.dart';
import '../models/agent_block.dart';
import '../models/chat_message.dart';
import '../state/agent_chat_notifier.dart';
import 'widgets/agent_turn_view.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_message_bubble.dart';

class AiChatbotPage extends ConsumerStatefulWidget {
  const AiChatbotPage({super.key});

  @override
  ConsumerState<AiChatbotPage> createState() => _AiChatbotPageState();
}

class _AiChatbotPageState extends ConsumerState<AiChatbotPage> {
  final ScrollController _scrollController = ScrollController();

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    ref.listen<AgentChatState>(
      agentChatProvider,
      (_, _) => _scheduleScrollToBottom(),
    );

    final state = ref.watch(agentChatProvider);
    final notifier = ref.read(agentChatProvider.notifier);

    final onlyInitial =
        state.items.length == 1 && state.items.first is AgentTurn;
    final stickyPrompt = _latestUserMessage(state.items);
    final pendingProposal = _pendingProposal(state.items);
    final transcriptForList = _transcriptExcludingStickyPrompt(
      state.items,
      stickyPrompt,
    );

    return Scaffold(
      backgroundColor: brand.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ChatHeader(isStreaming: state.isStreaming),
            if (state.threadJob != null)
              _ThreadContextChip(
                job: state.threadJob!,
                onClear: notifier.clearThread,
              ),
            if (stickyPrompt != null) _StickyUserPrompt(message: stickyPrompt),
            Expanded(
              child: onlyInitial && state.threadJob == null
                  ? _EmptyState(
                      onPromptTap: (text) =>
                          notifier.sendPrompt(prompt: text),
                    )
                  : ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                      children: [
                        for (final item in transcriptForList)
                          switch (item) {
                            UserMessage() => UserMessageView(message: item),
                            AgentTurn() => AgentTurnView(turn: item),
                          },
                      ],
                    ),
            ),
            if (pendingProposal != null)
              _DockedActionProposal(block: pendingProposal),
            const ChatInputBar(),
          ],
        ),
      ),
    );
  }

  /// The most recent [UserMessage] in the transcript, or null if none yet.
  static UserMessage? _latestUserMessage(List<ChatItem> items) {
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item is UserMessage) return item;
    }
    return null;
  }

  /// Pending action proposal hoisted from the latest agent turn into the
  /// docked island. Only the most recent unresolved proposal surfaces.
  static ActionProposalBlock? _pendingProposal(List<ChatItem> items) {
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item is! AgentTurn) continue;
      for (var j = item.blocks.length - 1; j >= 0; j--) {
        final block = item.blocks[j];
        if (block is ActionProposalBlock &&
            block.state == ActionState.pending) {
          return block;
        }
      }
    }
    return null;
  }

  /// Strip the sticky prompt from the in-list transcript so we don't render
  /// it twice. Everything else (older prompts, agent turns) still flows in
  /// chronological order in the scroll view.
  static List<ChatItem> _transcriptExcludingStickyPrompt(
    List<ChatItem> items,
    UserMessage? sticky,
  ) {
    if (sticky == null) return items;
    return [
      for (final item in items)
        if (!(item is UserMessage && item.id == sticky.id)) item,
    ];
  }
}

/// Pinned latest-prompt banner: gives the agent's reasoning timeline a
/// persistent "what you asked" header, Claude-Code style.
class _StickyUserPrompt extends StatelessWidget {
  const _StickyUserPrompt({required this.message});

  final UserMessage message;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: brand.surface,
        border: Border(
          bottom: BorderSide(color: brand.border, width: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 32,
            margin: const EdgeInsets.only(top: 2, right: 12),
            decoration: BoxDecoration(
              color: brand.ink,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOU ASKED',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    color: brand.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    letterSpacing: -0.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate(key: ValueKey(message.id)).fadeIn(duration: 220.ms).moveY(
          begin: -6,
          end: 0,
          duration: 220.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

/// Pending [ActionProposalBlock] hoisted out of the chat list into a docked
/// island above the input — feels like Claude Code's "Accept changes" pill.
class _DockedActionProposal extends ConsumerWidget {
  const _DockedActionProposal({required this.block});

  final ActionProposalBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final notifier = ref.read(agentChatProvider.notifier);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: brand.outline, width: 1),
        boxShadow: [
          BoxShadow(
            color: brand.shadow.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: brand.accent,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(block.icon, size: 14, color: brand.onAccent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: brand.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'PROPOSED CHANGE',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          color: brand.onAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      block.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: brand.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DockedActionButton(
                  label: block.editLabel,
                  filled: false,
                  onTap: () => notifier.dismissProposal(block.id),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DockedActionButton(
                  label: block.acceptLabel,
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
        .moveY(
          begin: 12,
          end: 0,
          duration: 220.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

class _DockedActionButton extends StatelessWidget {
  const _DockedActionButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final bg = filled ? brand.ink : Colors.transparent;
    final fg = filled ? brand.inkInverse : brand.ink;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: filled ? brand.ink : brand.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned chip below the header announcing the active job thread. Tap the
/// X to clear context and return to a generic chat.
class _ThreadContextChip extends StatelessWidget {
  const _ThreadContextChip({required this.job, required this.onClear});

  final Job job;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(
        color: brand.surfaceMuted,
        border: Border(
          bottom: BorderSide(color: brand.border, width: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: brand.ink,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              job.company[0],
              style: TextStyle(
                color: brand.accent,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'THREAD',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    color: brand.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${job.title} · ${job.company}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: brand.ink,
                    letterSpacing: -0.1,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            label: 'Close thread',
            button: true,
            child: InkResponse(
              onTap: onClear,
              radius: 24,
              excludeFromSemantics: true,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: brand.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.isStreaming});

  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
      decoration: BoxDecoration(
        color: brand.surface,
        border: Border(
          bottom: BorderSide(color: brand.border, width: 0.6),
        ),
      ),
      child: Row(
        children: [
          _IconBtn(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => context.go(RouteNames.dashboard),
          ),
          Expanded(
            child: Center(
              child: _UsageDynamicIsland(active: isStreaming),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

/// Compact "dynamic island"-style status pill that surfaces the active model
/// + a mock context-window percentage. Single source of truth for "which
/// model am I talking to and how much room is left."
class _UsageDynamicIsland extends StatelessWidget {
  const _UsageDynamicIsland({required this.active});
  final bool active;

  static const _modelLabel = 'Syncra Opus';
  static const _contextPercent = 32;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: brand.ink,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(active: active, color: brand.accent),
          const SizedBox(width: 8),
          Text(
            _modelLabel,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: brand.inkInverse,
              letterSpacing: -0.15,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 12,
            color: brand.inkInverse.withValues(alpha: 0.2),
          ),
          const SizedBox(width: 8),
          Text(
            '$_contextPercent% ctx',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: brand.inkInverse.withValues(alpha: 0.72),
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.active, required this.color});
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

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 18, color: brand.ink),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPromptTap});

  final void Function(String prompt) onPromptTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    const prompts = MockAgentService.dashboardPrompts;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
      children: [
        Center(
          child: SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: brand.accent.withValues(alpha: 0.18),
                  ),
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: brand.ink,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: brand.ink.withValues(alpha: 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: brand.accent,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
        )
            .animate()
            .fadeIn(duration: 380.ms)
            .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1)),
        const SizedBox(height: 22),
        Text(
          'How can I help today?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: brand.ink,
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ).animate(delay: 80.ms).fadeIn(duration: 380.ms).moveY(
              begin: 8,
              end: 0,
              duration: 380.ms,
              curve: Curves.easeOutCubic,
            ),
        const SizedBox(height: 8),
        Text(
          'Find roles, tailor resumes, or draft outreach — I can take it from here.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: brand.textMuted,
            height: 1.45,
          ),
        ).animate(delay: 160.ms).fadeIn(duration: 380.ms),
        const SizedBox(height: 36),
        for (var i = 0; i < prompts.length; i++) ...[
          _PromptCard(
            text: prompts[i],
            icon: _promptIcons[i % _promptIcons.length],
            onTap: () => onPromptTap(prompts[i]),
          )
              .animate(delay: (220 + i * 70).ms)
              .fadeIn(duration: 360.ms)
              .moveY(
                begin: 10,
                end: 0,
                duration: 360.ms,
                curve: Curves.easeOutCubic,
              ),
          if (i < prompts.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  static const List<IconData> _promptIcons = [
    Icons.travel_explore_rounded,
    Icons.auto_awesome_rounded,
    Icons.mail_outline_rounded,
    Icons.insights_rounded,
  ];
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.text,
    required this.icon,
    required this.onTap,
  });

  final String text;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.surfaceMuted,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: brand.border.withValues(alpha: 0.7)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: brand.border),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: brand.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: brand.ink,
                    letterSpacing: -0.15,
                    height: 1.35,
                  ),
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

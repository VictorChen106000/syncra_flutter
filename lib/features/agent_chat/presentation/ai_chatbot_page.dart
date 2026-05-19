import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../core/utils/motion.dart';
import '../../../fixtures/mock_agent_service.dart';
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

    return Scaffold(
      backgroundColor: brand.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ChatHeader(isStreaming: state.isStreaming),
            Expanded(
              child: onlyInitial
                  ? _EmptyState(
                      onPromptTap: (text) =>
                          notifier.sendPrompt(prompt: text),
                    )
                  : ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      children: [
                        for (final item in state.items)
                          switch (item) {
                            UserMessage() => UserMessageView(message: item),
                            AgentTurn() => AgentTurnView(turn: item),
                          },
                      ],
                    ),
            ),
            const ChatInputBar(),
          ],
        ),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: brand.ink,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: brand.accent,
                      size: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Syncra',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: brand.ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (isStreaming) ...[
                    const SizedBox(width: 10),
                    const _LiveDot(),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
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

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: brand.accentBright,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: brand.accentBright.withValues(alpha: 0.45),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    )
        .animate(onPlay: repeatIfMotion(context, reverse: true))
        .fadeIn(duration: 500.ms)
        .then()
        .fadeOut(duration: 500.ms);
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
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: brand.ink,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: brand.ink.withValues(alpha: 0.12),
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

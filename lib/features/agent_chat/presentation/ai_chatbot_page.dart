import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../shared/widgets/app_header.dart';
import '../models/chat_message.dart';
import '../state/agent_chat_controller.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_message_bubble.dart';

class AiChatbotPage extends StatefulWidget {
  const AiChatbotPage({super.key});

  @override
  State<AiChatbotPage> createState() => _AiChatbotPageState();
}

class _AiChatbotPageState extends State<AiChatbotPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.watch<AgentChatController>();
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _ChatHeader(),
            Expanded(
              child: Consumer<AgentChatController>(
                builder: (context, controller, _) {
                  return ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                    children: [
                      for (final message in controller.messages)
                        if (message.type == ChatMessageType.resultCards)
                          const _ResultCards()
                        else
                          ChatMessageBubble(message: message),
                      if (controller.isTyping) const _TypingBubble(),
                    ],
                  );
                },
              ),
            ),
            const _QuickReplies(),
            const ChatInputBar(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _ChatHeader extends StatelessWidget {
  const _ChatHeader();

  @override
  Widget build(BuildContext context) {
    return Consumer<AgentChatController>(
      builder: (context, controller, _) {
        return AppHeader.page(
          title: controller.isTyping
              ? AppStrings.chatTypingTitle
              : AppStrings.chatTitle,
          kicker: 'Syncra Agent',
          onBack: () => context.go(RouteNames.dashboard),
          trailing: _LiveDot(active: controller.isTyping),
        );
      },
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: active ? AppColors.accent : AppColors.border,
        shape: BoxShape.circle,
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.40),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
    )
        .animate(
          onPlay: active ? (c) => c.repeat(reverse: true) : null,
          autoPlay: active,
        )
        .fadeIn(duration: 400.ms)
        .then()
        .fadeOut(duration: 400.ms);
  }
}

// ---------------------------------------------------------------------------
// Quick replies
// ---------------------------------------------------------------------------

class _QuickReplies extends StatelessWidget {
  const _QuickReplies();

  @override
  Widget build(BuildContext context) {
    return Consumer<AgentChatController>(
      builder: (context, controller, _) {
        const replies = [
          'Find me a UX role at a startup & draft outreach',
          'Improve my resume',
          'Find internships',
        ];
        return SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            itemBuilder: (context, index) {
              final text = replies[index];
              return Material(
                color: Colors.white.withValues(alpha: 0.60),
                borderRadius: BorderRadius.circular(99),
                child: InkWell(
                  onTap: controller.isTyping
                      ? null
                      : () => controller.sendPrompt(prompt: text),
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: AppColors.ink,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          text,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            separatorBuilder: (context, _) => const SizedBox(width: 8),
            itemCount: replies.length,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Typing bubble
// ---------------------------------------------------------------------------

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.accent,
                  size: 12,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Syncra',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.only(left: 30, top: 4),
            child: _BouncingDots(),
          ),
        ],
      ),
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
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.textMuted.withValues(alpha: 0.6),
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

// ---------------------------------------------------------------------------
// Result cards (after agent reply)
// ---------------------------------------------------------------------------

class _ResultCards extends StatelessWidget {
  const _ResultCards();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 30, bottom: 28),
      child: Column(
        children: [
          _ResultCard(
            icon: Icons.description_rounded,
            title: 'Linear_UX_Resume_v4.pdf',
            badge: 'Tailored · 92% Match',
            trailing: Icons.search_rounded,
            onTap: () {},
          ),
          const SizedBox(height: 10),
          _ResultCard(
            icon: Icons.mail_outline_rounded,
            title: 'Draft: Linear Outreach',
            subtitle: 'Includes recent news context',
            trailing: Icons.chevron_right_rounded,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.title,
    this.subtitle,
    this.badge,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? badge;
  final IconData trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.scaffold,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppColors.ink, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.ink,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      badge ?? subtitle ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(trailing, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

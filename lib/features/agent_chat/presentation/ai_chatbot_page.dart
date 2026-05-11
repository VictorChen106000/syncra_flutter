import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../data/mock/mock_agent_steps.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../models/chat_message.dart';
import '../state/agent_chat_controller.dart';
import 'widgets/agent_terminal.dart';
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
      duration: const Duration(milliseconds: 260),
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
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                    children: [
                      ...controller.messages.map((message) {
                        if (message.type == ChatMessageType.terminal) {
                          return const AgentTerminal();
                        }
                        if (message.type == ChatMessageType.resultCards) {
                          return const _ResultCards();
                        }
                        return ChatMessageBubble(message: message);
                      }),
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

class _ChatHeader extends StatelessWidget {
  const _ChatHeader();

  @override
  Widget build(BuildContext context) {
    return Consumer<AgentChatController>(
      builder: (context, controller, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              AppBackButton(onPressed: () => context.go(RouteNames.dashboard)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity( 0.62),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Colors.white.withOpacity( 0.45)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 8,
                      backgroundColor: controller.isTyping ? AppColors.accent : AppColors.ink,
                      child: controller.isTyping ? null : const Icon(Icons.star_rounded, color: AppColors.accent, size: 10),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      controller.isTyping ? AppStrings.chatTypingTitle : AppStrings.chatTitle,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.settings_rounded, size: 20),
                style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity( 0.62)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickReplies extends StatelessWidget {
  const _QuickReplies();

  @override
  Widget build(BuildContext context) {
    return Consumer<AgentChatController>(
      builder: (context, controller, _) {
        return SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            itemBuilder: (context, index) {
              final text = MockAgentSteps.quickReplies[index];
              return ActionChip(
                onPressed: controller.isTyping ? null : () => controller.sendPrompt(prompt: text),
                avatar: const Icon(Icons.auto_awesome_rounded, size: 15),
                label: Text(text),
                backgroundColor: Colors.white.withOpacity( 0.62),
                side: const BorderSide(color: AppColors.border),
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              );
            },
            separatorBuilder: (context, _) => const SizedBox(width: 8),
            itemCount: MockAgentSteps.quickReplies.length,
          ),
        );
      },
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 14,
          backgroundColor: AppColors.ink,
          child: Icon(Icons.star_rounded, color: AppColors.accent, size: 15),
        ),
        const SizedBox(width: 9),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
          child: const _BouncingDots(),
        ),
      ],
    );
  }
}

class _BouncingDots extends StatefulWidget {
  const _BouncingDots();

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Animation<double> _offsetFor(int index) => TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 0, end: -5), weight: 25),
        TweenSequenceItem(tween: Tween(begin: -5, end: 0), weight: 25),
        TweenSequenceItem(tween: ConstantTween(0), weight: 50),
      ]).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(index * 0.18, index * 0.18 + 0.55, curve: Curves.easeInOut),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Padding(
            padding: EdgeInsets.only(right: i < 2 ? 5 : 0),
            child: Transform.translate(
              offset: Offset(0, _offsetFor(i).value),
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.ink,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ResultCards extends StatelessWidget {
  const _ResultCards();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 38, bottom: 18),
      child: Column(
        children: [
          _ResultCard(
            icon: Icons.description_rounded,
            title: 'Linear_UX_Resume_v4.pdf',
            subtitle: 'Tailored • 92% Match',
            subtitleBadge: true,
            trailing: Icons.search_rounded,
          ),
          const SizedBox(height: 10),
          _ResultCard(
            icon: Icons.mail_outline_rounded,
            title: 'Draft: Linear Outreach',
            subtitle: 'Includes recent news context',
            trailing: Icons.chevron_right_rounded,
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
    required this.subtitle,
    required this.trailing,
    this.subtitleBadge = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final IconData trailing;
  final bool subtitleBadge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.ink,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              subtitleBadge
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(subtitle, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    )
                  : Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ]),
          ),
          Icon(trailing, size: 20),
        ],
      ),
    );
  }
}

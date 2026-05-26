import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/dev/dev_flags_notifier.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../agent_chat/models/agent_block.dart';
import '../../agent_chat/models/chat_message.dart';
import '../../agent_chat/presentation/widgets/agent_turn_view.dart';
import '../../agent_chat/presentation/widgets/chat_input_bar.dart';
import '../../agent_chat/presentation/widgets/chat_message_bubble.dart';
import '../../agent_chat/presentation/widgets/docked_panels.dart';
import '../../agent_chat/state/agent_chat_mode.dart';
import '../../agent_chat/state/agent_chat_notifier.dart';
import '../state/auth_notifier.dart';
import '../state/user_profile_notifier.dart';

/// First-run setup. Replaces the static scripted intro with a real
/// agent-driven conversation: the Anthropic-backed chatbot (in
/// [AgentChatMode.onboarding] mode) greets the user, calls `ask_user` to
/// capture their target role, then calls `complete_onboarding` — which surfaces
/// an "Enter Syncra" CTA card the user taps to land on the dashboard.
///
/// The visual scaffold is borrowed from [AiChatbotPage] (full-bleed
/// transcript behind frosted top chrome, docked input request above the
/// composer) so the onboarding moment is visually the same surface the user
/// will live in afterwards.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Flip the shared chat infrastructure into onboarding mode. The provider
    // rebuilds the AnthropicChatService with the onboarding system prompt +
    // a minimal tool registry, and the notifier seeds a personalised opener.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(agentChatModeProvider.notifier).set(AgentChatMode.onboarding);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // Return the chat to normal mode so that whichever surface opens the
    // chatbot next (dashboard "Ask Syncra", a job thread, etc.) gets the
    // full job arsenal — not the stripped-down onboarding sandbox.
    // ref.read is safe in dispose for providers that don't depend on the
    // disposed widget's state.
    Future.microtask(() {
      ref.read(agentChatModeProvider.notifier).set(AgentChatMode.jobs);
    });
    super.dispose();
  }

  /// Bypasses the agent-driven role capture and routes straight to the
  /// dashboard. Writes a neutral placeholder role so the router redirect
  /// doesn't immediately bounce the user back to `/onboarding` (the redirect
  /// fires whenever `role` is empty), and clears the dev "Show onboarding"
  /// toggle if it was the reason the user landed here. The user can edit the
  /// placeholder from Profile later.
  Future<void> _skipToDashboard() async {
    await ref
        .read(userProfileProvider.notifier)
        .setRole('Exploring opportunities');
    final dev = ref.read(devFlagsProvider);
    if (dev.showOnboarding) {
      await ref.read(devFlagsProvider.notifier).setShowOnboarding(false);
    }
    if (!mounted) return;
    context.go(RouteNames.dashboard);
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    ref.listen<AgentChatState>(
      agentChatProvider,
      (_, _) => _scheduleScrollToBottom(),
    );

    final state = ref.watch(agentChatProvider);
    final pendingInput = _pendingInputRequest(state.items);

    final media = MediaQuery.of(context);
    final topSafe = media.padding.top;
    final topInset = topSafe + 56;
    double bottomInset = media.padding.bottom + 152;
    if (pendingInput != null) bottomInset += 132;

    return Scaffold(
      backgroundColor: brand.surface,
      body: Stack(
        children: [
          // Full-bleed transcript — scrolls behind the floating chrome.
          Positioned.fill(
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(20, topInset, 20, bottomInset),
              children: [
                for (final item in state.items)
                  switch (item) {
                    UserMessage() => UserMessageView(message: item),
                    AgentTurn() => AgentTurnView(turn: item),
                  },
              ],
            ),
          ),

          // Top fade scrim — keeps the back/skip button legible over the chat.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topSafe + 60,
            child: IgnorePointer(child: _FadeScrim(brand: brand, top: true)),
          ),

          // Bottom fade scrim — softens the transcript into the composer.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: bottomInset,
            child: IgnorePointer(child: _FadeScrim(brand: brand, top: false)),
          ),

          // Floating top chrome: just a sign-out escape hatch and a "Setup"
          // chip. No history drawer, no new-chat button, no thread context.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    _FrostedIconBtn(
                      icon: Icons.arrow_back_ios_new_rounded,
                      tooltip: 'Sign out',
                      onTap: () =>
                          ref.read(authProvider.notifier).signOut(),
                    ),
                    const Spacer(),
                    const _SetupChip(),
                    const Spacer(),
                    _SkipButton(onTap: _skipToDashboard),
                  ],
                ),
              ),
            ),
          ),

          // Floating bottom chrome: the docked input request (when the agent
          // has paused for `ask_user`) plus the standard ChatInputBar. No
          // resume attachment chrome is shown — onboarding has no resume yet.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pendingInput != null) DockedInputRequest(block: pendingInput),
                const ChatInputBar(autofocus: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Pending `ask_user` request hoisted from the latest agent turn into the
  /// docked island. Only the most recent unanswered question surfaces.
  static InputRequestBlock? _pendingInputRequest(List<ChatItem> items) {
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item is! AgentTurn) continue;
      for (var j = item.blocks.length - 1; j >= 0; j--) {
        final block = item.blocks[j];
        if (block is InputRequestBlock &&
            block.state == InputRequestState.pending) {
          return block;
        }
      }
    }
    return null;
  }
}

/// Tiny pill that telegraphs the user is in first-run setup, not the regular
/// chat. Visually echoes the chatbot's frosted top chrome but stays in the
/// dead-centre so it reads as a status label, not a back action.
class _SetupChip extends StatelessWidget {
  const _SetupChip();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: brand.surface.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: brand.border, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: brand.ink,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.star_rounded, color: brand.accent, size: 10),
              ),
              const SizedBox(width: 8),
              Text(
                'Syncra AI Setup',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: brand.ink,
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

/// Frosted circular icon button — mirrors the chatbot's floating header
/// controls so the back-out / sign-out affordance feels native to the
/// chat-surface aesthetic.
class _FrostedIconBtn extends StatelessWidget {
  const _FrostedIconBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final button = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: brand.shadow.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            color: brand.surface.withValues(alpha: 0.78),
            shape: CircleBorder(
              side: BorderSide(color: brand.border, width: 0.8),
            ),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(icon, size: 18, color: brand.ink),
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Quiet text pill in the top-right that bypasses the agent role-capture and
/// drops the user on the dashboard with a placeholder role. Mostly a dev /
/// "I'll fill this in later" escape hatch — visually subdued so it doesn't
/// compete with the conversation.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: brand.surface.withValues(alpha: 0.78),
          shape: StadiumBorder(
            side: BorderSide(color: brand.border, width: 0.8),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: brand.textMuted,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: brand.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft gradient that fades the transcript into the background behind the
/// floating chrome, copied from the chatbot scaffold so the visual treatment
/// matches one-for-one.
class _FadeScrim extends StatelessWidget {
  const _FadeScrim({required this.brand, required this.top});

  final BrandTheme brand;
  final bool top;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [
            brand.surface,
            brand.surface.withValues(alpha: 0.0),
          ],
          stops: const [0.55, 1.0],
        ),
      ),
    );
  }
}

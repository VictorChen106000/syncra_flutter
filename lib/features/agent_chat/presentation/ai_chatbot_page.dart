import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/brand_theme.dart';
import '../../../core/utils/file_formatter.dart';
import '../../../data/models/job.dart';
import '../../../shared/widgets/gooey_orb.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/firestore/pipeline_repository.dart';
import '../../jobs/state/jobs_notifier.dart';
import '../../resumes/models/resume_file.dart';
import '../../resumes/presentation/widgets/select_resumes_bottom_sheet.dart';
import '../../resumes/state/resume_notifier.dart';
import '../agent_prompt_suggestions.dart';
import '../models/agent_block.dart';
import '../models/chat_message.dart';
import '../state/agent_chat_notifier.dart';
import 'widgets/agent_turn_view.dart';
import 'widgets/chat_history_drawer.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/docked_panels.dart';

class AiChatbotPage extends ConsumerStatefulWidget {
  const AiChatbotPage({super.key, this.autofocusComposer = false});

  /// When true, the chat composer grabs focus on open — set when the user
  /// arrives by tapping the dashboard's "Ask Syncra" bar.
  final bool autofocusComposer;

  @override
  ConsumerState<AiChatbotPage> createState() => _AiChatbotPageState();
}

class _AiChatbotPageState extends ConsumerState<AiChatbotPage> {
  final ScrollController _scrollController = ScrollController();
  bool _showJumpToLatest = false;

  /// Within this many pixels of the bottom we consider the user "pinned" and
  /// auto-scroll new content into view. Beyond it we leave them alone and
  /// surface the jump-to-latest FAB instead.
  static const double _stickyThreshold = 80;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final distance = pos.maxScrollExtent - pos.pixels;
    final shouldShow = distance > _stickyThreshold;
    if (shouldShow != _showJumpToLatest) {
      setState(() => _showJumpToLatest = shouldShow);
    }
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      // Only auto-follow when the user is already near the bottom. If they've
      // scrolled up to read, respect that and let the FAB do the work.
      final pos = _scrollController.position;
      if (pos.maxScrollExtent - pos.pixels > _stickyThreshold) return;
      _scrollToBottom();
    });
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
    _scrollController.removeListener(_onScroll);
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
    final hasAttachedResume = ref.watch(
      resumeProvider.select((s) => s.selectedResumes.isNotEmpty),
    );

    final onlyInitial =
        state.items.length == 1 && state.items.first is AgentTurn;
    final stickyPrompt = _latestUserMessage(state.items);
    final pendingProposal = _pendingProposal(state.items);
    final pendingInput = _pendingInputRequest(state.items);
    final transcriptForList = _transcriptExcludingStickyPrompt(
      state.items,
      stickyPrompt,
    );

    final media = MediaQuery.of(context);
    final topSafe = media.padding.top;
    final showEmpty = onlyInitial && state.threadJob == null;

    // Reserved scroll insets so the transcript clears the floating chrome.
    // Slight overlap under the frosted bars is intentional — that's the
    // "chat seen through the controls" effect.
    double topInset = topSafe + 56;
    if (state.threadJob != null) topInset += 58;
    // The resume card only surfaces once the chat is underway — until then
    // the attached resume previews inside the composer instead.
    if (hasAttachedResume && stickyPrompt != null) topInset += 58;
    if (stickyPrompt != null) topInset += 80;
    double bottomInset = media.padding.bottom + 152;
    // A docked panel sits above the composer — give the transcript extra
    // clearance so the last message isn't buried behind it.
    if (pendingInput != null || pendingProposal != null) bottomInset += 132;

    return Scaffold(
      backgroundColor: brand.surface,
      drawer: const ChatHistoryDrawer(),
      body: Stack(
        children: [
          // Full-bleed transcript — scrolls behind the floating chrome.
          Positioned.fill(
            child: showEmpty
                ? _EmptyState(
                    topInset: topInset,
                    bottomInset: bottomInset,
                    onPromptTap: (text) => notifier.sendPrompt(prompt: text),
                  )
                : ListView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(20, topInset, 20, bottomInset),
                    children: [
                      if (state.threadJob != null &&
                          !state.items.any((i) => i is UserMessage))
                        _ThreadHero(job: state.threadJob!),
                      for (final item in transcriptForList)
                        switch (item) {
                          UserMessage() => UserMessageView(message: item),
                          AgentTurn() => AgentTurnView(turn: item),
                        },
                    ],
                  ),
          ),

          // Top fade scrim keeps the status bar + floating buttons legible.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topSafe + 60,
            child: IgnorePointer(child: _FadeScrim(brand: brand, top: true)),
          ),

          // Bottom fade scrim softens the transcript into the composer.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: bottomInset,
            child: IgnorePointer(child: _FadeScrim(brand: brand, top: false)),
          ),

          // Floating top chrome: header buttons + optional thread chip +
          // optional sticky prompt.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _FloatingTop(
              isStreaming: state.isStreaming,
              threadJob: state.threadJob,
              stickyPrompt: stickyPrompt,
              onClearThread: notifier.newConversation,
            ),
          ),

          // Jump-to-latest pill — sits just above the floating composer.
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset - 12,
            child: IgnorePointer(
              ignoring: !_showJumpToLatest,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _showJumpToLatest ? 1 : 0,
                child: Center(
                  child: _JumpToLatestButton(onTap: _scrollToBottom),
                ),
              ),
            ),
          ),

          // Floating bottom chrome: a single docked panel — whatever the
          // agent needs from the user — sits directly above the composer.
          // An unanswered question outranks a proposal: it blocks the loop.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pendingInput != null)
                  DockedInputRequest(block: pendingInput)
                else if (pendingProposal != null)
                  DockedActionProposal(block: pendingProposal),
                ChatInputBar(autofocus: widget.autofocusComposer),
              ],
            ),
          ),
        ],
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
    return _FrostedCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
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
      ),
    ).animate(key: ValueKey(message.id)).fadeIn(duration: 220.ms).moveY(
          begin: -6,
          end: 0,
          duration: 220.ms,
          curve: Curves.easeOutCubic,
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
    return _FrostedCard(
      child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
              job.company.isNotEmpty ? job.company[0] : '?',
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
      ),
    );
  }
}

/// Pinned chip below the header announcing which resume(s) Syncra has in
/// context for the chat — the user's signal that the agent is working from
/// their actual resume. Tap the body to swap resumes; tap the X to detach.
class _ResumeContextChip extends ConsumerWidget {
  const _ResumeContextChip({required this.resumes});

  final List<ResumeFile> resumes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final isSingle = resumes.length == 1;
    final title = isSingle
        ? FileFormatter.cleanName(resumes.first.name)
        : '${resumes.length} resumes attached';
    return _FrostedCard(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_FrostedCard.radius),
        child: InkWell(
          onTap: () => SelectResumesBottomSheet.show(context),
          borderRadius: BorderRadius.circular(_FrostedCard.radius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
                  child: Icon(
                    Icons.description_rounded,
                    size: 15,
                    color: brand.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'RESUME IN USE',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          color: brand.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
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
                  label: 'Detach resume',
                  button: true,
                  child: InkResponse(
                    onTap: () => ref
                        .read(resumeProvider.notifier)
                        .clearSelectedResumes(),
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
          ),
        ),
      ),
    );
  }
}

/// Floating top chrome over the full-bleed transcript: a back button and a
/// new-chat button (frosted circles), plus the optional thread chip and
/// sticky prompt as frosted cards. No solid bar — the chat scrolls behind it.
class _FloatingTop extends ConsumerWidget {
  const _FloatingTop({
    required this.isStreaming,
    required this.threadJob,
    required this.stickyPrompt,
    required this.onClearThread,
  });

  final bool isStreaming;
  final Job? threadJob;
  final UserMessage? stickyPrompt;
  final VoidCallback onClearThread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasHistory = ref.watch(
      agentChatProvider.select(
        (s) => s.items.length > 1 || s.threadJob != null,
      ),
    );
    final attachedResumes = ref.watch(resumeProvider).selectedResumes;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                _IconBtn(
                  icon: Icons.menu_rounded,
                  tooltip: 'Menu',
                  onTap: () => Scaffold.of(context).openDrawer(),
                ),
                const Spacer(),
                if (hasHistory && !isStreaming)
                  _IconBtn(
                    icon: Icons.edit_square,
                    tooltip: 'New chat',
                    onTap: () => ref
                        .read(agentChatProvider.notifier)
                        .newConversation(),
                  ),
              ],
            ),
          ),
          if (threadJob != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _ThreadContextChip(
                job: threadJob!,
                onClear: onClearThread,
              ),
            ),
          if (attachedResumes.isNotEmpty && stickyPrompt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _ResumeContextChip(resumes: attachedResumes),
            ),
          if (stickyPrompt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _StickyUserPrompt(message: stickyPrompt!),
            ),
        ],
      ),
    );
  }

}

/// Soft gradient that fades the transcript into the background behind the
/// floating chrome so scrolled content never hard-clips against a button.
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

/// Frosted-glass container — translucent + blurred so the transcript stays
/// faintly visible through the floating cards.
class _FrostedCard extends StatelessWidget {
  const _FrostedCard({required this.child});

  final Widget child;

  static const double radius = 16;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: brand.shadow.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: brand.surface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: brand.border, width: 0.8),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Frosted circular icon button used for the floating header controls.
class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final enabled = onTap != null;
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
                child: Icon(
                  icon,
                  size: 18,
                  color: enabled ? brand.ink : brand.textSoft,
                ),
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

/// Scene-setting card shown at the top of a brand-new threaded chat (a
/// thread opened from a pipeline card with no user messages yet). Once the
/// user replies, this disappears and the conversation flows as normal.
class _ThreadHero extends StatelessWidget {
  const _ThreadHero({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: brand.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: brand.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: brand.ink,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  job.company.isNotEmpty ? job.company[0] : '?',
                  style: TextStyle(
                    color: brand.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: brand.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${job.company} · ${job.location}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: brand.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: brand.accent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${job.matchScore}% match',
                  style: TextStyle(
                    color: brand.onAccent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            job.why.isNotEmpty ? job.why : job.agentJustification,
            style: TextStyle(
              color: brand.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.5,
              letterSpacing: -0.05,
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating "scroll to latest" pill that appears when the user has scrolled
/// up far enough that auto-follow is suppressed.
class _JumpToLatestButton extends StatelessWidget {
  const _JumpToLatestButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.ink,
      shape: const StadiumBorder(),
      elevation: 4,
      shadowColor: brand.shadow.withValues(alpha: 0.35),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_downward_rounded,
                size: 14,
                color: brand.inkInverse,
              ),
              const SizedBox(width: 6),
              Text(
                'Jump to latest',
                style: TextStyle(
                  color: brand.inkInverse,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
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

/// Chat empty state — when the agent has surfaced any pipeline items we
/// show them as an inbox (Needs you · Sent today) so the user lands on the
/// agent's work. With nothing pending we fall back to the gooey-orb prompt
/// suggestions so the agent still feels approachable for fresh queries.
class _EmptyState extends ConsumerWidget {
  const _EmptyState({
    required this.onPromptTap,
    required this.topInset,
    required this.bottomInset,
  });

  final void Function(String prompt) onPromptTap;
  final double topInset;
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobsProvider);
    final visible = jobs.pendingCards
        .where((c) => !jobs.isDismissed(c.job.id))
        .toList();

    if (visible.isEmpty) {
      return _OrbEmptyState(
        topInset: topInset,
        bottomInset: bottomInset,
        onPromptTap: onPromptTap,
      );
    }

    return _InboxEmptyState(
      cards: visible,
      topInset: topInset,
      bottomInset: bottomInset,
    );
  }
}

/// Inbox of the agent's pending pipeline work. Tap a row → opens that job
/// as a thread in the chat itself — no separate page.
class _InboxEmptyState extends ConsumerWidget {
  const _InboxEmptyState({
    required this.cards,
    required this.topInset,
    required this.bottomInset,
  });

  final List<PipelineCard> cards;
  final double topInset;
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final needs = cards
        .where((c) =>
            c.job.category == JobCategory.inputNeeded ||
            c.job.category == JobCategory.exploration)
        .toList();
    final sent = cards
        .where((c) => c.job.category == JobCategory.ready)
        .toList();

    void open(Job job) {
      ref.read(agentChatProvider.notifier).openJobThread(job);
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, bottomInset + 12),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 14),
          child: Text(
            sent.isEmpty && needs.isEmpty
                ? 'Quiet for now'
                : [
                    if (sent.isNotEmpty) '${sent.length} sent today',
                    if (needs.isNotEmpty) '${needs.length} need you',
                  ].join(' · '),
            style: TextStyle(
              color: brand.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
        if (needs.isNotEmpty) ...[
          _InboxSectionHeader(
            label: 'Needs you',
            count: needs.length,
            accent: AppColors.categoryInputDeep,
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < needs.length; i++)
            _InboxNeedsRow(
              card: needs[i],
              onTap: () => open(needs[i].job),
            )
                .animate(delay: (i * 50).ms)
                .fadeIn(duration: 280.ms)
                .moveY(begin: 8, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 18),
        ],
        if (sent.isNotEmpty) ...[
          _InboxSectionHeader(
            label: 'Sent today',
            count: sent.length,
            accent: brand.accent,
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(18),
              border:
                  Border.all(color: brand.border.withValues(alpha: 0.60)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < sent.length; i++) ...[
                  _InboxSentRow(
                    card: sent[i],
                    onTap: () => open(sent[i].job),
                  ),
                  if (i < sent.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: brand.border.withValues(alpha: 0.55),
                    ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _InboxSectionHeader extends StatelessWidget {
  const _InboxSectionHeader({
    required this.label,
    required this.count,
    required this.accent,
  });

  final String label;
  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
              color: brand.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: brand.surfaceMuted,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: brand.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxNeedsRow extends StatelessWidget {
  const _InboxNeedsRow({required this.card, required this.onTap});

  final PipelineCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final job = card.job;
    final accent = job.category == JobCategory.exploration
        ? AppColors.categoryExploreDeep
        : AppColors.categoryInputDeep;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.border.withValues(alpha: 0.60)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: Container(color: accent),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: brand.ink,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        job.company.isNotEmpty ? job.company[0] : '?',
                        style: TextStyle(
                          color: brand.accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            job.agentAction.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.3,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            job.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: brand.ink,
                              letterSpacing: -0.15,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            job.company,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: brand.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 16,
                      color: brand.textMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxSentRow extends StatelessWidget {
  const _InboxSentRow({required this.card, required this.onTap});

  final PipelineCard card;
  final VoidCallback onTap;

  String _timeLabel() {
    final now = DateTime.now();
    final delta = now.difference(card.createdAt);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    final hh = card.createdAt.hour.toString().padLeft(2, '0');
    final mm = card.createdAt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final job = card.job;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: brand.ink,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  job.company.isNotEmpty ? job.company[0] : '?',
                  style: TextStyle(
                    color: brand.accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 13,
                          color: brand.accentBright,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'SENT · ${_timeLabel()}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                            color: brand.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      job.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: brand.ink,
                        letterSpacing: -0.1,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      job.company,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: brand.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The original gooey-orb + prompt-cards empty state. Now reserved for the
/// truly-empty case (no pipeline yet) so the agent still feels alive when
/// there's nothing in the inbox.
class _OrbEmptyState extends StatelessWidget {
  const _OrbEmptyState({
    required this.onPromptTap,
    required this.topInset,
    required this.bottomInset,
  });

  final void Function(String prompt) onPromptTap;
  final double topInset;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    const prompts = AgentPromptSuggestions.all;

    return ListView(
      padding: EdgeInsets.fromLTRB(24, topInset + 12, 24, bottomInset + 12),
      children: [
        Center(
          child: const GooeyOrb(size: 116),
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

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/dev/dev_flags_notifier.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../../shared/widgets/glass_pill.dart';
import '../state/auth_notifier.dart';
import '../state/user_profile_notifier.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final TextEditingController _roleController = TextEditingController();
  final FocusNode _roleFocus = FocusNode();
  bool _submitted = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(userProfileProvider)?.role;
    if (existing != null && existing.isNotEmpty) {
      _roleController.text = existing;
      _submitted = true;
    }
    _roleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _roleController.dispose();
    _roleFocus.dispose();
    super.dispose();
  }

  bool get _hasValidRole => _roleController.text.trim().isNotEmpty;

  Future<void> _saveAndContinue() async {
    final role = _roleController.text.trim();
    if (role.isEmpty || _saving) return;

    setState(() => _saving = true);
    _roleFocus.unfocus();

    await ref.read(userProfileProvider.notifier).setRole(role);

    if (!mounted) return;
    setState(() {
      _submitted = true;
      _saving = false;
    });

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    // Auto-clear the dev "Show onboarding" toggle so the redirect doesn't
    // bounce the user straight back here.
    final dev = ref.read(devFlagsProvider);
    if (dev.showOnboarding) {
      await ref.read(devFlagsProvider.notifier).setShowOnboarding(false);
    }
    if (!mounted) return;
    context.go(RouteNames.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final displayName = ref.watch(authProvider).appUser?.displayName;
    final firstName = (displayName?.split(' ').first ?? '').isEmpty
        ? null
        : displayName!.split(' ').first;

    return Scaffold(
      backgroundColor: brand.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              decoration: BoxDecoration(
                color: brand.bg,
                border: Border(
                  bottom: BorderSide(
                    color: brand.border.withValues(alpha: 0.50),
                  ),
                ),
              ),
              child: Row(
                children: [
                  AppBackButton(
                    onPressed: () =>
                        ref.read(authProvider.notifier).signOut(),
                  ),
                  const Spacer(),
                  GlassPill(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _MiniStarChip(),
                        const SizedBox(width: 8),
                        Text(
                          AppStrings.onboardingHeader,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: brand.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 28),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                children: [
                  _AiMessage(
                    text:
                        "Hi${firstName == null ? '' : ' $firstName'}! I'm Syncra AI. "
                        "Let's set up your career profile. Could you upload your latest resume?",
                  ).animate().fadeIn().moveY(begin: 8, end: 0),
                  const SizedBox(height: 16),
                  _UserMessage(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_rounded,
                            color: brand.accent, size: 16),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'chris_anderson_resume.pdf',
                            style: TextStyle(
                              color: brand.inkInverse,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate(delay: 200.ms).fadeIn().moveY(begin: 8, end: 0),
                  const SizedBox(height: 16),
                  const _AgentTerminalBlock()
                      .animate(delay: 400.ms)
                      .fadeIn(duration: 500.ms),
                  const SizedBox(height: 16),
                  const _AiMessage(
                    text:
                        'I successfully extracted your skills! To calibrate my matching engine, what specific role are you aiming for?',
                  ).animate(delay: 700.ms).fadeIn().moveY(begin: 8, end: 0),
                  const SizedBox(height: 16),
                  if (_submitted)
                    _UserMessage(
                      child: Text(
                        _roleController.text.trim(),
                        style: TextStyle(
                          color: brand.inkInverse,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ).animate().fadeIn().moveY(begin: 8, end: 0)
                  else
                    _RoleInput(
                      controller: _roleController,
                      focusNode: _roleFocus,
                      onSubmitted: _saveAndContinue,
                    ).animate(delay: 850.ms).fadeIn().moveY(begin: 8, end: 0),
                  if (_submitted) ...[
                    const SizedBox(height: 16),
                    const _AiMessage(
                      text:
                          "Got it! Your AI profile is ready. I'll start finding matches in the background.",
                    ).animate().fadeIn().moveY(begin: 8, end: 0),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      (_hasValidRole && !_saving) ? _saveAndContinue : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: brand.ink,
                    foregroundColor: brand.inkInverse,
                    disabledBackgroundColor: brand.border,
                    disabledForegroundColor: brand.textMuted,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_saving)
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: brand.inkInverse,
                          ),
                        )
                      else
                        Text(
                          _submitted
                              ? AppStrings.goToDashboard
                              : 'Save & continue',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      if (!_saving) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ],
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

class _RoleInput extends StatelessWidget {
  const _RoleInput({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.82,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: brand.ink,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomLeft: Radius.circular(22),
                bottomRight: Radius.circular(4),
              ),
              border: Border.all(
                color: brand.inkInverse.withValues(alpha: 0.15),
              ),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmitted(),
              style: TextStyle(
                color: brand.inkInverse,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. Senior UX Designer at AI startups',
                hintStyle: TextStyle(
                  color: brand.inkInverse.withValues(alpha: 0.54),
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniStarChip extends StatelessWidget {
  const _MiniStarChip();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: brand.ink,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(Icons.star_rounded, color: brand.accent, size: 10),
    );
  }
}

class _AiMessage extends StatelessWidget {
  const _AiMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: brand.ink,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(Icons.star_rounded, color: brand.accent, size: 14),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(22),
              ),
              boxShadow: [
                BoxShadow(
                  color: brand.shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              text,
              style: TextStyle(
                color: brand.ink,
                fontSize: 14.5,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: brand.ink,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomLeft: Radius.circular(22),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _AgentTerminalBlock extends StatelessWidget {
  const _AgentTerminalBlock();

  @override
  Widget build(BuildContext context) {
    // Terminal block is intentionally dark in both themes (it's a "monitor"
    // visual). Pin to BrandTheme.dark colors directly.
    const brand = BrandTheme.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: brand.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: brand.ink.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  brand.accent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _TerminalDot(color: brand.danger),
                    const SizedBox(width: 6),
                    _TerminalDot(color: brand.warning),
                    const SizedBox(width: 6),
                    _TerminalDot(color: brand.success),
                    const SizedBox(width: 10),
                    Text(
                      'AGENT THOUGHT PROCESS',
                      style: TextStyle(
                        color: brand.ink.withValues(alpha: 0.50),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22, color: Colors.white12),
                _TerminalLine(
                  prefix: '⚙',
                  text: 'Tool Call: ParseDocument(file)',
                  color: brand.ink.withValues(alpha: 0.80),
                ),
                const SizedBox(height: 4),
                _TerminalLine(
                  prefix: '↳',
                  text: 'Extracted 420 words.',
                  color: brand.accent,
                  bold: true,
                  indent: 14,
                ),
                const SizedBox(height: 12),
                _TerminalLine(
                  prefix: '⚙',
                  text: 'Tool Call: ExtractSkills()',
                  color: brand.ink.withValues(alpha: 0.80),
                ),
                const SizedBox(height: 4),
                _TerminalLine(
                  prefix: '↳',
                  text: 'Found: React, JavaScript, Figma.',
                  color: brand.accent,
                  bold: true,
                  indent: 14,
                ),
                const SizedBox(height: 12),
                _TerminalLine(
                  prefix: '🔍',
                  text:
                      'Agent Decision: Missing Target Role. Asking user for input.',
                  color: brand.warning,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalDot extends StatelessWidget {
  const _TerminalDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _TerminalLine extends StatelessWidget {
  const _TerminalLine({
    required this.prefix,
    required this.text,
    required this.color,
    this.bold = false,
    this.indent = 0,
  });

  final String prefix;
  final String text;
  final Color color;
  final bool bold;
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(prefix, style: TextStyle(color: color, fontSize: 11)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 11,
                height: 1.45,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

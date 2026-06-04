import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/dev/dev_flags_notifier.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/resumes_repository.dart';
import '../../../core/utils/motion.dart';
import '../../../shared/widgets/water_fill_circle.dart';
import '../../agent/state/passive_agent_notifier.dart';
import '../../agent_chat/tools/anthropic_tool_calls.dart';
import '../../resumes/models/resume_file.dart';
import '../../resumes/models/resume_fit.dart';
import '../../resumes/models/resume_json.dart';
import '../../resumes/services/resume_parser_service.dart';
import '../../resumes/services/resume_tailor_orchestrator.dart';
import '../../resumes/state/resume_notifier.dart';
import '../state/auth_notifier.dart';
import '../state/user_profile_notifier.dart';

/// Slightly off-white ink — pure #FFFFFF on true black reads as harsh, so back
/// off ~6%. Matches the morning brief / link-Gmail dark surfaces.
const Color _softInk = Color(0xFFF1F1F3);

/// First-run setup, reimagined as a dark, three-beat **resume upload** moment:
///
///   1. **Upload** — a big circular vessel the user taps to drop a resume; it
///      fills bottom-up with lime "water" as the file uploads.
///   2. **Prompt** — the parsed file surfaces and Syncra asks "What do you want
///      me to do?", with a context composer for the user's goal.
///   3. **Setup** — a headless agent reads the resume, infers the target role,
///      and kicks off the first brief while a live checklist narrates the work.
///
/// The whole flow is locked to [BrandTheme.dark] so it reads as one continuous,
/// premium hand-off into the (also dark) link-Gmail screen.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

enum _Phase { upload, prompt, setup }

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  // Built once so the forced-dark theme isn't rebuilt every frame.
  late final ThemeData _darkTheme = AppTheme.darkTheme;

  _Phase _phase = _Phase.upload;

  /// True once the user explicitly tapped to upload. Gates the auto-advance so
  /// a returning user who already has a resume isn't yanked forward before they
  /// choose to continue.
  bool _armed = false;

  /// The user's free-text instruction captured on the prompt phase, threaded
  /// into the agent brief.
  String _instruction = '';

  void _goToPrompt() {
    if (_phase != _Phase.upload) return;
    setState(() => _phase = _Phase.prompt);
  }

  /// Steps one phase back (setup → prompt → upload). Leaving the setup phase
  /// tears down its [_SetupPhase] via the [AnimatedSwitcher], cancelling the
  /// in-flight timers; re-entering re-runs the (idempotent) read.
  void _goBack() {
    setState(() {
      _phase = switch (_phase) {
        _Phase.setup => _Phase.prompt,
        _Phase.prompt => _Phase.upload,
        _Phase.upload => _Phase.upload,
      };
    });
  }

  /// Jump back to an already-visited phase from the top progress bar. Only
  /// backward moves are allowed — you can't skip ahead of the live flow.
  void _goToPhase(int index) {
    if (index >= _phase.index) return;
    setState(() => _phase = _Phase.values[index]);
  }

  void _send(String instruction) {
    _instruction = instruction.trim();
    setState(() => _phase = _Phase.setup);
  }

  Future<void> _pickResume() async {
    _armed = true;
    await ref.read(resumeProvider.notifier).pickAndUploadResumes();
  }

  /// Skips the whole flow — marks the user past first-run setup with no role
  /// captured. Mirrors the previous escape hatch.
  Future<void> _skip() async {
    await ref
        .read(userProfileProvider.notifier)
        .setHasCompletedOnboarding(true);
    final dev = ref.read(devFlagsProvider);
    if (dev.showOnboarding) {
      await ref.read(devFlagsProvider.notifier).setShowOnboarding(false);
    }
    if (!mounted) return;
    context.go(RouteNames.linkGmail);
  }

  Future<void> _confirmBackToLogin() async {
    final brand = context.brand;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: brand.surface,
        title: const Text('Back to login?'),
        content: const Text(
          "You'll be signed out and returned to the login screen. "
          "Your account stays — you can sign back in any time.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay here'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(authProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    // The moment a resume the user just uploaded lands, let the water-fill
    // visibly top out, then reveal the prompt. Selecting on the count keeps
    // this from firing on unrelated resume-list churn.
    ref.listen<int>(resumeProvider.select((s) => s.resumes.length), (
      prev,
      next,
    ) {
      if (_armed && _phase == _Phase.upload && next > (prev ?? 0)) {
        Future<void>.delayed(const Duration(milliseconds: 950), () {
          if (mounted && _phase == _Phase.upload) _goToPrompt();
        });
      }
    });

    return Theme(
      data: _darkTheme,
      child: Builder(
        builder: (context) {
          final brand = context.brand;
          return Scaffold(
            backgroundColor: brand.bg,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                child: Column(
                  children: [
                    // Header: a back/sign-out hatch beside the animated
                    // three-phase onboarding tracker.
                    Row(
                      children: [
                        _FrostedIconBtn(
                          icon: _phase == _Phase.upload
                              ? Icons.logout_rounded
                              : Icons.arrow_back_rounded,
                          tooltip: _phase == _Phase.upload
                              ? 'Back to login'
                              : 'Back',
                          onTap: _phase == _Phase.upload
                              ? _confirmBackToLogin
                              : _goBack,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _OnboardingProgress(
                            phaseIndex: _phase.index,
                            onTapIndex: _goToPhase,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 360),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, anim) =>
                            FadeTransition(opacity: anim, child: child),
                        child: switch (_phase) {
                          _Phase.upload => _UploadPhase(
                            key: const ValueKey('upload'),
                            onPick: _pickResume,
                            onContinue: _goToPrompt,
                            onSkip: _skip,
                          ),
                          _Phase.prompt => _PromptPhase(
                            key: const ValueKey('prompt'),
                            onSend: _send,
                            onSkip: _skip,
                            initialText: _instruction,
                          ),
                          _Phase.setup => _SetupPhase(
                            key: const ValueKey('setup'),
                            instruction: _instruction,
                          ),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 1 — upload (the water-fill vessel)
// ---------------------------------------------------------------------------

class _UploadPhase extends ConsumerWidget {
  const _UploadPhase({
    super.key,
    required this.onPick,
    required this.onContinue,
    required this.onSkip,
  });

  final VoidCallback onPick;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final state = ref.watch(resumeProvider);
    final uploading = state.uploadQueue.where((i) => !i.hasError).toList();
    final hasError = state.uploadQueue.any((i) => i.hasError);
    final hasResume = state.resumes.isNotEmpty;
    final busy = uploading.isNotEmpty;

    final progress = busy ? uploading.first.progress / 100.0 : 0.0;
    // Show a sliver of water the instant upload starts; hold full once the file
    // has landed.
    final fill = busy ? math.max(progress, 0.06) : (hasResume ? 1.0 : 0.0);
    final filled = !busy && hasResume;

    final caption = hasError
        ? 'That file didn\'t work — try another.'
        : busy
        ? 'Uploading your resume…'
        : hasResume
        ? 'Got it. Tap to continue.'
        : 'Drop in a PDF, DOC or DOCX — up to 5MB.';

    final onTap = busy ? null : (hasResume ? onContinue : onPick);

    return Column(
      children: [
        const SizedBox(height: 18),
        Text(
          'Upload Your Resume',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: _softInk,
            letterSpacing: -0.9,
            height: 1.1,
          ),
        ).animate().fadeIn(duration: 460.ms).moveY(begin: 8, end: 0),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: Text(
            caption,
            key: ValueKey(caption),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: hasError ? brand.warning : brand.textMuted,
              height: 1.5,
              letterSpacing: -0.1,
            ),
          ),
        ).animate(delay: 120.ms).fadeIn(),
        const Spacer(flex: 5),
        GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 224,
                height: 224,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    WaterFillCircle(fill: fill, active: busy, size: 224),
                    _CircleContent(
                      empty: !busy && !hasResume,
                      filled: filled,
                      fill: fill,
                      brand: brand,
                    ),
                  ],
                ),
              ),
            )
            .animate(delay: 160.ms)
            .fadeIn(duration: 460.ms)
            .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),
        const SizedBox(height: 22),
        if (hasResume && !busy)
          _FileChip(
            resume: state.resumes.first,
            ready: true,
          ).animate().fadeIn(duration: 320.ms).moveY(begin: 6, end: 0),
        const Spacer(flex: 7),
        if (hasResume && !busy)
          TextButton(
            onPressed: onPick,
            child: Text(
              'Upload a different resume',
              style: TextStyle(
                color: brand.textMuted,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        TextButton(
          onPressed: onSkip,
          child: Text(
            'Skip for now',
            style: TextStyle(
              color: brand.textSoft,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ),
        const SizedBox(height: 2),
      ],
    );
  }
}

/// The content layered over the water vessel: an invitation when empty, the
/// upload glyph fading out as it fills, and a check once it's full.
class _CircleContent extends StatelessWidget {
  const _CircleContent({
    required this.empty,
    required this.filled,
    required this.fill,
    required this.brand,
  });

  final bool empty;
  final bool filled;
  final double fill;
  final BrandTheme brand;

  @override
  Widget build(BuildContext context) {
    final String stateKey = empty
        ? 'empty'
        : filled
        ? 'filled'
        : 'busy';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1).animate(anim),
          child: child,
        ),
      ),
      child: switch (stateKey) {
        'filled' => Icon(
          Icons.check_rounded,
          key: const ValueKey('filled'),
          size: 56,
          color: brand.onAccent,
        ),
        'busy' => Opacity(
          key: const ValueKey('busy'),
          opacity: (1 - fill).clamp(0.0, 1.0),
          child: Icon(Icons.arrow_upward_rounded, size: 46, color: _softInk),
        ),
        _ => Column(
          key: const ValueKey('empty'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.file_upload_outlined, size: 46, color: brand.accent),
            const SizedBox(height: 10),
            Text(
              'Tap to upload',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: brand.textMuted,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 2 — prompt ("What do you want me to do?")
// ---------------------------------------------------------------------------

class _PromptPhase extends ConsumerStatefulWidget {
  const _PromptPhase({
    super.key,
    required this.onSend,
    required this.onSkip,
    this.initialText = '',
  });

  final ValueChanged<String> onSend;
  final VoidCallback onSkip;

  /// Pre-fills the composer — so stepping back from setup restores whatever the
  /// user already typed instead of a blank field.
  final String initialText;

  @override
  ConsumerState<_PromptPhase> createState() => _PromptPhaseState();
}

class _PromptPhaseState extends ConsumerState<_PromptPhase> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() => widget.onSend(_controller.text);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final resumes = ref.watch(resumeProvider).resumes;
    final resume = resumes.isNotEmpty ? resumes.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                if (resume != null)
                  _FileChip(
                    resume: resume,
                    ready: true,
                  ).animate().fadeIn(duration: 380.ms).moveY(begin: 6, end: 0),
                const SizedBox(height: 30),
                Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'What do you want\nme to '),
                          TextSpan(
                            text: 'do?',
                            style: TextStyle(color: brand.accent),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: _softInk,
                        height: 1.1,
                        letterSpacing: -1.0,
                      ),
                    )
                    .animate(delay: 120.ms)
                    .fadeIn(duration: 460.ms)
                    .moveY(begin: 10, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 14),
                Text(
                  "Tell me your goal and I'll get to work. Leave it blank and "
                  "I'll plan from your resume.",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: brand.textMuted,
                    height: 1.5,
                    letterSpacing: -0.1,
                  ),
                ).animate(delay: 200.ms).fadeIn(duration: 460.ms),
              ],
            ),
          ),
        ),
        _Composer(controller: _controller, focus: _focus, onSend: _submit)
            .animate(delay: 280.ms)
            .fadeIn(duration: 380.ms)
            .moveY(begin: 12, end: 0),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: widget.onSkip,
            child: Text(
              'Skip',
              style: TextStyle(
                color: brand.textSoft,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The docked instruction composer — a rounded field that brightens to the
/// accent on focus, with a circular send button.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final focused = focus.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: focused ? brand.accent : brand.border,
          width: 1.4,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              cursorColor: brand.accent,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: brand.ink,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: 'e.g. Find me remote product roles at startups',
                hintStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: brand.textSoft,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(onTap: onSend),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Semantics(
      button: true,
      label: 'Send',
      child: Material(
        color: brand.accent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              Icons.arrow_upward_rounded,
              color: brand.onAccent,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact pill showing the uploaded file — a PDF glyph, name, size, and a lime
/// "ready" check. Shared by the upload and prompt phases.
class _FileChip extends StatelessWidget {
  const _FileChip({required this.resume, this.ready = false});

  final ResumeFile resume;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: brand.accentMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.description_rounded,
              size: 18,
              color: brand.accent,
            ),
          ),
          const SizedBox(width: 11),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resume.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _formatBytes(resume.size),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: brand.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (ready) ...[
            const SizedBox(width: 12),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: brand.accent,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded, size: 14, color: brand.onAccent),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '—';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

// ---------------------------------------------------------------------------
// Phase 3 — setup (live agent work)
// ---------------------------------------------------------------------------

enum _StepStatus { pending, active, done, failed }

class _SetupPhase extends ConsumerStatefulWidget {
  const _SetupPhase({super.key, this.instruction = ''});

  /// The user's free-text instruction from the prompt phase. When present it
  /// steers the first brief; otherwise the inferred role does.
  final String instruction;

  @override
  ConsumerState<_SetupPhase> createState() => _SetupPhaseState();
}

class _SetupPhaseState extends ConsumerState<_SetupPhase> {
  static const _labels = [
    'Reading your resume',
    'Mapping your strengths',
    'Setting your target role',
    'Finding roles for you',
  ];

  final List<_StepStatus> _statuses = List<_StepStatus>.filled(
    4,
    _StepStatus.pending,
  );

  /// Live caption per step. The active step narrates what the agent is doing
  /// right now; finished steps keep a short result line. Drives the per-row
  /// subtitle in the process timeline.
  final List<String?> _subtitles = List<String?>.filled(4, null);

  String? _inferredRole;

  /// Concrete facts pulled from the parsed resume, revealed as chips under the
  /// reading step so the user sees the agent *actually read their file*.
  List<String> _found = const [];

  /// Free-text context the user adds mid-setup; folded into the live brief.
  final List<String> _addedContext = [];

  /// True once the first brief has kicked off — gates whether added context
  /// re-steers an already-running search.
  bool _briefStarted = false;

  /// Cycles the active step's subtitle through human-readable lines while an
  /// opaque async call is in flight, so a wait reads as live reasoning instead
  /// of a frozen caption.
  Timer? _thinking;

  /// Built locally (not via the agent tool layer) so onboarding owns its own
  /// dependency graph and doesn't reach into the chat's tool registry.
  late final ResumeTailorOrchestrator _orchestrator = ResumeTailorOrchestrator(
    resumesRepository: ResumesRepository(),
    jobsRepository: JobsRepository(),
    parser: ResumeParserService(),
  );
  final AnthropicParaphraseService _paraphrase = AnthropicParaphraseService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSetup());
  }

  @override
  void dispose() {
    _thinking?.cancel();
    super.dispose();
  }

  void _set(int i, _StepStatus status, {String? detail}) {
    if (!mounted) return;
    setState(() {
      _statuses[i] = status;
      if (detail != null) _subtitles[i] = detail;
    });
  }

  /// Builds a short, human list of what the parse actually pulled out of the
  /// file (name, role count, top skills) and reveals it under the headline.
  void _revealFindings(ResumeJson r) {
    final chips = <String>[];
    final name = r.header.name.trim();
    if (name.isNotEmpty) chips.add(name.split(RegExp(r'\s+')).first);
    // Lead with the most recent role — a concrete "I actually read your file"
    // signal, not just a count. Pair it with the company when both are present.
    if (r.experience.isNotEmpty) {
      final latest = r.experience.first;
      final role = latest.role.trim();
      final company = latest.company.trim();
      if (role.isNotEmpty && company.isNotEmpty) {
        chips.add('$role · $company');
      } else if (role.isNotEmpty) {
        chips.add(role);
      } else if (company.isNotEmpty) {
        chips.add(company);
      }
    }
    if (r.education.isNotEmpty) chips.add(r.education.first.degree.trim());
    chips.addAll(r.skills.where((s) => s.trim().isNotEmpty).take(4));
    final cleaned = chips.where((c) => c.trim().isNotEmpty).take(6).toList();
    if (!mounted || cleaned.isEmpty) return;
    setState(() => _found = cleaned);
  }

  /// Starts cycling [_detail] through [lines] every ~1.4s while [step]'s async
  /// work is in flight, so an opaque wait reads as live reasoning instead of a
  /// frozen caption. Caller stops it the moment the underlying work resolves.
  void _startThinking(int step, List<String> lines) {
    if (lines.isEmpty) return;
    var i = 0;
    _set(step, _StepStatus.active, detail: lines.first);
    _thinking?.cancel();
    _thinking = Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      i = (i + 1) % lines.length;
      setState(() => _subtitles[step] = lines[i]);
    });
  }

  void _stopThinking() {
    _thinking?.cancel();
    _thinking = null;
  }

  /// Folds the typed goal, any added context, and the inferred role into one
  /// brief query. Returns null when there's nothing to search on.
  String? _query() {
    final instruction = widget.instruction.trim();
    final parts = <String>[
      if (instruction.isNotEmpty) instruction,
      ..._addedContext,
      if (instruction.isEmpty && (_inferredRole?.isNotEmpty ?? false))
        _inferredRole!,
    ];
    return parts.isEmpty ? null : parts.join('. ');
  }

  /// Captures context the user adds while setup runs. If the search already
  /// kicked off, re-steer it with the fuller picture.
  void _addContext(String text) {
    final t = text.trim();
    if (t.isEmpty || !mounted) return;
    setState(() => _addedContext.add(t));
    if (_briefStarted) {
      unawaited(
        ref.read(passiveAgentProvider.notifier).runBrief(query: _query()),
      );
    }
  }

  Future<void> _runSetup() async {
    final uid = ref.read(authProvider).appUser?.uid;
    if (uid == null) {
      await _finish(roleSet: false);
      return;
    }

    // Step 1 — read + parse the resume. The download + Sonnet parse is a few
    // opaque seconds, so narrate it with rotating "reading" captions rather
    // than a single frozen line; the real extracted facts surface as chips the
    // moment the parse resolves.
    _startThinking(0, const [
      'Reading your resume…',
      'Scanning your experience…',
      'Pulling out your skills…',
      'Noting your education…',
    ]);
    final ResumeJson parsed;
    try {
      final resumeId = await _orchestrator.latestManualResumeId(uid);
      if (resumeId == null) {
        throw Exception('No resume found.');
      }
      parsed = await _orchestrator.readResumeJson(uid: uid, resumeId: resumeId);
      _stopThinking();
      _set(0, _StepStatus.done);
      _revealFindings(parsed);
    } catch (e) {
      // Scanned PDF / parse failure / missing key — don't trap the user. Mark
      // them past setup and let them into the app; the agent can read the
      // resume later from chat.
      _stopThinking();
      _set(
        0,
        _StepStatus.failed,
        detail: "Couldn't read that file — you can still continue.",
      );
      await _finish(roleSet: false);
      return;
    }

    // Step 2 — infer role + role-fit in one headless agent call. This is the
    // longest, most opaque step, so narrate it with rotating captions drawn
    // from the user's own resume rather than a single frozen line.
    _startThinking(1, [
      'Mapping your strengths…',
      if (parsed.experience.isNotEmpty)
        'Weighing ${parsed.experience.length} '
            '${parsed.experience.length == 1 ? 'role' : 'roles'} of experience…',
      if (parsed.skills.isNotEmpty)
        'Connecting ${parsed.skills.first} to live roles…',
      'Reading between your bullet points…',
      'Pinpointing your best-fit role…',
    ]);
    String role = '';
    try {
      final inferred = await _paraphrase.inferOnboardingProfile(
        resumeJson: parsed.toJson(),
      );
      _stopThinking();
      role = (inferred['role'] as String?)?.trim() ?? '';
      final fit = _fitFrom(inferred['segments']);
      if (fit != null) {
        await ref.read(userProfileProvider.notifier).setResumeFit(fit);
      }
      _set(1, _StepStatus.done);
    } catch (e) {
      _stopThinking();
      _set(1, _StepStatus.failed);
    }

    // Step 3 — persist the target role (without flipping the onboarding gate
    // yet, so the router keeps us on this screen while the work finishes).
    _set(2, _StepStatus.active, detail: 'Setting your target role…');
    if (role.isNotEmpty) {
      _inferredRole = role;
      await ref.read(userProfileProvider.notifier).setRole(role);
      _set(2, _StepStatus.done, detail: 'Target role: $role');
    } else {
      _set(2, _StepStatus.done, detail: 'You can set a target role anytime.');
    }

    // Step 4 — kick off the first brief. The user's typed instruction steers
    // the search when given; otherwise we fall back to the inferred role. It
    // runs in the background; the dashboard picks up the live state from here.
    final instruction = widget.instruction.trim();
    _set(
      3,
      _StepStatus.active,
      detail: instruction.isNotEmpty
          ? 'On it — searching live roles…'
          : 'Searching live roles for you…',
    );
    _briefStarted = true;
    unawaited(
      ref.read(passiveAgentProvider.notifier).runBrief(query: _query()),
    );
    // Brief stays running in the background — give it a beat so the handoff to
    // the dashboard reads as continuous motion, not a hard cut.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _set(3, _StepStatus.done, detail: 'Your first brief is on the way.');
    await _finish(roleSet: role.isNotEmpty);
  }

  ResumeFit? _fitFrom(dynamic rawSegments) {
    if (rawSegments is! List) return null;
    final segments = rawSegments
        .whereType<Map>()
        .map(
          (m) => ResumeFitSegment(
            label: (m['label'] as String?)?.trim() ?? '',
            percent: (m['percent'] as num?)?.toDouble() ?? 0,
            rationale: (m['rationale'] as String?)?.trim().isEmpty ?? true
                ? null
                : (m['rationale'] as String).trim(),
          ),
        )
        .where((s) => s.label.isNotEmpty && s.percent > 0)
        .toList();
    if (segments.length < 2) return null;
    return ResumeFit(segments: segments, generatedAt: DateTime.now());
  }

  /// Flips the onboarding gate and routes onward. Setting the flag last (rather
  /// than during step 3) keeps the router from redirecting away mid-setup, so
  /// the user actually sees the checklist complete.
  Future<void> _finish({required bool roleSet}) async {
    await ref
        .read(userProfileProvider.notifier)
        .setHasCompletedOnboarding(true);
    final dev = ref.read(devFlagsProvider);
    if (dev.showOnboarding) {
      await ref.read(devFlagsProvider.notifier).setShowOnboarding(false);
    }
    if (!mounted) return;
    context.go(RouteNames.linkGmail);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final allSettled = _statuses.every(
      (s) => s == _StepStatus.done || s == _StepStatus.failed,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text(
                  'Setting up your copilot',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    color: _softInk,
                    letterSpacing: -0.8,
                    height: 1.1,
                  ),
                ).animate().fadeIn(duration: 420.ms).moveY(begin: 8, end: 0),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: Text(
                    allSettled
                        ? 'All set — taking you in…'
                        : 'Your copilot is getting to work. This only takes a '
                              'few seconds.',
                    key: ValueKey(allSettled),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: brand.textMuted,
                      height: 1.45,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                const SizedBox(height: 34),
                // The process timeline — a node per step joined by a connector
                // that flows lime as work passes through it.
                for (var i = 0; i < _labels.length; i++)
                  _ProcessStep(
                    label:
                        i == 2 &&
                            _statuses[2] == _StepStatus.done &&
                            _inferredRole != null
                        ? 'Target role · $_inferredRole'
                        : _labels[i],
                    status: _statuses[i],
                    subtitle: _subtitles[i],
                    isLast: i == _labels.length - 1,
                    child: i == 0 && _found.isNotEmpty ? _foundWrap() : null,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Let the user feed the agent more to go on while it works.
        _AddContext(onSubmit: _addContext, added: _addedContext),
        const SizedBox(height: 4),
      ],
    );
  }

  /// The facts pulled from the parse, shown inline under the reading step.
  Widget _foundWrap() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _found.length; i++)
            _FoundChip(label: _found[i])
                .animate(delay: (i * 80).ms)
                .fadeIn(duration: 240.ms)
                .moveY(begin: 6, end: 0)
                .scale(
                  begin: const Offset(0.92, 0.92),
                  end: const Offset(1, 1),
                ),
        ],
      ),
    );
  }
}

/// A single extracted fact (name, role count, a skill) surfaced during setup
/// so the agent's read of the resume is visible, not implied.
class _FoundChip extends StatelessWidget {
  const _FoundChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      // Bound the width so the inner Flexible has a finite constraint (a Wrap
      // hands children unbounded width) and long entries ellipsize instead of
      // overflowing.
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: brand.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brand.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 13, color: brand.accentBright),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: brand.ink,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Process timeline — a vertical node-and-connector stepper
// ---------------------------------------------------------------------------

/// One row of the setup timeline: a status node on a left rail (joined to the
/// next node by an animated [_Connector]) beside a title, a live subtitle that
/// narrates what the agent is doing, and an optional [child] payload (the facts
/// the parse pulled out).
class _ProcessStep extends StatelessWidget {
  const _ProcessStep({
    required this.label,
    required this.status,
    required this.subtitle,
    required this.isLast,
    this.child,
  });

  final String label;
  final _StepStatus status;
  final String? subtitle;
  final bool isLast;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final active = status == _StepStatus.active;
    final done = status == _StepStatus.done;
    final pending = status == _StepStatus.pending;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left rail: node + the connector that drops to the next node.
          SizedBox(
            width: 30,
            child: Column(
              children: [
                _Node(status: status),
                if (!isLast)
                  Expanded(
                    child: _Connector(done: done, active: active),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: isLast ? 2 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 240),
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: active || done
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: pending ? brand.textMuted : _softInk,
                      letterSpacing: -0.2,
                      height: 1.2,
                    ),
                    child: Text(label),
                  ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: Text(
                        subtitle!,
                        key: ValueKey(subtitle),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: active ? brand.accentBright : brand.textMuted,
                          height: 1.35,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ],
                  ?child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The status disc on the rail: a lime check when done, a pulsing lime ring
/// while active, a warning glyph on failure, and a quiet hollow dot when
/// pending.
class _Node extends StatelessWidget {
  const _Node({required this.status});

  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    switch (status) {
      case _StepStatus.done:
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: brand.accentBright,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: brand.accent.withValues(alpha: 0.4),
                blurRadius: 9,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(Icons.check_rounded, size: 16, color: brand.onAccent),
        );
      case _StepStatus.failed:
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: brand.warning.withValues(alpha: 0.16),
            shape: BoxShape.circle,
            border: Border.all(color: brand.warning, width: 1.6),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.priority_high_rounded,
            size: 14,
            color: brand.warning,
          ),
        );
      case _StepStatus.active:
        return const _ActiveNode();
      case _StepStatus.pending:
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: brand.surfaceMuted,
            shape: BoxShape.circle,
            border: Border.all(color: brand.border, width: 1.4),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: brand.textSoft,
              shape: BoxShape.circle,
            ),
          ),
        );
    }
  }
}

/// The in-progress node: a lime ring around a bright core that breathes (gated
/// on reduced-motion).
class _ActiveNode extends StatelessWidget {
  const _ActiveNode();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final core = Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: brand.surface,
        shape: BoxShape.circle,
        border: Border.all(color: brand.accent, width: 2),
        boxShadow: [
          BoxShadow(color: brand.accent.withValues(alpha: 0.5), blurRadius: 10),
        ],
      ),
      alignment: Alignment.center,
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: brand.accentBright,
          shape: BoxShape.circle,
        ),
      ),
    );
    if (!shouldAnimate(context)) return core;
    return core
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(
          begin: 0.9,
          end: 1.1,
          duration: 900.ms,
          curve: Curves.easeInOut,
        );
  }
}

/// The vertical line joining two nodes. Pending: a faint track. Active: a lime
/// pulse travelling top-to-bottom (the work "flowing" to the next step). Done:
/// the track fills solid lime, top-down.
class _Connector extends StatefulWidget {
  const _Connector({required this.done, required this.active});

  final bool done;
  final bool active;

  @override
  State<_Connector> createState() => _ConnectorState();
}

class _ConnectorState extends State<_Connector>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Connector old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active && shouldAnimate(context)) {
      if (!_flow.isAnimating) _flow.repeat();
    } else {
      _flow.stop();
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            width: 2.5,
            child: widget.done
                ? _doneFill(brand)
                : widget.active
                ? _activeFlow(brand)
                : Container(color: brand.border),
          ),
        ),
      ),
    );
  }

  Widget _doneFill(BrandTheme brand) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Stack(
        fit: StackFit.expand,
        children: [
          Container(color: brand.border),
          Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(
              heightFactor: t,
              child: Container(color: brand.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeFlow(BrandTheme brand) {
    final base = brand.accent.withValues(alpha: 0.22);
    if (!shouldAnimate(context)) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Container(color: base),
          Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(
              heightFactor: 0.5,
              child: Container(color: brand.accent),
            ),
          ),
        ],
      );
    }
    return AnimatedBuilder(
      animation: _flow,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          Container(color: base),
          Align(
            // Drives a 40%-tall highlight from top (-1) to bottom (+1).
            alignment: Alignment(0, -1 + 2 * _flow.value),
            child: FractionallySizedBox(
              heightFactor: 0.4,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      brand.accent.withValues(alpha: 0),
                      brand.accentBright,
                      brand.accent.withValues(alpha: 0),
                    ],
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

// ---------------------------------------------------------------------------
// Add-context affordance (setup phase)
// ---------------------------------------------------------------------------

/// A collapsed "Add context" pill that expands into a composer, letting the
/// user feed the agent more to go on while setup runs. Added lines show as lime
/// chips above the control.
class _AddContext extends StatefulWidget {
  const _AddContext({required this.onSubmit, required this.added});

  final ValueChanged<String> onSubmit;
  final List<String> added;

  @override
  State<_AddContext> createState() => _AddContextState();
}

class _AddContextState extends State<_AddContext> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _open = false;

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focus.requestFocus(),
      );
    }
  }

  void _submit() {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    widget.onSubmit(t);
    _controller.clear();
    _focus.unfocus();
    setState(() => _open = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.added.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final c in widget.added) _ContextChip(label: c)],
            ),
          ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _open ? _composer(brand) : _addButton(brand),
        ),
      ],
    );
  }

  Widget _addButton(BrandTheme brand) {
    return Align(
      key: const ValueKey('add-btn'),
      alignment: Alignment.centerLeft,
      child: Material(
        color: brand.surface,
        shape: StadiumBorder(side: BorderSide(color: brand.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 18, color: brand.accent),
                const SizedBox(width: 8),
                Text(
                  'Add context',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _composer(BrandTheme brand) {
    return Container(
      key: const ValueKey('add-composer'),
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: brand.accent.withValues(alpha: 0.6),
          width: 1.4,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              cursorColor: brand.accent,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: brand.ink,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                hintText: 'e.g. prefer remote, \$120k+, no agencies',
                hintStyle: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: brand.textSoft,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _SendButton(onTap: _submit),
        ],
      ),
    );
  }
}

/// A user-added context line — lime-tinted to distinguish it from the read
/// facts surfaced by the agent.
class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: brand.accentMuted,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brand.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 13, color: brand.accentBright),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: brand.ink,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 220.ms).moveY(begin: 6, end: 0);
  }
}

// ---------------------------------------------------------------------------
// Top onboarding tracker
// ---------------------------------------------------------------------------

/// Slim three-segment tracker pinned above the flow. Each segment fills with
/// lime as its phase is reached; the live segment carries a soft glow. Visited
/// segments are tappable to step back.
class _OnboardingProgress extends StatelessWidget {
  const _OnboardingProgress({
    required this.phaseIndex,
    required this.onTapIndex,
  });

  final int phaseIndex;
  final ValueChanged<int> onTapIndex;

  static const _labels = ['Upload', 'Goal', 'Setup'];

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < _labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _ProgressSegment(
                  filled: i <= phaseIndex,
                  current: i == phaseIndex,
                  onTap: i < phaseIndex ? () => onTapIndex(i) : null,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            for (var i = 0; i < _labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == phaseIndex
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: i <= phaseIndex ? brand.ink : brand.textSoft,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ProgressSegment extends StatelessWidget {
  const _ProgressSegment({
    required this.filled,
    required this.current,
    this.onTap,
  });

  final bool filled;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // Enlarge the tap target around the slim 5px bar.
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          height: 5,
          decoration: BoxDecoration(
            color: brand.surfaceMuted,
            borderRadius: BorderRadius.circular(3),
          ),
          clipBehavior: Clip.antiAlias,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeOutCubic,
              widthFactor: filled ? 1.0 : 0.0,
              child: Container(
                decoration: BoxDecoration(
                  color: brand.accent,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: current
                      ? [
                          BoxShadow(
                            color: brand.accent.withValues(alpha: 0.45),
                            blurRadius: 9,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted circular icon button — the sign-out / back-to-login escape hatch.
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
    final button = Material(
      color: brand.surfaceMuted,
      shape: CircleBorder(side: BorderSide(color: brand.border)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 18, color: brand.ink),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

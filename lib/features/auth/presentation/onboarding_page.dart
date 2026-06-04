import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/dev/dev_flags_notifier.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../core/utils/motion.dart';
import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/resumes_repository.dart';
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

  void _send(String instruction) {
    _instruction = instruction.trim();
    setState(() => _phase = _Phase.setup);
  }

  Future<void> _pickResume() async {
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
        title: const Text('Back to sign in?'),
        content: const Text(
          "You'll be signed out and returned to the sign-in screen. "
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
                    // Header: a single bare back arrow — no circle, no chip.
                    // It signs out to the sign-in screen on the upload beat and
                    // steps one phase back thereafter. No progress tracker; the
                    // flow reveals itself as you move.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _BackButton(
                        semanticLabel: _phase == _Phase.upload
                            ? 'Back to sign in'
                            : 'Back',
                        onTap: _phase == _Phase.upload
                            ? _confirmBackToLogin
                            : _goBack,
                      ),
                    ),
                    const SizedBox(height: 12),
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
  });

  final VoidCallback onPick;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final state = ref.watch(resumeProvider);
    final uploading = state.uploadQueue.where((i) => !i.hasError).toList();
    final hasError = state.uploadQueue.any((i) => i.hasError);
    final hasResume = state.resumes.isNotEmpty;
    final busy = uploading.isNotEmpty;

    final percent = busy ? uploading.first.progress : 0;
    final progress = percent / 100.0;
    // Show a sliver of water the instant upload starts; hold full once the file
    // has landed.
    final fill = busy ? math.max(progress, 0.06) : (hasResume ? 1.0 : 0.0);
    final filled = !busy && hasResume;

    // One adaptive line under the vessel — the only words on this beat. While
    // uploading it's the live percentage, ticking up with the water.
    final label = hasError
        ? "That file didn't work — try again"
        : busy
        ? '$percent%'
        : filled
        ? 'Tap to continue'
        : 'Upload Your Resume';

    // Key the line on its *state*, not its text, so the percentage can tick up
    // in place without the AnimatedSwitcher cross-fading on every increment.
    final labelKey = hasError
        ? 'error'
        : busy
        ? 'busy'
        : filled
        ? 'filled'
        : 'empty';

    final onTap = busy ? null : (hasResume ? onContinue : onPick);

    return Column(
      children: [
        const Spacer(flex: 6),
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
            .animate()
            .fadeIn(duration: 460.ms)
            .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),
        const SizedBox(height: 28),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: Text(
            label,
            key: ValueKey(labelKey),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: hasError ? brand.warning : _softInk,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (hasResume && !busy)
          _UploadedResume(
            resume: state.resumes.first,
            onDelete: () => ref
                .read(resumeProvider.notifier)
                .deleteResume(state.resumes.first.id),
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
        const SizedBox(height: 2),
      ],
    );
  }
}

/// The content layered over the water vessel: a big up arrow when empty,
/// fading out as the water fills, and a check once it's full. No words — the
/// arrow alone says "tap to upload".
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
          size: 78,
          color: brand.onAccent,
        ),
        'busy' => Opacity(
          key: const ValueKey('busy'),
          opacity: (1 - fill).clamp(0.0, 1.0),
          child: Icon(Icons.arrow_upward_rounded, size: 96, color: _softInk),
        ),
        _ => Icon(
          Icons.arrow_upward_rounded,
          key: const ValueKey('empty'),
          size: 96,
          color: brand.accent,
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
                  _UploadedResume(
                    resume: resume,
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

/// The just-uploaded file, shown stripped right back — a cute PDF glyph, the
/// file name + size, and (when [onDelete] is given) a quiet trash affordance to
/// remove it. No card, no border: just the file, in keeping with the minimalist
/// flow. Shared by the upload and prompt phases.
class _UploadedResume extends StatelessWidget {
  const _UploadedResume({required this.resume, this.onDelete});

  final ResumeFile resume;

  /// When non-null, a trash icon sits beside the file and calls this to remove
  /// it. Omitted on the prompt phase, where the file is just being confirmed.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            AppAssets.pdfSvg,
            width: 30,
            height: 36,
            semanticsLabel: 'PDF',
          ),
          const SizedBox(width: 12),
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
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: _softInk,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatBytes(resume.size),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: brand.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 6),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: brand.textMuted,
                  ),
                ),
              ),
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
    'Reading your context',
    'Mapping your strengths',
    'Setting your target role',
    'Finding roles for you',
  ];

  /// Index of the "Reading your context" step — kept named so the timeline and
  /// the run sequence stay in lockstep when steps are reordered.
  static const _contextStep = 1;

  final List<_StepStatus> _statuses = List<_StepStatus>.filled(
    5,
    _StepStatus.pending,
  );

  /// Live caption per step. The active step narrates what the agent is doing
  /// right now; finished steps keep a short result line. Drives the per-row
  /// subtitle in the process timeline.
  final List<String?> _subtitles = List<String?>.filled(5, null);

  String? _inferredRole;

  /// Concrete facts pulled from the parsed resume, revealed as chips under the
  /// reading step so the user sees the agent *actually read their file*.
  List<String> _found = const [];

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

  /// The context the agent is working from — the goal the user typed on the
  /// prompt phase. Drives the chip shown under the "Reading your context" step.
  List<String> get _contextItems {
    final goal = widget.instruction.trim();
    return [if (goal.isNotEmpty) goal];
  }

  bool get _hasContext => _contextItems.isNotEmpty;

  /// Folds the typed goal and the inferred role into one brief query. Returns
  /// null when there's nothing to search on.
  String? _query() {
    final instruction = widget.instruction.trim();
    final parts = <String>[
      if (instruction.isNotEmpty) instruction,
      if (instruction.isEmpty && (_inferredRole?.isNotEmpty ?? false))
        _inferredRole!,
    ];
    return parts.isEmpty ? null : parts.join('. ');
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

    // Step 2 — read the user's own context (the goal they typed on the prompt
    // beat). It's already in hand, so this step is short; the goal is rendered
    // as a chip under the step so the read is *visible*.
    _set(_contextStep, _StepStatus.active, detail: 'Taking in what you told me…');
    await Future<void>.delayed(const Duration(milliseconds: 750));
    _set(
      _contextStep,
      _StepStatus.done,
      detail: _hasContext
          ? "Got your context — I'll factor it in."
          : "No goal set — I'll plan from your resume.",
    );

    // Step 3 — infer role + role-fit in one headless agent call. This is the
    // longest, most opaque step, so narrate it with rotating captions drawn
    // from the user's own resume rather than a single frozen line.
    _startThinking(2, [
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
      _set(2, _StepStatus.done);
    } catch (e) {
      _stopThinking();
      _set(2, _StepStatus.failed);
    }

    // Step 4 — persist the target role (without flipping the onboarding gate
    // yet, so the router keeps us on this screen while the work finishes).
    _set(3, _StepStatus.active, detail: 'Setting your target role…');
    if (role.isNotEmpty) {
      _inferredRole = role;
      await ref.read(userProfileProvider.notifier).setRole(role);
      _set(3, _StepStatus.done, detail: 'Target role: $role');
    } else {
      _set(3, _StepStatus.done, detail: 'You can set a target role anytime.');
    }

    // Step 5 — kick off the first brief. The user's typed instruction steers
    // the search when given; otherwise we fall back to the inferred role. It
    // runs in the background; the dashboard picks up the live state from here.
    final instruction = widget.instruction.trim();
    _set(
      4,
      _StepStatus.active,
      detail: instruction.isNotEmpty
          ? 'On it — searching live roles…'
          : 'Searching live roles for you…',
    );
    unawaited(
      ref.read(passiveAgentProvider.notifier).runBrief(query: _query()),
    );
    // Brief stays running in the background — give it a beat so the handoff to
    // the dashboard reads as continuous motion, not a hard cut.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _set(4, _StepStatus.done, detail: 'Your first brief is on the way.');
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
                // that flows lime as work passes through it. Each row reveals in
                // a gentle top-down stagger as the page enters; flutter_animate
                // plays this once per State, so live status updates that rebuild
                // these rows don't replay the entrance.
                for (var i = 0; i < _labels.length; i++)
                  _ProcessStep(
                        label:
                            i == 3 &&
                                _statuses[3] == _StepStatus.done &&
                                _inferredRole != null
                            ? 'Target role · $_inferredRole'
                            : _labels[i],
                        status: _statuses[i],
                        subtitle: _subtitles[i],
                        isLast: i == _labels.length - 1,
                        child: _stepChild(i),
                      )
                      .animate(delay: (i * 80).ms)
                      .fadeIn(duration: 360.ms)
                      .moveY(begin: 8, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The inline payload under a step: the facts pulled from the resume under
  /// the reading step, and the context the agent is working from under the
  /// "Reading your context" step.
  Widget? _stepChild(int i) {
    if (i == 0 && _found.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var j = 0; j < _found.length; j++)
              _FoundChip(label: _found[j])
                  .animate(delay: (j * 80).ms)
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
    if (i == _contextStep && _contextItems.isNotEmpty) {
      final items = _contextItems;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final c in items) _ContextChip(label: c)],
        ),
      );
    }
    return null;
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

  static const double _railWidth = 30;
  static const double _nodeSize = 26;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final active = status == _StepStatus.active;
    final done = status == _StepStatus.done;
    final pending = status == _StepStatus.pending;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;

    // The content (node + text) defines the row height; the connector is drawn
    // behind it as a Positioned line spanning from the bottom of this node to
    // the bottom of the row (which reaches the next node). Positioning gives the
    // connector a *bounded* height, so it never needs intrinsic sizing — a
    // fill-style connector reports an infinite intrinsic height, which is what
    // crashed the old IntrinsicHeight + Expanded layout.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (!isLast)
          Positioned(
            top: _nodeSize,
            bottom: 0,
            left: 0,
            width: _railWidth,
            child: Center(child: _Connector(done: done, active: active)),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _railWidth,
              child: Align(
                alignment: Alignment.topCenter,
                child: _Node(status: status),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 2, bottom: isLast ? 2 : 26),
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
                            color: active
                                ? brand.accentBright
                                : brand.textMuted,
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
      ],
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
    // height: infinity fills the bounded box handed down by the parent's
    // Positioned(top/bottom) — no intrinsic sizing involved.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          width: 2.5,
          height: double.infinity,
          child: widget.done
              ? _doneFill(brand)
              : widget.active
              ? _activeFlow(brand)
              : Container(color: brand.border),
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

/// The user's typed goal — lime-tinted to distinguish it from the read facts
/// the agent surfaced from the resume.
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
// Header back button
// ---------------------------------------------------------------------------

/// The header's lone affordance: a bare back arrow — no circle, no frosted
/// chip. The caller wires the action per phase (sign out on the upload beat,
/// one phase back thereafter); [semanticLabel] keeps that meaning for screen
/// readers even though the glyph stays the same.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.semanticLabel, required this.onTap});

  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.arrow_back_rounded, size: 24, color: _softInk),
          ),
        ),
      ),
    );
  }
}

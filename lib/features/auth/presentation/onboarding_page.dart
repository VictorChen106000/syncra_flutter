import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/dev/dev_flags_notifier.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/resumes_repository.dart';
import '../../../shared/widgets/gooey_orb.dart';
import '../../agent/state/passive_agent_notifier.dart';
import '../../agent_chat/tools/anthropic_tool_calls.dart';
import '../../resumes/models/resume_fit.dart';
import '../../resumes/presentation/widgets/resume_upload_card.dart';
import '../../resumes/services/resume_parser_service.dart';
import '../../resumes/services/resume_tailor_orchestrator.dart';
import '../../resumes/services/resume_tailor_service.dart';
import '../../resumes/state/resume_notifier.dart';
import '../state/auth_notifier.dart';
import '../state/user_profile_notifier.dart';

/// First-run setup, reimagined as a dedicated **resume upload** moment.
///
/// The user drops a resume and Syncra takes it from there: it parses the file,
/// infers the user's target role + role-fit breakdown in one headless agent
/// call, persists both to the profile, kicks off the first job brief, and
/// routes straight to the dashboard. The middle phase shows a live checklist
/// of what the agent is doing so the user is never staring at a frozen
/// "loading" screen.
///
/// No chat, no Q&A, no "Enter Syncra" tap — upload, watch, land.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

enum _Phase { upload, setup }

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  _Phase _phase = _Phase.upload;

  /// True once the user explicitly tapped "Upload". Gates the auto-advance so
  /// a returning user who already has a resume isn't yanked into setup before
  /// they tap Continue.
  bool _armed = false;

  void _goToSetup() {
    if (_phase == _Phase.setup) return;
    setState(() => _phase = _Phase.setup);
  }

  Future<void> _pickResume() async {
    _armed = true;
    await ref.read(resumeProvider.notifier).pickAndUploadResumes();
  }

  /// Skips upload entirely — marks the user past first-run setup with no role
  /// captured (they can set one later by chatting). Mirrors the previous
  /// flow's escape hatch.
  Future<void> _skip() async {
    await ref.read(userProfileProvider.notifier).setHasCompletedOnboarding(true);
    final dev = ref.read(devFlagsProvider);
    if (dev.showOnboarding) {
      await ref.read(devFlagsProvider.notifier).setShowOnboarding(false);
    }
    if (!mounted) return;
    context.go(RouteNames.dashboard);
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
    final brand = context.brand;

    // The moment a resume the user just uploaded lands in their library,
    // advance into the setup phase. Selecting on the count keeps this from
    // firing on unrelated resume-list churn.
    ref.listen<int>(
      resumeProvider.select((s) => s.resumes.length),
      (prev, next) {
        if (_armed && _phase == _Phase.upload && next > (prev ?? 0)) {
          _goToSetup();
        }
      },
    );

    return Scaffold(
      backgroundColor: brand.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            children: [
              // Top chrome: sign-out escape hatch + a quiet "Setup" label.
              Row(
                children: [
                  _FrostedIconBtn(
                    icon: Icons.logout_rounded,
                    tooltip: 'Back to login',
                    onTap: _confirmBackToLogin,
                  ),
                  const Spacer(),
                  Text(
                    'Setup',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: brand.textMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 42),
                ],
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: child,
                  ),
                  child: _phase == _Phase.upload
                      ? _UploadPhase(
                          key: const ValueKey('upload'),
                          onPick: _pickResume,
                          onContinue: _goToSetup,
                          onSkip: _skip,
                        )
                      : const _SetupPhase(key: ValueKey('setup')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 1 — upload
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
    final resumeState = ref.watch(resumeProvider);
    final resumes = resumeState.resumes;
    final uploading = resumeState.uploadQueue.where((i) => !i.hasError).toList();
    final hasResume = resumes.isNotEmpty;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          const SizedBox(height: 24),
          GooeyOrb(size: 132)
              .animate()
              .fadeIn(duration: 480.ms)
              .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1)),
          const SizedBox(height: 28),
          Text(
            "Let's set you up",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: brand.ink,
              letterSpacing: -0.6,
              height: 1.15,
            ),
          ).animate(delay: 100.ms).fadeIn().moveY(begin: 8, end: 0),
          const SizedBox(height: 10),
          Text(
            'Drop in your resume — Syncra reads it and tailors everything '
            'to you. No forms.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: brand.textMuted,
              height: 1.5,
              letterSpacing: -0.1,
            ),
          ).animate(delay: 180.ms).fadeIn(),
          const SizedBox(height: 32),

          // Live upload progress for any in-flight file.
          for (final item in uploading)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ResumeUploadCard(uploadingItem: item),
            ),

          // Existing resume(s) the user already has — lets returning users
          // continue without re-uploading.
          if (hasResume && uploading.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ResumeUploadCard(resume: resumes.first),
            ),

          _UploadDropCard(onTap: onPick, compact: hasResume)
              .animate(delay: 240.ms)
              .fadeIn()
              .moveY(begin: 10, end: 0),

          const SizedBox(height: 20),

          if (hasResume && uploading.isEmpty)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: brand.ink,
                  foregroundColor: brand.inkInverse,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),

          const SizedBox(height: 8),
          TextButton(
            onPressed: onSkip,
            child: Text(
              'Skip for now',
              style: TextStyle(
                color: brand.textMuted,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadDropCard extends StatelessWidget {
  const _UploadDropCard({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: compact ? 18 : 30),
          decoration: BoxDecoration(
            color: brand.surfaceMuted,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: brand.border, width: 1.4),
          ),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: brand.ink,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.upload_file_rounded,
                  color: brand.accent,
                  size: 24,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                compact ? 'Upload a different resume' : 'Upload your resume',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: brand.ink,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'PDF, DOC or DOCX · up to 5MB',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: brand.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 2 — setup (live agent work)
// ---------------------------------------------------------------------------

enum _StepStatus { pending, active, done, failed }

class _SetupPhase extends ConsumerStatefulWidget {
  const _SetupPhase({super.key});

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
  static const _icons = [
    Icons.description_rounded,
    Icons.insights_rounded,
    Icons.flag_rounded,
    Icons.travel_explore_rounded,
  ];

  final List<_StepStatus> _statuses =
      List<_StepStatus>.filled(4, _StepStatus.pending);
  String _detail = 'Getting started…';
  String? _inferredRole;

  /// Built locally (not via the agent tool layer) so onboarding owns its own
  /// dependency graph and doesn't reach into the chat's tool registry.
  late final ResumeTailorOrchestrator _orchestrator = ResumeTailorOrchestrator(
    resumesRepository: ResumesRepository(),
    jobsRepository: JobsRepository(),
    parser: ResumeParserService(),
    tailor: ResumeTailorService(),
  );
  final AnthropicParaphraseService _paraphrase = AnthropicParaphraseService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSetup());
  }

  void _set(int i, _StepStatus status, {String? detail}) {
    if (!mounted) return;
    setState(() {
      _statuses[i] = status;
      if (detail != null) _detail = detail;
    });
  }

  Future<void> _runSetup() async {
    final uid = ref.read(authProvider).appUser?.uid;
    if (uid == null) {
      await _finish(roleSet: false);
      return;
    }

    // Step 1 — read + parse the resume.
    _set(0, _StepStatus.active, detail: 'Reading your resume…');
    final dynamic parsed;
    try {
      final resumeId = await _orchestrator.latestManualResumeId(uid);
      if (resumeId == null) {
        throw Exception('No resume found.');
      }
      parsed = await _orchestrator.readResumeJson(uid: uid, resumeId: resumeId);
      _set(0, _StepStatus.done);
    } catch (e) {
      // Scanned PDF / parse failure / missing key — don't trap the user. Mark
      // them past setup and let them into the app; the agent can read the
      // resume later from chat.
      _set(0, _StepStatus.failed,
          detail: "Couldn't read that file — you can still continue.");
      await _finish(roleSet: false);
      return;
    }

    // Step 2 — infer role + role-fit in one headless agent call.
    _set(1, _StepStatus.active, detail: 'Mapping your strengths…');
    String role = '';
    try {
      final inferred = await _paraphrase.inferOnboardingProfile(
        resumeJson: parsed.toJson() as Map<String, dynamic>,
      );
      role = (inferred['role'] as String?)?.trim() ?? '';
      final fit = _fitFrom(inferred['segments']);
      if (fit != null) {
        await ref.read(userProfileProvider.notifier).setResumeFit(fit);
      }
      _set(1, _StepStatus.done);
    } catch (e) {
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

    // Step 4 — kick off the first brief. It runs in the background; the
    // dashboard picks up the live "Looking for X roles…" state from here.
    _set(3, _StepStatus.active, detail: 'Finding roles for you…');
    unawaited(
      ref.read(passiveAgentProvider.notifier).runBrief(
            query: role.isEmpty ? null : role,
          ),
    );
    // Brief stays running in the background — give it a beat so the handoff to
    // the dashboard reads as continuous motion, not a hard cut.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _set(3, _StepStatus.done);
    await _finish(roleSet: role.isNotEmpty);
  }

  ResumeFit? _fitFrom(dynamic rawSegments) {
    if (rawSegments is! List) return null;
    final segments = rawSegments
        .whereType<Map>()
        .map((m) => ResumeFitSegment(
              label: (m['label'] as String?)?.trim() ?? '',
              percent: (m['percent'] as num?)?.toDouble() ?? 0,
              rationale: (m['rationale'] as String?)?.trim().isEmpty ?? true
                  ? null
                  : (m['rationale'] as String).trim(),
            ))
        .where((s) => s.label.isNotEmpty && s.percent > 0)
        .toList();
    if (segments.length < 2) return null;
    return ResumeFit(segments: segments, generatedAt: DateTime.now());
  }

  /// Flips the onboarding gate and routes to the dashboard. Setting the flag
  /// last (rather than during step 3) keeps the router from redirecting away
  /// mid-setup, so the user actually sees the checklist complete.
  Future<void> _finish({required bool roleSet}) async {
    await ref
        .read(userProfileProvider.notifier)
        .setHasCompletedOnboarding(true);
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
    return Column(
      children: [
        const SizedBox(height: 24),
        GooeyOrb(size: 120)
            .animate(onPlay: (c) => c.repeat())
            .shimmer(duration: 1800.ms, color: brand.accent.withValues(alpha: 0.3)),
        const SizedBox(height: 24),
        Text(
          'Setting up your copilot',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: brand.ink,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: Text(
            _detail,
            key: ValueKey(_detail),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: brand.textMuted,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 36),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: brand.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _labels.length; i++)
                _StepRow(
                  label: _statuses[i] == _StepStatus.done && i == 2 &&
                          _inferredRole != null
                      ? 'Target role · $_inferredRole'
                      : _labels[i],
                  icon: _icons[i],
                  status: _statuses[i],
                  isLast: i == _labels.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.icon,
    required this.status,
    required this.isLast,
  });

  final String label;
  final IconData icon;
  final _StepStatus status;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final bool active = status == _StepStatus.active;
    final bool done = status == _StepStatus.done;
    final bool failed = status == _StepStatus.failed;

    final Color tint = done
        ? brand.accentBright
        : failed
            ? brand.warning
            : active
                ? brand.ink
                : brand.textSoft;

    return Padding(
      padding: EdgeInsets.only(top: 12, bottom: isLast ? 12 : 12),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: _leading(brand, active, done, failed),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: active || done ? FontWeight.w800 : FontWeight.w600,
                color: status == _StepStatus.pending ? brand.textMuted : brand.ink,
                letterSpacing: -0.1,
              ),
            ),
          ),
          Icon(icon, size: 17, color: tint),
        ],
      ),
    );
  }

  Widget _leading(BrandTheme brand, bool active, bool done, bool failed) {
    if (active) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          valueColor: AlwaysStoppedAnimation(brand.ink),
        ),
      );
    }
    if (done) {
      return Container(
        decoration: BoxDecoration(
          color: brand.accentBright,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(Icons.check_rounded, size: 16, color: brand.onAccent),
      );
    }
    if (failed) {
      return Container(
        decoration: BoxDecoration(
          color: brand.warning.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(Icons.priority_high_rounded, size: 15, color: brand.warning),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: brand.surfaceMuted,
        shape: BoxShape.circle,
        border: Border.all(color: brand.border),
      ),
    );
  }
}

/// Frosted circular icon button — the sign-out / back-to-login escape hatch.
class _FrostedIconBtn extends StatelessWidget {
  const _FrostedIconBtn({required this.icon, required this.onTap, this.tooltip});

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

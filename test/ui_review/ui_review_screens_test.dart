// UI-review harness — renders the Jobs pipeline page and the agent chat's
// generative-UI blocks with fixed fake data and captures golden PNGs.
//
// Run with:
//   flutter test --update-goldens test/ui_review
//
// The PNGs land in test/ui_review/goldens/. This file exists so the app's two
// most design-sensitive surfaces can be screenshotted without Firebase auth or
// live API keys.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' hide PipelineStage;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as gf_base;

import 'package:syncra/core/theme/app_theme.dart';
import 'package:syncra/data/firestore/applications_repository.dart';
import 'package:syncra/data/firestore/pipeline_repository.dart';
import 'package:syncra/data/firestore/resumes_repository.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/features/agent/services/anthropic_service.dart';
import 'package:syncra/features/agent/state/passive_agent_notifier.dart';
import 'package:syncra/features/agent_chat/models/agent_block.dart';
import 'package:syncra/features/agent_chat/models/chat_message.dart';
import 'package:syncra/features/agent_chat/presentation/ai_chatbot_page.dart';
import 'package:syncra/features/agent_chat/state/agent_chat_notifier.dart';
import 'package:syncra/features/jobs/presentation/jobs_page.dart';
import 'package:syncra/features/jobs/state/jobs_notifier.dart';
import 'package:syncra/features/resumes/models/proposed_edit.dart';
import 'package:syncra/features/resumes/state/resume_notifier.dart';

// ---------------------------------------------------------------------------
// Fakes — enough to construct the notifiers without Firebase.initializeApp().
// ---------------------------------------------------------------------------

class _FakeFirestore extends Fake implements FirebaseFirestore {}

class _FakeStorage extends Fake implements FirebaseStorage {}

class _FixedJobsNotifier extends JobsNotifier {
  _FixedJobsNotifier(this._fixed)
    : super(
        repository: PipelineRepository(db: _FakeFirestore()),
        applicationsRepository: ApplicationsRepository(db: _FakeFirestore()),
      );

  final JobsState _fixed;

  @override
  JobsState build() => _fixed;
}

class _FixedPassiveAgentNotifier extends PassiveAgentNotifier {
  _FixedPassiveAgentNotifier()
    : super(
        service: AnthropicService(apiKey: 'test-key'),
        pipelineRepository: PipelineRepository(db: _FakeFirestore()),
      );

  @override
  PassiveAgentState build() => PassiveAgentState(
    status: AgentBriefStatus.done,
    lastBriefAt: DateTime.now().subtract(const Duration(hours: 2)),
  );
}

class _FixedChatNotifier extends AgentChatNotifier {
  _FixedChatNotifier(this._fixed);

  final AgentChatState _fixed;

  @override
  AgentChatState build() => _fixed;
}

class _FixedResumeNotifier extends ResumeNotifier {
  _FixedResumeNotifier()
    : super(
        repository: ResumesRepository(
          db: _FakeFirestore(),
          storage: _FakeStorage(),
        ),
      );

  @override
  ResumeState build() => const ResumeState();
}

// ---------------------------------------------------------------------------
// Fixture data
// ---------------------------------------------------------------------------

Job _job({
  required String id,
  required String title,
  required String company,
  required JobCategory category,
  String location = 'Remote',
  String salary = r'$110k – $140k',
  List<String> skills = const ['Figma', 'Prototyping', 'Design systems'],
  List<String> missing = const [],
  String why = 'Strong overlap with your portfolio work.',
}) => Job(
  id: id,
  title: title,
  company: company,
  location: location,
  salary: salary,
  category: category,
  matchScore: 82,
  agentAction: 'apply',
  agentJustification: why,
  skills: skills,
  missingSkills: missing,
  why: why,
);

List<PipelineCard> _pipelineCards() {
  final now = DateTime.now();
  return [
    PipelineCard(
      id: 'p1',
      job: _job(
        id: 'j1',
        title: 'Senior Product Designer',
        company: 'Linear',
        category: JobCategory.ready,
        location: 'Remote · US',
        salary: r'$150k – $185k',
      ),
      status: PipelineCardStatus.pending,
      createdAt: now.subtract(const Duration(minutes: 18)),
      stage: PipelineStage.drafted,
      trustRiskLevel: 'low',
      trustRiskLabel: 'Looks safe',
    ),
    PipelineCard(
      id: 'p2',
      job: _job(
        id: 'j2',
        title: 'UX Designer, Growth',
        company: 'Notion',
        category: JobCategory.inputNeeded,
        location: 'Hybrid · NYC',
        salary: r'$120k – $145k',
        missing: ['A/B testing', 'SQL'],
      ),
      status: PipelineCardStatus.pending,
      createdAt: now.subtract(const Duration(hours: 1)),
      stage: PipelineStage.matched,
      trustRiskLevel: 'medium',
      trustRiskLabel: 'Verify first',
      trustSignalsCount: 2,
    ),
    PipelineCard(
      id: 'p3',
      job: _job(
        id: 'j3',
        title: 'Frontend Engineer (Design Systems)',
        company: 'Vercel',
        category: JobCategory.ready,
        location: 'Remote · EU',
        salary: r'$130k – $160k',
        skills: ['React', 'TypeScript', 'Storybook'],
      ),
      status: PipelineCardStatus.pending,
      createdAt: now.subtract(const Duration(hours: 3)),
      stage: PipelineStage.tailored,
      trustRiskLevel: 'low',
      trustRiskLabel: 'Looks safe',
    ),
    PipelineCard(
      id: 'p4',
      job: _job(
        id: 'j4',
        title: 'Product Designer',
        company: 'Figma',
        category: JobCategory.ready,
        location: 'SF · On-site',
        salary: r'$140k – $170k',
      ),
      status: PipelineCardStatus.pending,
      createdAt: now.subtract(const Duration(hours: 26)),
      stage: PipelineStage.sent,
      trustRiskLevel: 'low',
      trustRiskLabel: 'Looks safe',
    ),
  ];
}

AgentChatState _chatWithJobsRail() {
  final turn = AgentTurn(
    id: 't1',
    isStreaming: false,
    status: AgentTurnStatus.done,
    blocks: [
      ThinkingBlock(
        id: 'b0',
        content:
            'The user wants remote senior design roles. I should search and '
            'rank by fit against their resume.',
      ),
      ToolCallBlock(
        id: 'b1',
        name: 'search_jobs',
        label: 'Searching jobs',
        icon: Icons.search_rounded,
        status: ToolCallStatus.done,
        resultSummary: 'Found 14 roles · kept the 3 strongest fits',
      ),
      TextBlock(
        id: 'b2',
        text:
            'I found three roles that fit your senior product design '
            'background. Linear is the strongest match — their posting '
            'leans heavily on systems thinking, which your resume already '
            'demonstrates.',
      ),
      JobsBlock(
        id: 'b3',
        jobs: [
          _job(
            id: 'j1',
            title: 'Senior Product Designer',
            company: 'Linear',
            category: JobCategory.ready,
            salary: r'$150k – $185k',
          ),
          _job(
            id: 'j2',
            title: 'Staff Designer, Platform',
            company: 'Stripe',
            category: JobCategory.inputNeeded,
            salary: r'$160k – $200k',
            missing: ['Payments domain'],
          ),
          _job(
            id: 'j3',
            title: 'Design Engineer',
            company: 'Vercel',
            category: JobCategory.exploration,
            salary: r'$130k – $160k',
          ),
        ],
      ),
    ],
  );
  return AgentChatState(
    conversationId: 'demo',
    items: [
      UserMessage(
        id: 'u1',
        text: 'Find me senior product design roles, remote first.',
      ),
      turn,
    ],
  );
}

AgentChatState _chatWithDraftAndEdits() {
  final turn = AgentTurn(
    id: 't2',
    isStreaming: false,
    status: AgentTurnStatus.done,
    blocks: [
      ToolCallBlock(
        id: 'c1',
        name: 'tailor_resume',
        label: 'Tailoring resume for Linear',
        icon: Icons.auto_fix_high_rounded,
        status: ToolCallStatus.done,
        resultSummary: '4 edits applied to resume_2026.pdf',
      ),
      ProposedEditsBlock.applied(
        id: 'c2',
        jobId: 'j1',
        resumeId: 'r1',
        edits: const [
          ProposedEdit(
            targetPath: 'experience[0].bullets[1]',
            originalText: 'Worked on the design system used by several teams.',
            proposedText:
                'Owned the cross-platform design system adopted by 6 product teams.',
            reason: 'Linear asks for design-system ownership.',
          ),
          ProposedEdit(
            targetPath: 'skills',
            originalText: '',
            proposedText: 'Linear-style keyboard-first UX patterns',
            reason: 'Posting emphasises keyboard-first workflows.',
            op: ProposedEditOp.add,
          ),
        ],
      ),
      TextBlock(
        id: 'c3',
        text:
            'Resume tailored. I also drafted the outreach email below — '
            'review it and send when you are happy.',
      ),
      EmailDraftBlock(
        id: 'c4',
        recipient: 'careers@linear.app',
        subject: 'Senior Product Designer — application',
        body:
            'Hi Linear team,\n\nI am a senior product designer with six years '
            'of experience building design systems used across multiple '
            'product teams. Linear’s keyboard-first philosophy mirrors '
            'how I design — I would love to talk.\n\nBest,\nDaryn',
        jobId: 'j1',
        attachmentResumeId: 'r1',
        attachmentFilename: 'tailored_linear.pdf',
      ),
      InputRequestBlock(
        id: 'c5',
        question:
            'Should I mention your availability for a portfolio walkthrough this week?',
        suggestions: const ['Yes, offer this week', 'No, keep it short'],
      ),
    ],
  );
  return AgentChatState(
    conversationId: 'demo2',
    items: [
      UserMessage(
        id: 'u2',
        text: 'Tailor my resume for the Linear role and draft the email.',
      ),
      turn,
    ],
  );
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

const _fontDir = 'test/ui_review/fonts';

File _materialIconsFontFile() {
  final candidates = <File>[];
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.trim().isNotEmpty) {
    candidates.add(
      File(
        '${flutterRoot.trim()}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    );
  }

  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    candidates
      ..add(
        File(
          '${dir.path}/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ),
      )
      ..add(
        File(
          '${dir.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ),
      );
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  candidates.add(
    File(
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ),
  );

  for (final candidate in candidates) {
    if (candidate.existsSync()) return candidate;
  }
  throw StateError('Could not locate MaterialIcons-Regular.otf.');
}

/// Intercepts the asset channel so google_fonts finds Inter "in the bundle":
/// the AssetManifest response gains entries for the Inter TTFs, and requests
/// for those paths are served from [_fontDir]. Everything else passes through
/// to the real test asset bundle.
void _installFontAssets(TestDefaultBinaryMessenger messenger) {
  final fontNames = Directory(_fontDir)
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.ttf'))
      .toList();

  messenger.setMockMessageHandler('flutter/assets', (message) async {
    final key = utf8.decode(
      message!.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes),
    );
    if (key == 'AssetManifest.bin') {
      final real = await messenger.delegate.send('flutter/assets', message);
      final decoded = real == null
          ? <Object?, Object?>{}
          : const StandardMessageCodec().decodeMessage(real)!
                as Map<Object?, Object?>;
      final merged = Map<Object?, Object?>.from(decoded);
      for (final name in fontNames) {
        merged['googlefonts/$name'] = <Object?>[];
      }
      return const StandardMessageCodec().encodeMessage(merged);
    }
    if (key.startsWith('googlefonts/')) {
      final bytes = File('$_fontDir/${key.split('/').last}').readAsBytesSync();
      return ByteData.sublistView(bytes);
    }
    return messenger.delegate.send('flutter/assets', message);
  });
}

Widget _wrap(Widget child, List<Override> overrides, {bool dark = false}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: child,
    ),
  );
}

Future<void> _settleAnimations(WidgetTester tester) async {
  // flutter_animate entrances finish within ~1.5s; the page also hosts
  // looping animations (orb, shimmer) so pumpAndSettle would never return.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> capture(
    WidgetTester tester,
    Widget Function() buildApp,
    String name, {
    double height = 852,
  }) async {
    // Install the asset mock before the theme is built — GoogleFonts kicks
    // off its font load the moment the TextTheme is constructed.
    _installFontAssets(tester.binding.defaultBinaryMessenger);
    // Anything that cached the real manifest before the mock was installed
    // must be evicted so google_fonts sees the font entries.
    rootBundle.evict('AssetManifest.bin');
    gf_base.assetManifest = null;

    tester.view.physicalSize = Size(393 * 3, height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    // Real blurred shadows in the capture — must be restored before the test
    // body ends or the binding's invariant check fails the test.
    debugDisableShadows = false;
    try {
      // Prime every Inter face inside runAsync: font loads started in the
      // fake-async test zone can never complete while runAsync awaits them
      // (deadlock), so kick them off *and* drain them in the real-async zone
      // before the theme is ever built in the test zone.
      await tester.runAsync(() async {
        for (final w in const [
          FontWeight.w400,
          FontWeight.w500,
          FontWeight.w600,
          FontWeight.w700,
          FontWeight.w800,
          FontWeight.w900,
        ]) {
          GoogleFonts.inter(fontWeight: w);
        }
        await GoogleFonts.pendingFonts();
        // Material icons otherwise render as tofu boxes in widget tests.
        final icons = _materialIconsFontFile().readAsBytesSync();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons)))).load();
      });
      final app = buildApp();
      await tester.pumpWidget(app);
      await _settleAnimations(tester);
      // Rebuild from scratch so every paragraph lays out with the loaded faces.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app);
      await _settleAnimations(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  testWidgets('jobs page — populated pipeline', (tester) async {
    await capture(
      tester,
      () => _wrap(const JobsPage(), [
        jobsProvider.overrideWith(
          () => _FixedJobsNotifier(JobsState(cards: _pipelineCards())),
        ),
        passiveAgentProvider.overrideWith(_FixedPassiveAgentNotifier.new),
      ]),
      'jobs_pipeline_light',
    );
  });

  testWidgets('jobs page — populated pipeline (tall)', (tester) async {
    await capture(
      tester,
      () => _wrap(const JobsPage(), [
        jobsProvider.overrideWith(
          () => _FixedJobsNotifier(JobsState(cards: _pipelineCards())),
        ),
        passiveAgentProvider.overrideWith(_FixedPassiveAgentNotifier.new),
      ]),
      'jobs_pipeline_tall',
      height: 2300,
    );
  });

  testWidgets('jobs page — populated pipeline (dark)', (tester) async {
    await capture(
      tester,
      () => _wrap(const JobsPage(), [
        jobsProvider.overrideWith(
          () => _FixedJobsNotifier(JobsState(cards: _pipelineCards())),
        ),
        passiveAgentProvider.overrideWith(_FixedPassiveAgentNotifier.new),
      ], dark: true),
      'jobs_pipeline_dark',
    );
  });

  testWidgets('jobs page — empty state', (tester) async {
    await capture(
      tester,
      () => _wrap(const JobsPage(), [
        jobsProvider.overrideWith(() => _FixedJobsNotifier(const JobsState())),
        passiveAgentProvider.overrideWith(_FixedPassiveAgentNotifier.new),
      ]),
      'jobs_empty_light',
    );
  });

  testWidgets('chat — generative jobs rail', (tester) async {
    await capture(
      tester,
      () => _wrap(const AiChatbotPage(), [
        agentChatProvider.overrideWith(
          () => _FixedChatNotifier(_chatWithJobsRail()),
        ),
        jobsProvider.overrideWith(() => _FixedJobsNotifier(const JobsState())),
        resumeProvider.overrideWith(_FixedResumeNotifier.new),
      ]),
      'chat_jobs_rail_light',
    );
  });

  testWidgets('chat — email draft + proposed edits + input request', (
    tester,
  ) async {
    await capture(
      tester,
      () => _wrap(const AiChatbotPage(), [
        agentChatProvider.overrideWith(
          () => _FixedChatNotifier(_chatWithDraftAndEdits()),
        ),
        jobsProvider.overrideWith(() => _FixedJobsNotifier(const JobsState())),
        resumeProvider.overrideWith(_FixedResumeNotifier.new),
      ]),
      'chat_draft_review_light',
    );
  });

  testWidgets('chat — draft review (tall)', (tester) async {
    await capture(
      tester,
      () => _wrap(const AiChatbotPage(), [
        agentChatProvider.overrideWith(
          () => _FixedChatNotifier(_chatWithDraftAndEdits()),
        ),
        jobsProvider.overrideWith(() => _FixedJobsNotifier(const JobsState())),
        resumeProvider.overrideWith(_FixedResumeNotifier.new),
      ]),
      'chat_draft_review_tall',
      height: 1700,
    );
  });
}

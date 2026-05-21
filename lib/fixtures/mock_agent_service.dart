import 'package:flutter/material.dart';

import '../features/agent_chat/models/agent_block.dart';
import '../features/agent_chat/models/chat_message.dart';
import '../features/agent_chat/services/agent_service.dart';

/// Scripted [AgentService] for the demo flow.
///
/// Each scenario is a list of [_Step]s the service emits with realistic
/// delays so the UI animates like a streaming response. To wire the real
/// backend later, implement [AgentService] against the API and swap the
/// instance in the Provider tree — no UI changes required.
class MockAgentService implements AgentService {
  MockAgentService();

  @override
  void provideUserAnswer(String blockId, String answer) {
    // Mock doesn't run a tool-use loop, so ask_user never fires here.
  }

  @override
  void resetConversation() {
    // Scripted scenarios are stateless — nothing to reset.
  }

  /// Bumped on every [runPrompt] so block IDs stay unique across repeats of
  /// the same scenario — otherwise [acceptProposal] on the second run would
  /// silently target the first run's card.
  int _invocation = 0;

  // ---------------------------------------------------------------------------
  // Public prompt catalogue — shared by dashboard cards + chat quick replies.
  // ---------------------------------------------------------------------------

  static const String discoverPrompt =
      'Find UX roles at AI startups hiring this week';
  static const String tailorPrompt =
      'Tailor my resume for the Linear UX Designer role';
  static const String outreachPrompt =
      "Draft a cold outreach to Linear's hiring manager";
  static const String strategyPrompt =
      'What roles match my current trajectory?';

  static const List<String> dashboardPrompts = [
    discoverPrompt,
    tailorPrompt,
    outreachPrompt,
    strategyPrompt,
  ];

  @override
  Stream<AgentEvent> runPrompt({
    required String prompt,
    List<ChatAttachment> attachments = const [],
    bool threaded = true,
  }) async* {
    _invocation += 1;
    final prefix = 'r$_invocation-';
    String pfx(String id) => '$prefix$id';

    final steps = _scenarioFor(prompt);
    final pendingTools = <String, String>{}; // prefixed blockId → result

    for (final step in steps) {
      await Future<void>.delayed(step.delay);
      switch (step) {
        case _AddBlock(:final block, :final pendingToolResult):
          final rebranded = _withId(block, pfx(block.id));
          if (rebranded is ToolCallBlock && pendingToolResult != null) {
            pendingTools[rebranded.id] = pendingToolResult;
          }
          yield BlockAdded(rebranded);
        case _FinishTool(:final blockId, :final summary):
          yield ToolCallCompleted(blockId: pfx(blockId), summary: summary);
        case _AutoFinishTool(:final blockId):
          final id = pfx(blockId);
          final summary = pendingTools.remove(id);
          if (summary != null) {
            yield ToolCallCompleted(blockId: id, summary: summary);
          }
      }
    }
    yield const TurnCompleted();
  }

  /// Rebuilds [block] with a new [id] so repeated runs of the same scenario
  /// don't share block IDs across turns.
  AgentBlock _withId(AgentBlock block, String id) {
    return switch (block) {
      ThinkingBlock(:final content) =>
        ThinkingBlock(id: id, content: content),
      ToolCallBlock(:final name, :final label, :final icon, :final detail) =>
        ToolCallBlock(
          id: id,
          name: name,
          label: label,
          icon: icon,
          detail: detail,
        ),
      TextBlock(:final text) => TextBlock(id: id, text: text),
      ProposedEditsBlock(:final edits, :final jobId, :final resumeId) =>
      ProposedEditsBlock(
        id: id,
        edits: edits,
        jobId: jobId,
        resumeId: resumeId,
      ),
      ActionProposalBlock(
        :final icon,
        :final title,
        :final description,
        :final acceptLabel,
        :final editLabel,
      ) =>
        ActionProposalBlock(
          id: id,
          icon: icon,
          title: title,
          description: description,
          acceptLabel: acceptLabel,
          editLabel: editLabel,
        ),
      InputRequestBlock(:final question, :final suggestions) =>
        InputRequestBlock(id: id, question: question, suggestions: suggestions),
    };
  }

  // ---------------------------------------------------------------------------
  // Scenario scripts
  // ---------------------------------------------------------------------------

  List<_Step> _scenarioFor(String prompt) {
    final normalized = prompt.trim().toLowerCase();
    if (normalized == discoverPrompt.toLowerCase()) return _discover();
    if (normalized == tailorPrompt.toLowerCase()) return _tailor();
    if (normalized == outreachPrompt.toLowerCase()) return _outreach();
    if (normalized == strategyPrompt.toLowerCase()) return _strategy();
    return _fallback();
  }

  List<_Step> _discover() {
    const search = 'search_jobs';
    const score = 'score_match';
    return [
      _addThinking(
        'discover-think',
        "The user wants fresh UX roles at AI startups. I'll pull the last "
            '48h of postings, filter by AI-native companies, and rank by '
            'match against their saved profile.',
        delay: const Duration(milliseconds: 320),
      ),
      _addTool(
        id: search,
        label: 'Searching LinkedIn, Wellfound & company pages…',
        icon: Icons.travel_explore_rounded,
        pendingToolResult: 'Scanned 142 postings · 12 strong matches',
        detail: '▸ input\n'
            '   query    "UX designer · AI startups"\n'
            '   sources  LinkedIn, Wellfound, careers pages\n'
            '   window   last 48h\n'
            '▸ output\n'
            '   scanned  142 postings\n'
            '   matched  12 roles (AI-native teams)',
        delay: const Duration(milliseconds: 700),
      ),
      _autoFinish(search, delay: const Duration(milliseconds: 1100)),
      _addTool(
        id: score,
        label: 'Scoring matches against your profile…',
        icon: Icons.insights_rounded,
        pendingToolResult: 'Top 3: Linear 94% · Binance 94% · Vercel 98%',
        detail: '▸ input\n'
            '   candidates  12 roles\n'
            '   profile     Daryn — Senior Product Designer\n'
            '▸ output\n'
            '   Vercel    98%   design systems + data viz\n'
            '   Linear    94%   recent redesign overlap\n'
            '   Binance   94%   motion at scale',
        delay: const Duration(milliseconds: 600),
      ),
      _autoFinish(score, delay: const Duration(milliseconds: 900)),
      _addText(
        'discover-text',
        "I found 3 strong fits posted in the last 48 hours. Linear is your "
            "highest at 94% — they shipped a redesign last week that lines up "
            "with your Design Systems work. Want me to save them to your pipeline?",
        delay: const Duration(milliseconds: 600),
      ),
      _addProposal(
        id: 'discover-action',
        icon: Icons.bookmark_added_rounded,
        title: 'Save 3 roles to your pipeline',
        description: 'Linear · Binance · Vercel — ready for review',
        delay: const Duration(milliseconds: 400),
      ),
    ];
  }

  List<_Step> _tailor() {
    const analyze = 'analyze_resume';
    const keywords = 'extract_jd_keywords';
    const tailor = 'tailor_resume';
    return [
      _addThinking(
        'tailor-think',
        "Reading the Linear JD and comparing it against the user's base "
            'resume. I need to surface keyword gaps and rewrite weak bullets '
            'without inventing experience.',
        delay: const Duration(milliseconds: 320),
      ),
      _addTool(
        id: analyze,
        label: 'Parsing Daryn_resume.pdf…',
        icon: Icons.description_rounded,
        pendingToolResult: '7 sections · 18 strong keywords detected',
        detail: '▸ input\n'
            '   file     Daryn_resume.pdf (1 page)\n'
            '▸ output\n'
            '   sections  7 detected\n'
            '   keywords  18 strong signals\n'
            '   gaps      motion, a/b testing',
        delay: const Duration(milliseconds: 600),
      ),
      _autoFinish(analyze, delay: const Duration(milliseconds: 900)),
      _addTool(
        id: keywords,
        label: 'Extracting requirements from the JD…',
        icon: Icons.filter_alt_rounded,
        pendingToolResult: 'Needs: Design Systems · Motion · A/B Testing',
        detail: '▸ input\n'
            '   job   Linear — UX Designer\n'
            '▸ output\n'
            '   must-have   Design Systems, Motion, A/B Testing\n'
            '   bonus       Prototyping, User Research',
        delay: const Duration(milliseconds: 600),
      ),
      _autoFinish(keywords, delay: const Duration(milliseconds: 800)),
      _addTool(
        id: tailor,
        label: 'Rewriting your project section…',
        icon: Icons.auto_awesome_rounded,
        pendingToolResult: '3 bullets rewritten · 4 keywords added',
        detail: '▸ input\n'
            '   base    Daryn_resume.pdf\n'
            '   target  Linear — UX Designer\n'
            '▸ output\n'
            '   rewrote   3 project bullets\n'
            '   injected  4 missing keywords\n'
            '   match     81% → 92%',
        delay: const Duration(milliseconds: 700),
      ),
      _autoFinish(tailor, delay: const Duration(milliseconds: 1100)),
      _addText(
        'tailor-text',
        "Done. Match moved from 81% → 92%. The biggest lift came from "
            "leading with your Design Systems work and adding motion examples "
            "from the Stripe project.",
        delay: const Duration(milliseconds: 600),
      ),
      _addProposal(
        id: 'tailor-action',
        icon: Icons.save_alt_rounded,
        title: 'Save Linear_UX_Resume_v4.pdf',
        description: 'Tailored resume · 92% match · ready to attach',
        delay: const Duration(milliseconds: 400),
      ),
    ];
  }

  List<_Step> _outreach() {
    const contact = 'lookup_contact';
    const news = 'fetch_company_news';
    const draft = 'draft_email';
    return [
      _addThinking(
        'outreach-think',
        "Cold outreach lands best when it references something specific and "
            'recent. Let me find the design lead and pull a warm hook from '
            "the last month of company news.",
        delay: const Duration(milliseconds: 320),
      ),
      _addTool(
        id: contact,
        label: 'Looking up the hiring manager…',
        icon: Icons.person_search_rounded,
        pendingToolResult: 'Karri Saarinen · Head of Design at Linear',
        detail: '▸ input\n'
            '   company  Linear\n'
            '   role     design lead\n'
            '▸ output\n'
            '   name   Karri Saarinen\n'
            '   title  Head of Design\n'
            '   email  karri@linear.app (verified)',
        delay: const Duration(milliseconds: 600),
      ),
      _autoFinish(contact, delay: const Duration(milliseconds: 900)),
      _addTool(
        id: news,
        label: 'Scanning recent Linear news…',
        icon: Icons.newspaper_rounded,
        pendingToolResult: 'Series C announced 3 weeks ago · 50→80 hires',
        detail: '▸ input\n'
            '   company  Linear\n'
            '   window   last 30 days\n'
            '▸ output\n'
            '   • Series C announced — 3 weeks ago\n'
            '   • Headcount 50 → 80 planned',
        delay: const Duration(milliseconds: 600),
      ),
      _autoFinish(news, delay: const Duration(milliseconds: 900)),
      _addTool(
        id: draft,
        label: 'Drafting a 4-sentence cold email…',
        icon: Icons.edit_note_rounded,
        pendingToolResult: 'Subject + body ready · 320 chars',
        detail: '▸ input\n'
            '   to     Karri Saarinen\n'
            '   tone   warm · concise\n'
            '▸ output\n'
            '   subject  "Design systems at Linear, post–Series C"\n'
            '   length   4 sentences · 320 chars',
        delay: const Duration(milliseconds: 800),
      ),
      _autoFinish(draft, delay: const Duration(milliseconds: 1100)),
      _addText(
        'outreach-text',
        "Here's a warm but tight outreach. It opens with the Series C, "
            "ties your Design Systems work to their hiring push, and ends "
            "with a specific ask — not a generic 'love to chat'.",
        delay: const Duration(milliseconds: 600),
      ),
      _addProposal(
        id: 'outreach-action',
        icon: Icons.send_rounded,
        title: 'Send via Gmail',
        description: 'To karri@linear.app — review before it goes out',
        delay: const Duration(milliseconds: 400),
      ),
    ];
  }

  List<_Step> _strategy() {
    const analyze = 'analyze_history';
    return [
      _addThinking(
        'strategy-think',
        "Pattern-matching the user's last 12 saved roles and their apply "
            "behaviour. Looking for the centre of mass and the adjacent paths "
            "they're under-indexing on.",
        delay: const Duration(milliseconds: 320),
      ),
      _addTool(
        id: analyze,
        label: 'Analysing your saved roles + apply history…',
        icon: Icons.insights_rounded,
        pendingToolResult: 'Centre: Senior IC · design-led · \$135K median',
        detail: '▸ input\n'
            '   saved    12 roles\n'
            '   applied  5 applications\n'
            '▸ output\n'
            '   centre    Senior IC · design-led\n'
            '   median    \$135K\n'
            '   adjacent  Design Systems Lead, Data Viz',
        delay: const Duration(milliseconds: 900),
      ),
      _autoFinish(analyze, delay: const Duration(milliseconds: 1300)),
      _addText(
        'strategy-text',
        "You're trending Senior IC at design-led product companies "
            "(median \$135K). Two adjacent paths worth a look: Design Systems "
            "Lead — your strongest signal — and Data Viz Specialist, where "
            "you're a hidden 98% match at Vercel.",
        delay: const Duration(milliseconds: 700),
      ),
    ];
  }

  List<_Step> _fallback() {
    return [
      _addText(
        'fallback-text',
        "Got it — I'll work on that. Try one of the suggested prompts to "
            'see a full scenario play out end-to-end.',
        delay: const Duration(milliseconds: 700),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Step factories
  // ---------------------------------------------------------------------------

  _Step _addThinking(String id, String content, {required Duration delay}) =>
      _AddBlock(
        delay: delay,
        block: ThinkingBlock(id: id, content: content),
      );

  _Step _addTool({
    required String id,
    required String label,
    required IconData icon,
    required String pendingToolResult,
    required Duration delay,
    String? detail,
  }) =>
      _AddBlock(
        delay: delay,
        block: ToolCallBlock(
          id: id,
          name: id,
          label: label,
          icon: icon,
          detail: detail,
        ),
        pendingToolResult: pendingToolResult,
      );

  _Step _autoFinish(String id, {required Duration delay}) =>
      _AutoFinishTool(delay: delay, blockId: id);

  _Step _addText(String id, String text, {required Duration delay}) =>
      _AddBlock(delay: delay, block: TextBlock(id: id, text: text));

  _Step _addProposal({
    required String id,
    required IconData icon,
    required String title,
    required String description,
    required Duration delay,
  }) =>
      _AddBlock(
        delay: delay,
        block: ActionProposalBlock(
          id: id,
          icon: icon,
          title: title,
          description: description,
        ),
      );
}

// ---------------------------------------------------------------------------
// Internal step types — describe the script, not the wire format.
// ---------------------------------------------------------------------------

sealed class _Step {
  const _Step({required this.delay});
  final Duration delay;
}

class _AddBlock extends _Step {
  const _AddBlock({
    required super.delay,
    required this.block,
    this.pendingToolResult,
  });
  final AgentBlock block;
  final String? pendingToolResult;
}

class _FinishTool extends _Step {
  const _FinishTool({
    required super.delay,
    required this.blockId,
    required this.summary,
  });
  final String blockId;
  final String summary;
}

class _AutoFinishTool extends _Step {
  const _AutoFinishTool({required super.delay, required this.blockId});
  final String blockId;
}

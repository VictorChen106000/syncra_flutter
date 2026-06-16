import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/router/route_names.dart';
import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/pipeline_repository.dart';
import '../../../data/firestore/resumes_repository.dart';
import '../../../data/models/job.dart';
import '../../../data/services/jsearch_service.dart';
import '../../../shared/state/running_task_notifier.dart';
import '../../auth/models/user_profile.dart';
import '../../auth/state/auth_notifier.dart';
import '../../auth/state/user_profile_notifier.dart';
import '../../notifications/models/app_notification.dart';
import '../../notifications/state/notifications_notifier.dart';
import '../../jobs/state/jobs_notifier.dart';
import '../../resumes/models/resume_integrity_result.dart';
import '../../resumes/services/resume_parser_service.dart';
import '../../resumes/services/resume_tailor_orchestrator.dart';
import '../../resumes/state/resume_notifier.dart';
import '../models/agent_block.dart';
import '../models/chat_message.dart';
import '../models/conversation_summary.dart';
import '../services/agent_service.dart';
import '../services/anthropic_chat_service.dart';
import '../services/chat_history_repository.dart';
import '../tools/builtin_tools.dart';
import '../tools/tool_registry.dart';
import 'dart:typed_data';

/// Maps the user's autonomy dial to the system directive the agent reads each
/// turn. Sent as a secondary system block (see [AgentService.setAutonomyDirective]).
/// The irreversible send stays code-gated by the email confirmation token in
/// every mode — Autopilot only changes who mints that token (the app, after an
/// undo window) rather than removing the gate.
String _autonomyDirectiveFor(AutonomyLevel level) => switch (level) {
  AutonomyLevel.assist =>
    'ACTIVE AUTONOMY MODE: Assist. After each step, STOP and call `ask_user` '
        'with 2-3 next-step chips before doing the next step — even when the '
        "user stated a multi-step goal. Do NOT chain steps. Don't tailor, "
        'draft, or save without an explicit go-ahead for that step. Never call '
        '`send_email`.',
  AutonomyLevel.autoDraft =>
    'ACTIVE AUTONOMY MODE: Auto-draft. Treat any request to find, search, or '
        'show roles as a full apply goal, not just discovery: carry it out in '
        'one run (find -> match -> save top matches -> tailor -> draft) WITHOUT '
        'pausing to ask permission between steps; narrate each decision in one '
        'short line instead. For a partial match with a missing skill, tailor '
        'with the real resume and note the gap rather than asking. Stop only at '
        'the two human gates handled by the app UI: the user saves the tailored '
        'resume, then the user taps Send. Never call `send_email` yourself.',
  AutonomyLevel.autopilot =>
    'ACTIVE AUTONOMY MODE: Autopilot. Treat any request to find, search, or '
        'show roles as a full apply goal: carry it out in one run (find -> '
        'match -> save top matches -> tailor -> draft) without inter-step asks; '
        'narrate decisions briefly. For a partial match with a missing skill, '
        'tailor with the real resume and note the gap rather than asking. After '
        'you call `draft_email`, the app auto-sends low-risk drafts after a '
        'short Undo window, so tell the user you will send it automatically '
        "unless they tap Undo. Do NOT call `send_email` yourself — the app "
        'performs the confirmed send.',
};

/// The active [AgentService] for the app — Claude via the tool-use loop.
/// Requires an `ANTHROPIC_API_KEY`; without one the agent surfaces an error
/// at call time rather than falling back to scripted responses.
final agentServiceProvider = Provider<AgentService>((ref) {
  final registry = ToolRegistry();
  // One shared JSearchService so the controller can push the user's job region
  // (its default search country) down to the `search_jobs` tool each turn via
  // [AgentService.setSearchCountry].
  final search = JSearchService();
  registerBuiltinTools(registry, jsearch: search);
  return AnthropicChatService(registry: registry, searchService: search);
});

/// Persists the recoverable full chat UI snapshot so chats survive app
/// restarts. Scoped to the signed-in user's Firestore subtree.
final chatHistoryRepositoryProvider = Provider<ChatHistoryRepository>(
  (ref) => ChatHistoryRepository(),
);

/// Live list of saved conversations for the history drawer. Empty for guests
/// — they have no Firestore subtree to read.
final conversationListProvider =
    StreamProvider.autoDispose<List<ConversationSummary>>((ref) {
      final repo = ref.watch(chatHistoryRepositoryProvider);
      final user = ref.watch(authProvider).appUser;
      if (user == null) {
        return Stream.value(const <ConversationSummary>[]);
      }
      return repo.watchConversations(user.uid);
    });

/// One-slot "draft" handed from a prompt card to the chat composer. A prompt
/// card (on the dashboard or in the chat's empty state) drops its prompt here
/// and routes to the chat; [ChatInputBar] picks it up, pre-fills the field,
/// and clears this — nothing sends until the user taps Send. This is what lets
/// the user attach a resume before the prompt actually runs.
final composerDraftProvider = StateProvider<String?>((ref) => null);

/// Set true by onboarding when the user skips uploading a resume. The chat
/// reads it on open and, for a fresh generic chat, greets with a proactive
/// offer to build a resume from scratch — so skipping the upload isn't a dead
/// end. One-shot: the chat clears it once the offer has been seeded.
final pendingResumeBuilderOfferProvider = StateProvider<bool>((ref) => false);

/// Set true by onboarding's "Build one with AI" path. The dashboard's Ask
/// Syncra bar reads it on first build and, after a beat, *auto-presses itself*
/// (a visible press animation) and opens the chat — guiding the no-resume user
/// into the chatbot from the home screen. One-shot: the bar clears it once the
/// guided open has started.
final autoOpenChatProvider = StateProvider<bool>((ref) => false);

@immutable
class AgentChatState {
  const AgentChatState({
    required this.items,
    required this.conversationId,
    this.isStreaming = false,
    this.threadJob,
  });

  final List<ChatItem> items;

  /// Firestore document id this transcript persists to. Switching chats from
  /// the history drawer swaps this; "New chat" mints a fresh one.
  final String conversationId;

  final bool isStreaming;

  /// When set, the chat is scoped to a single job — surfaces a context chip
  /// in the header and gates the opening message to that role.
  final Job? threadJob;

  AgentChatState copyWith({
    List<ChatItem>? items,
    String? conversationId,
    bool? isStreaming,
    Job? threadJob,
    bool clearThreadJob = false,
  }) {
    return AgentChatState(
      items: items ?? this.items,
      conversationId: conversationId ?? this.conversationId,
      isStreaming: isStreaming ?? this.isStreaming,
      threadJob: clearThreadJob ? null : (threadJob ?? this.threadJob),
    );
  }
}

class AgentChatNotifier extends Notifier<AgentChatState> {
  late AgentService _service;
  late ChatHistoryRepository _history;
  late ResumesRepository _resumesRepository;
  late ResumeTailorOrchestrator _orchestrator;
  StreamSubscription<AgentEvent>? _activeSub;
  AgentTurn? _activeTurn;
  Timer? _persistDebounce;
  int _seq = 0;
  bool _hydrating = false;
  bool _persistenceReady = false;
  bool _serviceReady = false;
  bool _threadPipelineMarkedComplete = false;
  String? _pendingIntegrityRepairBlockId;
  String? _activeIntegrityRepairSourceBlockId;

  @override
  AgentChatState build() {
    _service = ref.watch(agentServiceProvider);
    _serviceReady = true;
    _history = ref.watch(chatHistoryRepositoryProvider);
    _resumesRepository = ResumesRepository();
    _orchestrator = ResumeTailorOrchestrator(
      resumesRepository: _resumesRepository,
      jobsRepository: JobsRepository(),
      parser: ResumeParserService(),
    );
    _persistenceReady = true;
    _seq = 0;
    _threadPipelineMarkedComplete = false;
    ref.onDispose(() {
      _serviceReady = false;
      _persistenceReady = false;
      _activeSub?.cancel();
      _persistDebounce?.cancel();
    });

    // Hydrate the most recent saved conversation in the background. We start
    // from a fresh opener and replace once the load completes, *iff* the user
    // hasn't already started a new conversation in the meantime.
    _hydrateFromFirestore();

    return AgentChatState(
      items: [_buildOpener(null)],
      conversationId: _newConversationId(),
    );
  }

  /// Mints a unique Firestore document id for a new conversation.
  String _newConversationId() =>
      'conv-${DateTime.now().microsecondsSinceEpoch}';

  String? get _uid {
    final user = ref.read(authProvider).appUser;
    if (user == null) return null;
    return user.uid;
  }

  /// The global running-task banner. Driven so a prompt's progress stays
  /// visible from any page once the user navigates away from the chat.
  RunningTaskNotifier get _runningTask =>
      ref.read(runningTaskProvider.notifier);

  Future<void> _hydrateFromFirestore() async {
    final uid = _uid;
    if (uid == null) return;
    _hydrating = true;
    try {
      final convos = await _history.listConversations(uid);
      if (convos.isEmpty) return;
      // Only apply hydration if the user hasn't already typed or opened a
      // thread since build() — otherwise we'd clobber their in-progress work.
      final current = state;
      final isUntouched =
          current.items.length == 1 &&
          current.items.first is AgentTurn &&
          current.threadJob == null;
      if (!isUntouched) return;
      final mostRecent = convos.first;
      final saved = await _history.loadConversation(uid, mostRecent.id);
      if (saved.items.isEmpty) return;
      state = AgentChatState(
        items: _restoreHistoryItems(saved.items),
        conversationId: mostRecent.id,
        threadJob: saved.threadJob,
      );
      // Make sure subsequent IDs don't collide with hydrated ones.
      _seq = saved.items.length + 1;
      ref
          .read(resumeProvider.notifier)
          .setSelectedResumes(_resumeIdsFromHistory(saved.items));
      _restoreServiceContext(saved);
      unawaited(_restorePreviewBytesFromStorage());
    } catch (_) {
      // Best-effort hydration; failures are silent so a flaky network never
      // blocks the chat from working.
    } finally {
      _hydrating = false;
    }
  }

  /// Debounced snapshot write for high-frequency UI changes such as streamed
  /// blocks, tool completion updates, and card-state transitions.
  void _schedulePersist() {
    if (_hydrating || !_persistenceReady) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 450), _persistNow);
  }

  /// Immediate snapshot write for durable boundaries: user sends a prompt,
  /// a turn ends/fails/stops, or the user settles a card/action.
  void _persistNow() {
    _persistDebounce?.cancel();
    _persistDebounce = null;

    if (_hydrating || !_persistenceReady) return;
    final uid = _uid;
    if (uid == null) return;

    final items = _itemsForHistory(state.items);
    if (items.isEmpty) return;

    // Fire-and-forget; UI doesn't wait on persistence. The verbatim Anthropic
    // history rides alongside the UI snapshot so a later session can replay the
    // exact turns (full fidelity) rather than a lossy text summary.
    unawaited(
      _history.save(
        uid,
        state.conversationId,
        items: items,
        title: _deriveTitle(items, fallbackJob: state.threadJob),
        threadJob: state.threadJob,
        agentMessages: _service.exportConversation(),
      ),
    );
  }

  /// Restores the agent's working memory from a loaded snapshot — preferring
  /// the verbatim Anthropic history (full fidelity) and falling back to the
  /// lossy UI-snapshot summary only for legacy/oversized transcripts that
  /// never saved one.
  void _restoreServiceContext(SavedConversation saved) {
    if (saved.agentMessages.isNotEmpty) {
      _service.importConversation(saved.agentMessages);
    } else {
      _service.restoreConversationContext(
        saved.items,
        threadJob: saved.threadJob,
      );
    }
  }

  Future<void> _storePreviewBytes(AgentBlock block, List<int> bytes) async {
    final uid = _uid;
    if (uid == null || bytes.isEmpty) return;

    try {
      final path = await _resumesRepository.uploadConversationPreview(
        uid: uid,
        conversationId: state.conversationId,
        blockId: block.id,
        bytes: Uint8List.fromList(bytes),
      );

      switch (block) {
        case ProposedEditsBlock():
          block.previewStoragePath = path;
        case ResumeDraftBlock():
          block.previewStoragePath = path;
        default:
          return;
      }
    } catch (e) {
      debugPrint('chat preview upload failed: $e');
    }
  }

  Future<void> _restorePreviewBytesFromStorage() async {
    final uid = _uid;
    if (uid == null) return;

    var changed = false;

    for (final item in state.items) {
      if (item is! AgentTurn) continue;

      for (final block in item.blocks) {
        if (block is ProposedEditsBlock) {
          final path = block.previewStoragePath;
          if (block.previewBytes != null || path == null || path.isEmpty) {
            continue;
          }

          final bytes = await _resumesRepository.downloadConversationPreview(
            path,
          );
          if (bytes == null || bytes.isEmpty) continue;

          block.previewBytes = bytes;
          changed = true;
          continue;
        }

        if (block is ResumeDraftBlock) {
          final path = block.previewStoragePath;
          if (block.previewBytes != null || path == null || path.isEmpty) {
            continue;
          }

          final bytes = await _resumesRepository.downloadConversationPreview(
            path,
          );
          if (bytes == null || bytes.isEmpty) continue;

          block.previewBytes = bytes;
          changed = true;
        }
      }
    }

    if (!changed) return;
    state = state.copyWith(items: [...state.items]);
  }

  List<ChatItem> _itemsForHistory(List<ChatItem> items) {
    if (items.isEmpty) return const <ChatItem>[];

    final start = items.indexWhere((item) {
      if (item is! AgentTurn) return true;
      return !item.id.startsWith('turn-opener') &&
          item.id != 'turn-history-notice';
    });

    if (start < 0) return const <ChatItem>[];
    return items.sublist(start);
  }

  /// A short conversation label drawn from the first user message — what the
  /// history drawer shows for the row.
  /// A short conversation label for the history drawer.
  String _deriveTitle(List<ChatItem> items, {Job? fallbackJob}) {
    if (fallbackJob != null) {
      final title = fallbackJob.title.trim();
      final company = fallbackJob.company.trim();

      if (title.isNotEmpty && company.isNotEmpty) {
        return '$title · $company';
      }
      if (title.isNotEmpty) return title;
      if (company.isNotEmpty) return company;
    }

    for (final item in items) {
      if (item is UserMessage) {
        final text = item.text.trim();
        if (text.isEmpty) continue;
        return text.length <= 60 ? text : '${text.substring(0, 60).trim()}…';
      }
    }

    for (final item in items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is TextBlock) {
          final text = block.text.trim();
          if (text.isEmpty) continue;
          return text.length <= 60 ? text : '${text.substring(0, 60).trim()}…';
        }
      }
    }

    return 'Saved transcript';
  }

  /// Builds the first agent turn shown when the chat opens. Adapts to the
  /// optional [job] so a thread opened from a pipeline card lands on a
  /// contextual message + a relevant action proposal instead of the
  /// generic welcome.
  AgentTurn _buildOpener(
    Job? job, {
    PipelineStage stage = PipelineStage.matched,
    bool autopilotClaimed = false,
  }) {
    if (job == null) {
      // No greeting bubble: the fresh-chat experience is the empty state
      // ("How can I help today?"). The opener stays as an empty turn purely so
      // the single-agent-item check that triggers the empty state keeps
      // working; it's filtered out of the rendered transcript.
      return AgentTurn(id: 'turn-opener', isStreaming: false);
    }

    // The background autopilot may have already carried this card forward. Read
    // the same pipeline stage it advanced so a tailored / drafted / sent card
    // isn't greeted with a stale "Prepare draft" — the chat and the processor
    // stay in sync instead of colliding.
    final advanced = _openerForAdvancedStage(job, stage);
    if (advanced != null) return advanced;

    // Still `matched` but the autopilot has already claimed it and is mid-run.
    // Show "preparing…" (no action) so the user can't fire a duplicate tailor
    // on a job the background processor is actively working.
    if (autopilotClaimed && stage == PipelineStage.matched) {
      return AgentTurn(
        id: 'turn-opener-${job.id}',
        isStreaming: false,
        blocks: [
          TextBlock(
            id: 'opener-text-${job.id}',
            text:
                "Syncra is preparing your application for ${job.title} at "
                "${job.company} right now — tailoring your résumé and drafting "
                "the outreach. It'll be ready to send in a moment.",
          ),
        ],
      );
    }

    final blocks = <AgentBlock>[];
    switch (job.category) {
      case JobCategory.ready:
        blocks.add(
          TextBlock(
            id: 'opener-text-${job.id}',
            text:
                "I drafted your application for ${job.title} at "
                "${job.company} — ${job.matchLabel.toLowerCase()}. "
                "${job.agentJustification}\n\n"
                "Ready to send it out?",
          ),
        );
        blocks.add(
          ActionProposalBlock(
            id: 'opener-action-${job.id}',
            icon: Icons.send_rounded,
            title: 'Prepare application for ${job.company}',
            description:
                'Tailored resume + outreach draft · user reviews before send',
            acceptLabel: 'Prepare draft',
            editLabel: 'Make changes',
            continuationPrompt:
                '''
      The user approved preparing an application for this matched job.

      Job:
      - job_id: ${job.id}
      - title: ${job.title}
      - company: ${job.company}
      - location: ${job.location}

      Continue the application workflow from here.
      Use tools for safe next steps, such as reading the resume, tailoring if needed, or drafting outreach.
      Do not call send_email. Sending still requires the email review UI and explicit confirmation token.
      ''',
          ),
        );
        break;
      case JobCategory.inputNeeded:
        final missingSkill = job.missingSkills.isEmpty
            ? 'the missing context'
            : job.missingSkills.first;
        final gapNote = job.missingSkills.isEmpty
            ? ''
            : " One gap I spotted: your resume doesn't show $missingSkill, so "
                  "I'll tailor with what you've got and flag it rather than "
                  'invent it.';

        blocks.add(
          TextBlock(
            id: 'opener-text-${job.id}',
            text:
                "I can prepare your application for ${job.title} at "
                "${job.company} — ${job.matchLabel.toLowerCase()}. "
                "${job.agentJustification}$gapNote",
          ),
        );
        blocks.add(
          ActionProposalBlock(
            id: 'opener-action-${job.id}',
            icon: Icons.send_rounded,
            title: 'Prepare application for ${job.company}',
            description:
                'Tailored resume + outreach draft · user reviews before send',
            acceptLabel: 'Prepare draft',
            editLabel: 'Make changes',
            continuationPrompt:
                '''
        The user approved preparing an application for this partial-match job.

        Job:
        - job_id: ${job.id}
        - title: ${job.title}
        - company: ${job.company}
        - location: ${job.location}
        - match: ${job.matchLabel}
        - missing_skill: $missingSkill
        - agent_justification: ${job.agentJustification}

        Continue the application workflow from here. Tailor the resume using ONLY
        the user's real resume facts — do not add the missing skill or any
        unsupported detail. Briefly note the gap in user-visible text, then draft
        outreach. Do not stop to ask whether the user has the missing skill.
        Do not call send_email. Sending still requires the email review UI and explicit confirmation token.
        ''',
          ),
        );
        break;
      case JobCategory.exploration:
        blocks.add(
          TextBlock(
            id: 'opener-text-${job.id}',
            text:
                "Worth considering: ${job.title} at ${job.company}. "
                "${job.agentJustification}",
          ),
        );
        blocks.add(
          ActionProposalBlock(
            id: 'opener-action-${job.id}',
            icon: Icons.auto_awesome_rounded,
            title: 'Draft a pitch for ${job.company}',
            description: 'I\'ll tailor your resume + draft outreach',
            acceptLabel: 'Draft it',
            editLabel: 'Pass on this',
            continuationPrompt:
                '''
      The user approved exploring this job and drafting a pitch.

      Job:
      - job_id: ${job.id}
      - title: ${job.title}
      - company: ${job.company}
      - location: ${job.location}

      Continue the workflow from here.
      First make sure the user's resume context is available.
      If tailoring is useful, propose resume edits and stop for the diff viewer.
      If outreach is the next safe step, draft the email.
      Do not call send_email. Sending still requires explicit user approval.
      ''',
          ),
        );
        break;
    }

    return AgentTurn(
      id: 'turn-opener-${job.id}',
      blocks: blocks,
      isStreaming: false,
    );
  }

  /// A stage-aware opener for a card the background autopilot already advanced.
  /// Returns null for a still-`matched` card so [_buildOpener] falls through to
  /// its category-based "prepare draft" greeting; otherwise it reflects the real
  /// progress (tailored → offer to draft, drafted → review & send, sent → done).
  AgentTurn? _openerForAdvancedStage(Job job, PipelineStage stage) {
    switch (stage) {
      case PipelineStage.matched:
        return null;
      case PipelineStage.tailored:
      case PipelineStage.drafted:
        final isDrafted = stage == PipelineStage.drafted;
        return AgentTurn(
          id: 'turn-opener-${job.id}',
          isStreaming: false,
          blocks: [
            TextBlock(
              id: 'opener-text-${job.id}',
              text: isDrafted
                  ? "Your application for ${job.title} at ${job.company} is "
                        "tailored and the outreach is drafted — ready to send. "
                        "Want me to send it, or make changes first?"
                  : "I've tailored your résumé for ${job.title} at "
                        "${job.company}. Want me to draft the outreach next?",
            ),
            ActionProposalBlock(
              id: 'opener-action-${job.id}',
              icon: Icons.send_rounded,
              title: 'Continue application for ${job.company}',
              description: isDrafted
                  ? 'Review the outreach draft and send'
                  : 'Draft outreach from your tailored résumé',
              acceptLabel: isDrafted ? 'Review & send' : 'Draft outreach',
              editLabel: 'Make changes',
              continuationPrompt:
                  '''
        The user opened a pipeline job the background autopilot already advanced to "${stage.name}".

        Job:
        - job_id: ${job.id}
        - title: ${job.title}
        - company: ${job.company}
        - location: ${job.location}

        The résumé is already tailored for this role — do NOT re-tailor unless the user asks.
        Continue toward outreach: draft (or refine) the recruiter email so the user can review and send it.
        Do not call send_email. Sending still requires the email review UI and explicit confirmation token.
        ''',
            ),
          ],
        );
      case PipelineStage.sent:
      case PipelineStage.replied:
        return AgentTurn(
          id: 'turn-opener-${job.id}',
          isStreaming: false,
          blocks: [
            TextBlock(
              id: 'opener-text-${job.id}',
              text:
                  "Your application to ${job.company} for ${job.title} is "
                  "already sent — it's in your tracker now. Want me to find "
                  "more roles like it or prep a follow-up?",
            ),
          ],
        );
    }
  }

  List<ChatItem> _restoreHistoryItems(List<ChatItem> saved) {
    if (saved.isEmpty) return [_buildOpener(null)];
    return [...saved];
  }

  /// Scopes the chat to [job] and replaces the opener with a contextual
  /// turn. Called by the pipeline when a card is tapped — the chatbot is
  /// the single thread for every agentic interaction.
  void openJobThread(
    Job job, {
    PipelineStage stage = PipelineStage.matched,
    bool autopilotClaimed = false,
  }) {
    final currentThreadJob = state.threadJob;

    if (currentThreadJob != null && currentThreadJob.id == job.id) {
      return;
    }

    _persistNow();
    _service.resetConversation();
    _threadPipelineMarkedComplete = false;
    state = AgentChatState(
      items: [_buildOpener(job, stage: stage, autopilotClaimed: autopilotClaimed)],
      conversationId: _newConversationId(),
      threadJob: job,
    );
  }

  /// Starts a fresh, generic conversation. The previous one is already saved
  /// to history (if it had content), so nothing is lost — no confirm needed.
  void newConversation() {
    if (state.isStreaming) return;
    _persistNow();
    _service.resetConversation();
    _threadPipelineMarkedComplete = false;
    state = AgentChatState(
      items: [_buildOpener(null)],
      conversationId: _newConversationId(),
    );
  }

  /// Seeds the opener of a fresh, generic chat with a proactive offer to build
  /// a resume from scratch — used right after the user skips the onboarding
  /// resume upload, so the hand-off to the dashboard isn't a dead end. No-op if
  /// a stream is running, the chat is scoped to a job thread, or the user has
  /// already started a conversation. The seeded turn keeps a `turn-opener-` id
  /// so it stays out of saved history (see [_itemsForHistory]).
  void offerResumeBuild() {
    if (state.isStreaming) return;
    if (state.threadJob != null) return;
    final items = state.items;
    final isFreshOpener =
        items.length == 1 &&
        items.first is AgentTurn &&
        (items.first as AgentTurn).blocks.isEmpty;
    if (!isFreshOpener) return;

    final turn = AgentTurn(
      id: 'turn-opener-resume-offer',
      isStreaming: false,
      blocks: [
        TextBlock(
          id: 'opener-resume-text',
          text:
              "Hey — looks like you skipped uploading a resume. No problem: I "
              "can build one with you from scratch. A few quick questions and "
              "I'll draft it for you to review.",
        ),
        ActionProposalBlock(
          id: 'opener-resume-action',
          icon: Icons.auto_awesome_rounded,
          title: 'Build my resume',
          description: "A few quick questions, then I'll draft it for you",
          acceptLabel: 'Build my resume',
          editLabel: 'Maybe later',
          continuationPrompt: '''
The user has no resume yet and asked you to build one from scratch.
Start the from-scratch resume builder now. Greet briefly, then begin gathering what you need.
Call ask_user for the first piece — their name and contact details — with short suggestion chips where helpful.
Across a few short turns, collect their work experience, education, and skills.
When you have enough, call build_resume ONCE with the full structure. It renders a preview only; the user previews the PDF and taps Save.
Do not call send_email.
''',
        ),
      ],
    );

    state = state.copyWith(items: [turn]);
  }

  /// Clears the live chat after account reset without saving the old transcript.
  ///
  /// Account reset already deletes Firestore conversations. This method only
  /// clears the in-memory chat/provider state so a deleted conversation does not
  /// remain visible until app restart.
  void resetAfterAccountReset() {
    _activeSub?.cancel();
    _activeSub = null;
    _activeTurn = null;
    _persistDebounce?.cancel();
    _persistDebounce = null;

    _service.resetConversation();
    _threadPipelineMarkedComplete = false;
    _pendingIntegrityRepairBlockId = null;
    _activeIntegrityRepairSourceBlockId = null;
    _seq = 0;

    ref.read(composerDraftProvider.notifier).state = null;
    ref.read(resumeProvider.notifier).clearSelectedResumes();
    _runningTask.dismiss();

    state = AgentChatState(
      items: [_buildOpener(null)],
      conversationId: _newConversationId(),
    );
  }

  /// Starts a brand-new generic chat and immediately sends [prompt].
  ///
  /// Used by entry points like Resumes → Build with AI that must not append
  /// their prompt into a restored/history conversation.
  void startFreshPrompt({
    required String prompt,
    List<ChatAttachment> attachments = const [],
  }) {
    if (state.isStreaming) return;

    _persistNow();
    _service.resetConversation();
    _threadPipelineMarkedComplete = false;
    state = AgentChatState(
      items: [_buildOpener(null)],
      conversationId: _newConversationId(),
    );

    sendPrompt(prompt: prompt, attachments: attachments);
  }

  /// Loads a saved conversation from history into the live transcript.
  Future<void> switchConversation(String conversationId) async {
    if (state.isStreaming) return;
    if (conversationId == state.conversationId) return;
    final uid = _uid;
    if (uid == null) return;
    _persistNow();
    _service.resetConversation();
    _threadPipelineMarkedComplete = false;
    final saved = await _history.loadConversation(uid, conversationId);
    state = AgentChatState(
      items: _restoreHistoryItems(saved.items),
      conversationId: conversationId,
      threadJob: saved.threadJob,
    );
    // Make sure subsequent IDs don't collide with loaded ones.
    _seq = saved.items.length + 1;
    // Continue the chat with the resume it was already using — sync the
    // attachment selection to that conversation's latest user message so
    // the "RESUME IN USE" card (and the next send) stay consistent.
    ref
        .read(resumeProvider.notifier)
        .setSelectedResumes(_resumeIdsFromHistory(saved.items));
    _restoreServiceContext(saved);
    unawaited(_restorePreviewBytesFromStorage());
  }

  /// Resume ids attached to the most recent [UserMessage] in a loaded
  /// transcript — empty if that conversation used no resume.
  Set<String> _resumeIdsFromHistory(List<ChatItem> items) {
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item is UserMessage) {
        return item.attachments.map((a) => a.id).toSet();
      }
    }
    return const {};
  }

  /// Permanently deletes a saved conversation. If it's the one on screen,
  /// drops to a fresh chat.
  Future<void> deleteConversation(String conversationId) async {
    final uid = _uid;
    if (uid == null) return;
    await _history.delete(uid, conversationId);
    if (conversationId == state.conversationId) {
      _service.resetConversation();
      _threadPipelineMarkedComplete = false;
      state = AgentChatState(
        items: [_buildOpener(null)],
        conversationId: _newConversationId(),
      );
    }
  }

  Future<void> renameConversation(String conversationId, String title) async {
    final uid = _uid;
    final cleanTitle = title.trim();
    if (uid == null || cleanTitle.isEmpty) return;
    await _history.rename(uid, conversationId, title: cleanTitle);
  }

  Future<void> setConversationPinned(
    String conversationId, {
    required bool pinned,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _history.setPinned(uid, conversationId, pinned: pinned);
  }

  String _nextId(String prefix) {
    _seq += 1;
    return '$prefix-$_seq';
  }

  void sendPrompt({
    required String prompt,
    List<ChatAttachment> attachments = const [],
  }) {
    final clean = prompt.trim();
    if (clean.isEmpty || state.isStreaming) return;

    final next = [
      ...state.items,
      UserMessage(id: _nextId('user'), text: clean, attachments: attachments),
    ];
    final turn = AgentTurn(id: _nextId('turn'));
    _activeTurn = turn;
    state = state.copyWith(items: [...next, turn], isStreaming: true);
    _persistNow();
    _runningTask.start(
      'Prompt is running…',
      // Stay quiet on the agent chat and the resume-flow surfaces — the user
      // can already see the work inline there. The pill reappears the moment
      // they navigate to a different surface.
      originRoutes: const {
        RouteNames.agentChat,
        RouteNames.resumes,
        RouteNames.resumePreview,
      },
    );

    _syncAutonomyDirective();
    _syncSearchRegion();
    _activeSub = _service
        .runPrompt(prompt: clean, attachments: attachments)
        .listen(
          _handleEvent,
          onDone: _finishTurn,
          onError: (Object e) => _failActiveTurn('Something went wrong. $e'),
        );
  }

  /// Pushes the user's active autonomy level down to the agent service before a
  /// turn runs, so the model advances exactly as far as the dial allows. Read
  /// fresh each turn so a mid-session change in Profile takes effect at once.
  void _syncAutonomyDirective() {
    final level =
        ref.read(userProfileProvider)?.autonomyLevel ?? AutonomyLevel.autopilot;
    _service.setAutonomyDirective(_autonomyDirectiveFor(level));
  }

  /// Pushes the user's selected job region down to the agent's live job search
  /// before a turn runs, so `search_jobs` scopes to that country. Read fresh
  /// each turn so a mid-session change in Profile takes effect at once.
  void _syncSearchRegion() {
    final region =
        ref.read(userProfileProvider)?.jobRegion ?? JobRegion.unitedStates;
    _service.setSearchRegion(region.code, region.label);
  }

  void _startContinuationPrompt(String prompt) {
    final clean = prompt.trim();
    if (clean.isEmpty) return;
    if (state.isStreaming) return;
    if (!_serviceReady) return;

    final turn = AgentTurn(id: _nextId('turn'));
    _activeTurn = turn;

    state = state.copyWith(items: [...state.items, turn], isStreaming: true);
    _persistNow();

    _syncAutonomyDirective();
    _syncSearchRegion();
    _activeSub = _service
        .runPrompt(prompt: clean, threaded: true)
        .listen(
          _handleEvent,
          onDone: _finishTurn,
          onError: (Object e) => _failActiveTurn('Something went wrong. $e'),
        );
  }

  void _continueAfterSavedResume(ProposedEditsBlock block) {
    final tailoredResumeId = block.savedResumeId;
    if (tailoredResumeId == null || tailoredResumeId.isEmpty) return;

    final sourceResumeId =
        block.resolvedResumeId ?? block.resumeId ?? 'unknown';
    final jobId = block.jobId ?? 'unknown';
    final integrity = block.integrity;
    final integrityStatus = integrity?.status.name ?? 'not_run';
    final integritySummary =
        integrity?.summary ?? 'No Resume Integrity Check result was attached.';

    _startContinuationPrompt('''
The user approved the proposed resume edits and saved the tailored resume.

Approval result:
- source_resume_id: $sourceResumeId
- tailored_resume_id: $tailoredResumeId
- job_id: $jobId
- applied_count: ${block.appliedCount}
- skipped_count: ${block.skippedCount}
- integrity_status: $integrityStatus
- integrity_summary: $integritySummary

Continue the original application workflow from here without asking the user to repeat the task.
Use tailored_resume_id as the resume_id for the next steps.
If integrity_status is verified, continue normally.
If integrity_status is needsReview, mention that the user saved despite warnings and do not claim the resume is guaranteed safe.
If integrity_status is blocked, stop and ask the user to review the resume integrity issue; this should be unusual because saving is disabled.
Now offer outreach: call ask_user to ask whether they want you to draft recruiter outreach for this role, with
chips like ["Draft recruiter outreach", "Not yet", "Save for later"]. Only call draft_email after the user confirms.
If they confirm, call resolve_company_contact before draft_email. If confidence is low or none, draft only and tell the user to verify or replace the recipient.
Do not call send_email. Sending still requires explicit user approval.
''');
  }

  void _handleEvent(AgentEvent event) {
    final turn = _activeTurn;
    if (turn == null) return;
    switch (event) {
      case BlockAdded(:final block):
        turn.blocks.add(block);
        _reflectRunningTask(block);
        if (block is ProposedEditsBlock) {
          _markIntegrityRepairReplacement(block);
        }
        // A freshly-tailored edits card arrives already "applied" but with no
        // rendered PDF — render it now so its preview has bytes to show.
        if (block is ProposedEditsBlock &&
            block.state == ProposedEditsState.applied &&
            block.previewBytes == null) {
          unawaited(_autoRenderAppliedEdits(block));
        }
        // A from-scratch resume draft lands with no rendered PDF — render it
        // now so its preview has bytes to show.
        if (block is ResumeDraftBlock &&
            block.state == ResumeDraftState.rendering &&
            block.previewBytes == null) {
          unawaited(_autoRenderResumeDraft(block));
        }
      case ToolCallCompleted(
        :final blockId,
        :final summary,
        :final status,
        :final detail,
      ):
        ToolCallBlock? completedTool;

        for (final b in turn.blocks) {
          if (b is ToolCallBlock && b.id == blockId) {
            b.status = status;
            b.resultSummary = summary;
            if (detail != null) b.detail = detail;
            completedTool = b;
            break;
          }
        }

        if (status == ToolCallStatus.done && completedTool != null) {
          final toolName = completedTool.name;
          if (toolName == 'save_to_pipeline' || toolName == 'save_to_tracker') {
            final jobId = _jobIdFromToolDetail(completedTool.detail);
            if (jobId != null && jobId.isNotEmpty) {
              _markJobHandledEverywhere(jobId);
            }
          }
        }
      case JobsBlockUpdated(:final blockId, :final jobs):
        // match_jobs re-scored the rail search_jobs already rendered — swap in
        // the scored roles in place so the same roles don't appear twice.
        for (final b in turn.blocks) {
          if (b is JobsBlock && b.id == blockId) {
            b.jobs = jobs;
            break;
          }
        }
      case TurnCompleted():
        _finishTurn();
        return;
      case TurnFailed(:final message):
        _failActiveTurn(message);
        return;
    }
    // Mirror the event to the notifications inbox with tool-aware copy and
    // Accept/Make-changes affordances for proposals, so the user can settle
    // a block from the banner without opening the chat.
    _mirrorToInbox(event, turn);
    // Rebuild the outer items list so Riverpod sees a new reference.
    state = state.copyWith(items: [...state.items]);
    _schedulePersist();
  }

  /// Mirrors *actionable* agent events onto the inbox. Only events that
  /// genuinely need the user — `ask_user` (intercept) and Accept/Make-changes
  /// proposals — produce a notification. Plain tool completions are visible
  /// via the running pill's "Task completed" state; we deliberately don't
  /// pile "Open chat" rows on top of that.
  void _mirrorToInbox(AgentEvent event, AgentTurn turn) {
    final inbox = ref.read(notificationsProvider.notifier);
    switch (event) {
      case BlockAdded(:final block) when block is InputRequestBlock:
        inbox.add(
          AppNotification(
            id: 'n-input-${block.id}',
            kind: NotificationKind.intercept,
            title: 'Agent needs your input',
            body: block.question,
            timestamp: 'Just now',
            actionLabel: 'Answer',
            targetBlockId: block.id,
          ),
        );
      case BlockAdded(:final block) when block is ActionProposalBlock:
        inbox.add(
          AppNotification(
            id: 'n-prop-${block.id}',
            kind: NotificationKind.proposal,
            title: block.title,
            body: block.description,
            timestamp: 'Just now',
            actionLabel: block.acceptLabel,
            secondaryActionLabel: block.editLabel,
            targetBlockId: block.id,
          ),
        );
      case _:
        break;
    }
  }

  /// Mirrors the agent's progress onto the global running-task banner so it
  /// stays meaningful from any page: each tool call relabels the banner with
  /// that tool's UI label ("Tailoring resume…", "Searching jobs…"), and an
  /// `ask_user` pause flips it to a waiting state.
  void _reflectRunningTask(AgentBlock block) {
    if (block is ToolCallBlock) {
      _runningTask.update(block.label);
    } else if (block is InputRequestBlock) {
      _runningTask.update('Waiting for your input…');
    }
  }

  void _ensureNextStepChoiceAfterPipelineSave(AgentTurn turn) {
    if (_turnAlreadyNeedsUserChoice(turn)) return;
    if (!_turnSavedToPipeline(turn)) return;

    final rankedJobs = _latestRankedJobsForNextStep(turn);
    final input = InputRequestBlock(
      id: _nextId('input'),
      question: 'Saved to Pipeline. What should I do next?',
      suggestions: const [
        'Tailor for the strongest saved role',
        'Open Pipeline',
        'Search more roles',
      ],
      continuationPrompt: _pipelineSavedNextStepPrompt(rankedJobs),
    );

    turn.blocks.add(input);
    _mirrorToInbox(BlockAdded(input), turn);
  }

  bool _turnSavedToPipeline(AgentTurn turn) {
    for (final block in turn.blocks) {
      if (block is ToolCallBlock &&
          block.name == 'save_to_pipeline' &&
          block.status == ToolCallStatus.done) {
        return true;
      }
    }
    return false;
  }

  List<Job> _latestRankedJobsForNextStep(AgentTurn activeTurn) {
    for (final block in activeTurn.blocks.reversed) {
      if (block is JobsBlock && block.jobs.isNotEmpty) {
        return _rankJobsForNextStep(block.jobs);
      }
    }

    for (var i = state.items.length - 1; i >= 0; i--) {
      final item = state.items[i];
      if (item is! AgentTurn) continue;

      for (final block in item.blocks.reversed) {
        if (block is JobsBlock && block.jobs.isNotEmpty) {
          return _rankJobsForNextStep(block.jobs);
        }
      }
    }

    return const [];
  }

  String _pipelineSavedNextStepPrompt(List<Job> rankedJobs) {
    final topJobs = rankedJobs.take(5).toList(growable: false);

    if (topJobs.isEmpty) {
      return '''
The user just saved roles to Pipeline.

Use the user's answer to continue:
- If they choose "Tailor for the strongest saved role", ask which saved role they want to tailor for with 2-3 short suggestion chips.
- If they choose "Open Pipeline", briefly tell them Pipeline now contains the saved roles and they can open it from the Jobs tab.
- If they choose "Search more roles", call search_jobs and then continue the standard job-search sequence.
- Do not show numeric match scores in user-visible text.
- Do not call send_email.
- If the next action needs approval or missing information, call ask_user with 2-3 clear suggestion chips.
''';
    }

    final topRole = topJobs.first;
    final jobContext = topJobs.map(_jobContextLine).join('\n');

    return '''
The user just saved roles to Pipeline.

Saved/matched job context, sorted strongest-first:
$jobContext

Recommended strongest saved role:
- job_id: ${topRole.id}
- title: ${topRole.title}
- company: ${topRole.company}

Use the user's answer to continue:
- If they choose "Tailor for the strongest saved role", call read_resume if needed, then call tailor_resume for the recommended strongest saved role.
- If they choose "Open Pipeline", briefly tell them Pipeline now contains these saved roles and they can open it from the Jobs tab. Do not call tools for this.
- If they choose "Search more roles", call search_jobs with a related query based on the saved roles, then continue the standard job-search sequence.
- Do not show numeric match scores in user-visible text.
- Do not call draft_email until after a tailored resume is saved or the user directly asks for outreach.
- Do not call send_email.
- If the next action needs approval or missing information, call ask_user with 2-3 clear suggestion chips.
''';
  }

  void _ensureNextStepChoiceAfterJobResults(AgentTurn turn) {
    if (_turnAlreadyNeedsUserChoice(turn)) return;

    JobsBlock? latestJobsBlock;
    for (final block in turn.blocks.reversed) {
      if (block is JobsBlock && block.jobs.isNotEmpty) {
        latestJobsBlock = block;
        break;
      }
    }

    final jobsBlock = latestJobsBlock;
    if (jobsBlock == null) return;

    final rankedJobs = _rankJobsForNextStep(jobsBlock.jobs);
    if (rankedJobs.isEmpty) return;

    final input = InputRequestBlock(
      id: _nextId('input'),
      question: 'What should I do with these matches next?',
      suggestions: const [
        'Save top 3 to Pipeline',
        'Tailor for the top role',
        'Explore one role',
      ],
      continuationPrompt: _jobResultsNextStepPrompt(rankedJobs),
    );

    turn.blocks.add(input);
    _mirrorToInbox(BlockAdded(input), turn);
  }

  bool _turnAlreadyNeedsUserChoice(AgentTurn turn) {
    for (final block in turn.blocks) {
      if (block is InputRequestBlock &&
          block.state == InputRequestState.pending) {
        return true;
      }
      if (block is ActionProposalBlock && block.state == ActionState.pending) {
        return true;
      }
      if (block is ProposedEditsBlock &&
          block.state != ProposedEditsState.dismissed) {
        return true;
      }
      if (block is EmailDraftBlock &&
          block.status == EmailDraftStatus.reviewing) {
        return true;
      }
      if (block is ResumeDraftBlock && !block.isSaved) {
        return true;
      }
    }
    return false;
  }

  List<Job> _rankJobsForNextStep(List<Job> jobs) {
    final ranked = [...jobs];
    ranked.sort((a, b) {
      final categoryCompare = _jobCategoryPriority(
        a.category,
      ).compareTo(_jobCategoryPriority(b.category));
      if (categoryCompare != 0) return categoryCompare;

      // Internal-only sort signal. The UI still shows qualitative labels only.
      return b.matchScore.compareTo(a.matchScore);
    });
    return ranked;
  }

  int _jobCategoryPriority(JobCategory category) {
    return switch (category) {
      JobCategory.ready => 0,
      JobCategory.inputNeeded => 1,
      JobCategory.exploration => 2,
    };
  }

  String _jobResultsNextStepPrompt(List<Job> rankedJobs) {
    final topJobs = rankedJobs.take(5).toList(growable: false);
    final topThreeIds = topJobs.take(3).map((job) => job.id).join(', ');
    final topRole = topJobs.first;
    final jobContext = topJobs.map(_jobContextLine).join('\n');

    return '''
The user reviewed the matched job results and chose a next step.

Available matched jobs, already sorted strongest-first:
$jobContext

Recommended top role:
- job_id: ${topRole.id}
- title: ${topRole.title}
- company: ${topRole.company}

Top 3 job_ids:
$topThreeIds

Use the user's answer to continue:
- If they choose "Save top 3 to Pipeline", call save_to_pipeline for the top 3 job_ids.
- If they choose "Tailor for the top role", call tailor_resume for the recommended top role.
- If they choose "Explore one role", compare the strongest roles briefly and ask which one they want to continue with if needed.
- Do not show numeric match scores in user-visible text.
- Do not call send_email.
- If the next action needs approval or missing information, call ask_user with 2-3 clear suggestion chips.
''';
  }

  String _jobContextLine(Job job) {
    final reason = job.agentJustification.trim().isNotEmpty
        ? job.agentJustification.trim()
        : job.why.trim();
    final matched = job.skills.isEmpty ? 'none listed' : job.skills.join(', ');
    final gaps = job.missingSkills.isEmpty
        ? 'none listed'
        : job.missingSkills.join(', ');

    return '''
- job_id: ${job.id}
  title: ${job.title}
  company: ${job.company}
  location: ${job.location}
  match_label: ${job.matchLabel}
  reason: ${reason.isEmpty ? 'Not provided' : reason}
  matched_signals: $matched
  gaps: $gaps''';
  }

  void _finishTurn() {
    final turn = _activeTurn;
    if (turn != null && turn.status == AgentTurnStatus.streaming) {
      _ensureNextStepChoiceAfterPipelineSave(turn);
      _ensureNextStepChoiceAfterJobResults(turn);
      turn.status = AgentTurnStatus.done;
    }
    _activeTurn = null;
    _activeSub?.cancel();
    _activeSub = null;
    state = state.copyWith(items: [...state.items], isStreaming: false);
    _runningTask.complete();
    _clearActiveIntegrityRepairIfStalled();
    _persistNow();
    _startPendingIntegrityRepair();
  }

  void _markIntegrityRepairReplacement(ProposedEditsBlock replacement) {
    final sourceId = _activeIntegrityRepairSourceBlockId;
    if (sourceId == null || replacement.id == sourceId) return;

    final source = _findProposedEdits(sourceId);
    if (source != null) {
      source.integrityAutoRepairing = false;
      source.supersededByBlockId = replacement.id;
      source.applyError = null;
    }

    replacement.integrityRepairAttempted = true;
    replacement.integrityAutoRepairing = false;
    _activeIntegrityRepairSourceBlockId = null;
    _pendingIntegrityRepairBlockId = null;
  }

  void _clearActiveIntegrityRepairIfStalled({String? message}) {
    final sourceId = _activeIntegrityRepairSourceBlockId;
    if (sourceId == null) return;

    _activeIntegrityRepairSourceBlockId = null;
    final source = _findProposedEdits(sourceId);
    if (source == null) return;

    source.integrityAutoRepairing = false;
    source.applyError ??=
        message ??
        'Syncra could not produce a safer revision. Try Fix with Syncra again.';
    state = state.copyWith(items: [...state.items]);
  }

  void _clearPendingIntegrityRepair({String? message}) {
    final pendingId = _pendingIntegrityRepairBlockId;
    if (pendingId == null) return;

    _pendingIntegrityRepairBlockId = null;
    final source = _findProposedEdits(pendingId);
    if (source == null) return;

    source.integrityAutoRepairing = false;
    source.applyError ??=
        message ??
        'Syncra could not start a safer revision. Try Fix with Syncra again.';
    state = state.copyWith(items: [...state.items]);
  }

  void _startPendingIntegrityRepair() {
    final pendingId = _pendingIntegrityRepairBlockId;
    if (pendingId == null || state.isStreaming) return;

    final block = _findProposedEdits(pendingId);
    if (block == null || !block.integrityAutoRepairing) {
      _pendingIntegrityRepairBlockId = null;
      return;
    }

    _beginIntegrityRepair(block);
  }

  void _failActiveTurn(String message) {
    final turn = _activeTurn;
    if (turn != null) {
      turn.status = AgentTurnStatus.failed;
      turn.errorMessage = message;
    }
    _activeTurn = null;
    _activeSub?.cancel();
    _activeSub = null;
    state = state.copyWith(items: [...state.items], isStreaming: false);
    _runningTask.fail();
    _clearPendingIntegrityRepair(
      message: 'Syncra could not start the safer revision.',
    );
    _clearActiveIntegrityRepairIfStalled(
      message:
          'Syncra could not finish the safer revision. Try Fix with Syncra again.',
    );
    _persistNow();
  }

  void stopStreaming() {
    if (!state.isStreaming) return;
    final turn = _activeTurn;
    if (turn != null) turn.status = AgentTurnStatus.stopped;
    _activeTurn = null;
    _activeSub?.cancel();
    _activeSub = null;
    state = state.copyWith(items: [...state.items], isStreaming: false);
    _runningTask.dismiss();
    _clearPendingIntegrityRepair(
      message: 'Safer revision stopped before Syncra could start it.',
    );
    _clearActiveIntegrityRepairIfStalled(
      message: 'Safer revision stopped before Syncra could finish it.',
    );
    _persistNow();
  }

  /// Drops the most recent [AgentTurn] and re-runs the user prompt that
  /// triggered it. No-op if there is no preceding user message (e.g. only the
  /// opener turn is present) or if a stream is already in flight.
  void regenerateLastTurn() {
    if (state.isStreaming) return;
    final items = state.items;
    int lastTurnIdx = -1;
    for (var i = items.length - 1; i >= 0; i--) {
      if (items[i] is AgentTurn) {
        lastTurnIdx = i;
        break;
      }
    }
    if (lastTurnIdx <= 0) return;
    final priorUser = items[lastTurnIdx - 1];
    if (priorUser is! UserMessage) return;

    state = state.copyWith(items: items.sublist(0, lastTurnIdx - 1));
    sendPrompt(prompt: priorUser.text, attachments: priorUser.attachments);
  }

  void acceptProposal(String blockId) {
    final block = _findProposal(blockId);
    if (block == null) return;
    if (block.state != ActionState.pending) return;

    block.state = ActionState.accepted;
    ref.read(notificationsProvider.notifier).markReadByTargetBlock(blockId);
    state = state.copyWith(items: [...state.items]);
    _persistNow();

    _continueAfterAcceptedProposal(block);
  }

  void _continueAfterAcceptedProposal(ActionProposalBlock block) {
    if (!_serviceReady) return;

    final explicit = block.continuationPrompt?.trim();
    final prompt = (explicit != null && explicit.isNotEmpty)
        ? explicit
        : '''
  The user accepted this proposed agent action.

  Accepted proposal:
  - title: ${block.title}
  - description: ${block.description}
  - accepted_label: ${block.acceptLabel}

  Continue the original workflow from here without asking the user to repeat the task.
  Use tools for safe next steps.
  Pause again if you need missing user information or if the next action requires approval.
  Do not call send_email unless the app provides an explicit user-confirmation token or says the user tapped Send in the email review UI.
  ''';

    _startContinuationPrompt(prompt);
  }

  void _continueAfterInputAnswer(InputRequestBlock block, String answer) {
    if (!_serviceReady) return;

    final continuation = block.continuationPrompt?.trim();
    if (continuation == null || continuation.isEmpty) return;

    _startContinuationPrompt('''
  $continuation

  User answered:
  - question: ${block.question}
  - answer: $answer

  Continue the original workflow from here without asking the user to repeat the task.
  Use the user's answer as context for the next decision.
  Use tools for safe next steps.
  If tailoring is useful, propose resume edits and stop for the diff viewer.
  If outreach is the next safe step, draft the email only; do not send.
  Never call send_email unless the app provides an explicit user-confirmation token or says the user tapped Send.
  ''');
  }

  void _continueAfterRestoredInputAnswer(
    InputRequestBlock block,
    String answer,
  ) {
    if (!_serviceReady) return;

    _startContinuationPrompt('''
The user answered an input request from a restored or resumed Syncra chat.

Question:
${block.question}

User answer:
$answer

Continue the workflow from here without asking the same question again.
Use the answer as context for the next safe step.
Use tools when needed.
If building a resume from scratch, continue collecting the missing resume details or call build_resume once enough information exists.
If the next step needs user approval, call ask_user with 2-3 clear suggestion chips.
Do not call send_email.
''');
  }

  void dismissProposal(String blockId) {
    final block = _findProposal(blockId);
    if (block == null) return;
    block.state = ActionState.dismissed;
    ref.read(notificationsProvider.notifier).markReadByTargetBlock(blockId);
    state = state.copyWith(items: [...state.items]);
    _persistNow();
  }

  ActionProposalBlock? _findProposal(String blockId) {
    for (final item in state.items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is ActionProposalBlock && block.id == blockId) return block;
      }
    }
    return null;
  }

  /// Public lookup for a [ProposedEditsBlock] by id — used by the preview
  /// screen to read the rendered bytes / saved state reactively.
  ProposedEditsBlock? proposedEditsBlock(String blockId) =>
      _findProposedEdits(blockId);

  /// Starts an agentic revision of a rendered tailored resume from the preview
  /// screen. The agent must call `tailor_resume` again and stop at a replacement
  /// diff, preserving the same source resume and job context.
  bool requestTailoredResumeRevision(String blockId) {
    final block = _findProposedEdits(blockId);
    if (block == null) return false;
    if (block.state != ProposedEditsState.applied) return false;
    if (block.integrityAutoRepairing) return false;
    if (!_serviceReady || state.isStreaming) return false;

    block.integrityRepairAttempted = true;
    block.integrityAutoRepairing = true;
    block.applyError = null;
    block.supersededByBlockId = null;
    state = state.copyWith(items: [...state.items]);
    _persistNow();

    return _beginIntegrityRepair(block);
  }

  ProposedEditsBlock? _findProposedEdits(String blockId) {
    for (final item in state.items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is ProposedEditsBlock && block.id == blockId) return block;
      }
    }
    return null;
  }

  void _maybeStartIntegrityRepair(ProposedEditsBlock block) {
    final integrity = block.integrity;
    if (integrity == null) return;
    if (integrity.status == ResumeIntegrityStatus.verified) return;
    if (block.integrityRepairAttempted || block.integrityAutoRepairing) return;
    if (block.isSaved) return;
    if (!_serviceReady) return;

    block.integrityRepairAttempted = true;
    block.integrityAutoRepairing = true;
    block.applyError = null;
    block.supersededByBlockId = null;
    state = state.copyWith(items: [...state.items]);
    _persistNow();

    _beginIntegrityRepair(block);
  }

  bool _beginIntegrityRepair(ProposedEditsBlock block) {
    if (!_serviceReady) return false;
    if (state.isStreaming) {
      _pendingIntegrityRepairBlockId = block.id;
      return true;
    }

    _pendingIntegrityRepairBlockId = null;
    _activeIntegrityRepairSourceBlockId = block.id;
    _startContinuationPrompt(_tailoredResumeRevisionPrompt(block));
    return true;
  }

  String _tailoredResumeRevisionPrompt(ProposedEditsBlock block) {
    final resolvedResumeId =
        block.resolvedResumeId ?? block.resumeId ?? 'unknown';
    final sourceResumeId = block.resumeId ?? resolvedResumeId;
    final jobId = block.jobId ?? 'unknown';
    final integrity = block.integrity;
    final integrityStatus = integrity?.status.name ?? 'not_run';
    final integritySummary =
        integrity?.summary ?? 'No Resume Integrity Check result was attached.';
    final trigger = integrity == null
        ? 'The user chose to keep editing the tailored resume.'
        : 'The Resume Integrity Check found issues in the tailored resume.';

    return '''
$trigger

Revision target:
- source_resume_id: $sourceResumeId
- resolved_resume_id: $resolvedResumeId
- job_id: $jobId
- applied_count: ${block.appliedCount}
- skipped_count: ${block.skippedCount}

Resume Integrity Check:
- status: $integrityStatus
- summary: $integritySummary

Integrity signals:
${_integritySignalsText(block)}

Task:
Call `tailor_resume` again for the same source resume and job. Use the integrity signals to produce a safer replacement proposed-edits block.

Hard constraints:
- Preserve original resume facts. Do not add unsupported companies, roles, dates, degrees, certifications, tools, skills, metrics, years of experience, or achievements.
- If a job requirement is not supported by the resume, learned_facts, or explicit user context, do not insert it as a skill or achievement.
- Do not create duplicate skills or repeated bracketed skill lists. If a skill already exists, leave it alone unless you are improving that exact item.
- Use `tailor_resume`; do not call `apply_resume_edits`, `draft_email`, or `send_email`.
- Stop after `tailor_resume` returns so the user can review the replacement diff.
''';
  }

  String _integritySignalsText(ProposedEditsBlock block) {
    final signals = block.integrity?.signals ?? const [];
    if (signals.isEmpty) return '- none';

    return signals
        .take(6)
        .map(
          (signal) =>
              '- ${signal.severity.name}: ${signal.label} - ${signal.detail}',
        )
        .join('\n');
  }

  /// Settles an [EmailDraftBlock] once the user has saved it to Gmail Drafts
  /// from the review sheet. UI-only — the draft itself was already created by
  /// the review sheet; this just flips the card to its "saved" state so it
  /// can't be re-saved into a duplicate.
  void markEmailDraftSaved(String blockId, String? draftId) {
    final block = _findEmailDraft(blockId);
    if (block == null) return;
    if (block.status == EmailDraftStatus.saved) return;

    block.status = EmailDraftStatus.saved;
    block.savedDraftId = draftId;

    state = state.copyWith(items: [...state.items]);
    if (block.jobId != null && block.jobId!.trim().isNotEmpty) {
      _markJobHandledEverywhere(block.jobId!);
    }
    _markPipelineDraftProcessed(block);
    _persistNow();
  }

  /// Settles an [EmailDraftBlock] once the user actually sent it from the
  /// review sheet (send mode). Flips the card to its terminal "sent" state and
  /// runs the same pipeline bookkeeping as a saved draft. The Gmail send itself
  /// already happened inside the review sheet (behind the confirmation token);
  /// this only mirrors the outcome onto the card.
  void markEmailDraftSent(String blockId, String? messageId) {
    final block = _findEmailDraft(blockId);
    if (block == null) return;
    if (block.status == EmailDraftStatus.sent) return;

    block.status = EmailDraftStatus.sent;
    block.savedDraftId = messageId;

    state = state.copyWith(items: [...state.items]);

    _markPipelineDraftProcessed(block);
  }

  void _markPipelineDraftProcessed(EmailDraftBlock block) {
    final jobId = (block.jobId ?? state.threadJob?.id)?.trim();
    if (jobId == null || jobId.isEmpty) return;

    final threadJobId = state.threadJob?.id;
    final isThreadJob = threadJobId != null && threadJobId == jobId;

    if (isThreadJob) {
      if (_threadPipelineMarkedComplete) return;
      _threadPipelineMarkedComplete = true;
    }

    unawaited(
      ref
          .read(jobsProvider.notifier)
          .markDraftedByJobId(jobId, resumeId: block.attachmentResumeId),
    );

    if (isThreadJob) {
      state = state.copyWith(clearThreadJob: true);
    }
  }

  EmailDraftBlock? _findEmailDraft(String blockId) {
    for (final item in state.items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is EmailDraftBlock && block.id == blockId) return block;
      }
    }
    return null;
  }

  /// Records the user's Accept/Reject choice for a single edit inside a
  /// [ProposedEditsBlock]. UI-only — nothing is applied to the resume until
  /// [applyProposedEdits] runs. No-ops once the card has settled.
  void setEditDecision(String blockId, int editIndex, EditDecision decision) {
    final block = _findProposedEdits(blockId);
    if (block == null) return;
    if (block.state != ProposedEditsState.reviewing) return;
    if (editIndex < 0 || editIndex >= block.decisions.length) return;
    if (block.decisions[editIndex] == decision) return;
    block.decisions[editIndex] = decision;
    state = state.copyWith(items: [...state.items]);
    _schedulePersist();
  }

  /// Renders the tailored PDF for the accepted edits and moves the card into a
  /// preview-ready state — **without** saving it to the resume library yet.
  /// The user previews the result and then either saves it
  /// ([savePreviewedResume]) or keeps editing by replying in the chat.
  Future<void> applyProposedEdits(String blockId) async {
    final block = _findProposedEdits(blockId);
    if (block == null) return;
    if (block.state != ProposedEditsState.reviewing) return;
    if (block.acceptedCount == 0) return;

    // Unit tests can override build() with a seeded transcript and skip the real
    // Firebase-backed service/orchestrator setup. In that case, preserve the old
    // state-only behavior so notifier/UI tests don't need Firebase initialization.
    if (!_serviceReady) {
      block.appliedCount = block.acceptedCount;
      block.skippedCount = 0;
      block.integrity = null;
      block.applyError = null;
      block.state = ProposedEditsState.applied;
      state = state.copyWith(items: [...state.items]);
      _persistNow();
      return;
    }

    final uid = _uid;
    if (uid == null) {
      block.applyError = 'Sign in to apply resume edits.';
      state = state.copyWith(items: [...state.items]);
      _persistNow();
      return;
    }

    block.state = ProposedEditsState.applying;
    block.applyError = null;
    block.integrity = null;
    state = state.copyWith(items: [...state.items]);
    _schedulePersist();

    final error = await _renderEditsPreview(block, uid);
    if (error == null) {
      block.state = ProposedEditsState.applied;
    } else {
      // Roll back to reviewing so the user can adjust and retry; the error
      // surfaces inline above the action buttons.
      block.state = ProposedEditsState.reviewing;
      block.applyError = error;
    }
    state = state.copyWith(items: [...state.items]);
    _persistNow();
    if (error == null) {
      _maybeStartIntegrityRepair(block);
    }
  }

  /// Renders the tailored PDF for [block]'s accepted edits and stores the
  /// result on the block ([ProposedEditsBlock.previewBytes] et al.). Returns
  /// `null` on success or a short, user-facing message on failure. The caller
  /// owns the surrounding state transitions and the re-emit. Shared by the
  /// user-driven [applyProposedEdits] and the auto-applied tailor path
  /// ([_autoRenderAppliedEdits]).
  Future<String?> _renderEditsPreview(
    ProposedEditsBlock block,
    String uid,
  ) async {
    try {
      var resumeId = block.resumeId;
      if (resumeId == null || resumeId.isEmpty) {
        resumeId = await _orchestrator.latestManualResumeId(uid);
      }
      if (resumeId == null || resumeId.isEmpty) {
        throw const TailorOrchestratorException(
          'No source resume found — upload one first.',
        );
      }

      final rendered = await _orchestrator.renderEdits(
        uid: uid,
        resumeId: resumeId,
        acceptedEdits: block.acceptedEdits,
      );

      block.previewBytes = rendered.bytes;
      block.previewResume = rendered.resume;
      block.appliedCount = rendered.appliedCount;
      block.skippedCount = rendered.skippedCount;
      block.integrity = rendered.integrity;
      block.resolvedResumeId = resumeId;
      await _storePreviewBytes(block, rendered.bytes);
      return null;
    } catch (e) {
      return _shortError(e);
    }
  }

  /// Renders the preview PDF for an auto-applied tailor card the instant it
  /// lands in the chat. `tailor_resume` surfaces its edits as an already-
  /// `applied`, read-only diff (see `_proposedEditsBlockFromData`), but the
  /// card carries no rendered PDF — without this the preview screen would have
  /// no bytes and show "Preview unavailable". Keeps the card in [applying]
  /// (the "Rendering…" spinner) while the PDF builds so the preview button
  /// only appears once there are bytes behind it; on failure it falls back to
  /// [reviewing] so the user can retry via "Apply N edits".
  Future<void> _autoRenderAppliedEdits(ProposedEditsBlock block) async {
    if (!_serviceReady) return;
    if (block.previewBytes != null) return;
    if (block.acceptedEdits.isEmpty) return;

    final uid = _uid;
    if (uid == null) {
      // Guests have no resume library to render against; leave the read-only
      // diff in place without a preview.
      return;
    }

    block.state = ProposedEditsState.applying;
    block.applyError = null;
    block.integrity = null;
    state = state.copyWith(items: [...state.items]);
    _schedulePersist();

    final error = await _renderEditsPreview(block, uid);
    if (error == null) {
      block.state = ProposedEditsState.applied;
    } else {
      block.state = ProposedEditsState.reviewing;
      block.applyError = error;
    }
    state = state.copyWith(items: [...state.items]);
    _persistNow();
    if (error == null) {
      _maybeStartIntegrityRepair(block);
    }
  }

  // -------------------------------------------------------------------------
  // From-scratch resume drafts (build_resume → ResumeDraftBlock)
  // -------------------------------------------------------------------------

  /// Public lookup for a [ResumeDraftBlock] by id — used by the draft preview
  /// screen to read the rendered bytes / saved state reactively.
  ResumeDraftBlock? resumeDraftBlock(String blockId) =>
      _findResumeDraft(blockId);

  ResumeDraftBlock? _findResumeDraft(String blockId) {
    for (final item in state.items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is ResumeDraftBlock && block.id == blockId) return block;
      }
    }
    return null;
  }

  /// Renders the preview PDF for a from-scratch resume the instant its draft
  /// card lands. `build_resume` carries the structured resume but no PDF — this
  /// renders one (a pure template render, no Firestore) so the preview screen
  /// has bytes to show. On failure it surfaces the error inline on the card.
  Future<void> _autoRenderResumeDraft(ResumeDraftBlock block) async {
    if (!_serviceReady) return;
    if (block.previewBytes != null) return;

    try {
      final bytes = await _orchestrator.renderResume(block.resume);
      block.previewBytes = bytes;
      await _storePreviewBytes(block, bytes);
      block.error = null;
    } catch (e) {
      block.error = _shortError(e);
    }
    block.state = ResumeDraftState.ready;
    state = state.copyWith(items: [...state.items]);
    _persistNow();
  }

  /// Persists a previewed from-scratch resume as a new `source: manual` base
  /// resume. No-op until the draft has rendered ([previewBytes] set) and only
  /// saves once. Seeds the byte cache so opening it from the list is instant.
  Future<void> saveBuiltResume(String blockId) async {
    final block = _findResumeDraft(blockId);
    if (block == null) return;
    if (block.previewBytes == null) return;
    if (block.isSaved) return;

    final uid = _uid;
    if (uid == null) {
      block.error = 'Sign in to save resumes.';
      state = state.copyWith(items: [...state.items]);
      _persistNow();
      return;
    }

    try {
      final saved = await _orchestrator.saveBuiltResume(
        uid: uid,
        bytes: block.previewBytes!,
        resume: block.resume,
        name: block.fileName,
      );
      block.savedResumeId = saved.id;
      block.error = null;
      ref
          .read(resumeProvider.notifier)
          .primeBytes(saved.id, block.previewBytes!);
      state = state.copyWith(items: [...state.items]);
      _persistNow();
    } catch (e) {
      block.error = _shortError(e);
      state = state.copyWith(items: [...state.items]);
      _persistNow();
    }
  }

  /// Persists the previewed tailored PDF to the resume library so it appears
  /// in the user's resumes / profile. No-op until the card has rendered a
  /// preview ([ProposedEditsState.applied]) and only saves once.
  Future<void> savePreviewedResume(String blockId) async {
    final block = _findProposedEdits(blockId);
    if (block == null) return;
    if (block.state != ProposedEditsState.applied) return;
    if (block.previewBytes == null || block.previewResume == null) return;
    if (block.isSaved) return;
    if (block.integrityAutoRepairing) {
      block.applyError =
          'Syncra is repairing this resume after the integrity check. Save will unlock when the safer revision is ready.';
      state = state.copyWith(items: [...state.items]);
      _persistNow();
      return;
    }
    if (block.integrity?.isBlocked == true) {
      block.applyError =
          'Resume Integrity Check blocked saving: ${block.integrity!.summary}';
      state = state.copyWith(items: [...state.items]);
      _persistNow();
      return;
    }

    final uid = _uid;
    if (uid == null) {
      block.applyError = 'Sign in to save resumes.';
      state = state.copyWith(items: [...state.items]);
      _persistNow();
      return;
    }

    try {
      final saved = await _orchestrator.saveRenderedResume(
        uid: uid,
        bytes: block.previewBytes!,
        resume: block.previewResume!,
        parentResumeId: block.resolvedResumeId,
        jobId: block.jobId,
      );
      block.savedResumeId = saved.id;
      block.applyError = null;
      // Seed the bytes cache so opening it from the resume list is instant.
      ref
          .read(resumeProvider.notifier)
          .primeBytes(saved.id, block.previewBytes!);
      state = state.copyWith(items: [...state.items]);
      _persistNow();

      _continueAfterSavedResume(block);
    } catch (e) {
      block.applyError = _shortError(e);
      state = state.copyWith(items: [...state.items]);
      _persistNow();
    }
  }

  String _shortError(Object e) {
    final raw = e
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('TailorOrchestratorException: ', '')
        .trim();
    if (raw.isEmpty) return 'Something went wrong.';
    return raw.length > 120 ? '${raw.substring(0, 120)}…' : raw;
  }

  void dismissJobInBlock(String blockId, String jobId) {
    final block = _findJobsBlock(blockId);
    if (block == null) return;

    block.dismissJob(jobId);
    state = state.copyWith(items: [...state.items]);
    _persistNow();
  }

  void hideJobInBlock(String blockId, String jobId) {
    final block = _findJobsBlock(blockId);
    if (block == null) return;

    block.hideJob(jobId);
    state = state.copyWith(items: [...state.items]);
    _persistNow();
  }

  void unhideAllJobsInBlock(String blockId) {
    final block = _findJobsBlock(blockId);
    if (block == null) return;

    final hiddenIds = {...block.hiddenJobIds};
    block.unhideAllJobs();

    final jobsNotifier = ref.read(jobsProvider.notifier);
    for (final id in hiddenIds) {
      jobsNotifier.unhide(id);
    }

    state = state.copyWith(items: [...state.items]);
    _persistNow();
  }

  void markJobHandledInBlock(String blockId, String jobId) {
    final block = _findJobsBlock(blockId);
    if (block == null) return;

    block.markJobHandled(jobId);
    state = state.copyWith(items: [...state.items]);
    _persistNow();
  }

  void _markJobHandledEverywhere(String jobId) {
    final clean = jobId.trim();
    if (clean.isEmpty) return;

    var changed = false;

    for (final item in state.items) {
      if (item is! AgentTurn) continue;

      for (final block in item.blocks) {
        if (block is JobsBlock &&
            block.jobs.any((job) => job.id == clean) &&
            !block.handledJobIds.contains(clean)) {
          block.markJobHandled(clean);
          changed = true;
        }
      }
    }

    final activeTurn = _activeTurn;
    if (activeTurn != null) {
      for (final block in activeTurn.blocks) {
        if (block is JobsBlock &&
            block.jobs.any((job) => job.id == clean) &&
            !block.handledJobIds.contains(clean)) {
          block.markJobHandled(clean);
          changed = true;
        }
      }
    }

    if (!changed) return;

    state = state.copyWith(items: [...state.items]);
    _persistNow();
  }

  String? _jobIdFromToolDetail(String? detail) {
    if (detail == null || detail.trim().isEmpty) return null;

    final quoted = RegExp(r'"job_id"\s*:\s*"([^"]+)"').firstMatch(detail);
    if (quoted != null) return quoted.group(1)?.trim();

    final snake = RegExp(
      r'job_id\s*[:=]\s*([A-Za-z0-9._-]+)',
    ).firstMatch(detail);
    return snake?.group(1)?.trim();
  }

  JobsBlock? _findJobsBlock(String blockId) {
    for (final item in state.items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is JobsBlock && block.id == blockId) return block;
      }
    }
    return null;
  }

  /// Dismisses a [ProposedEditsBlock] without applying anything.
  void dismissProposedEdits(String blockId) {
    final block = _findProposedEdits(blockId);
    if (block == null) return;
    if (block.state != ProposedEditsState.reviewing) return;
    block.state = ProposedEditsState.dismissed;
    state = state.copyWith(items: [...state.items]);
    _persistNow();
  }

  InputRequestBlock? _findInputRequest(String blockId) {
    for (final item in state.items) {
      if (item is! AgentTurn) continue;
      for (final block in item.blocks) {
        if (block is InputRequestBlock && block.id == blockId) return block;
      }
    }
    return null;
  }

  /// Called when the user submits an answer to an inline `ask_user` prompt.
  void submitInputAnswer(String blockId, String answer) {
    final block = _findInputRequest(blockId);
    if (block == null) return;
    if (block.state == InputRequestState.answered) return;

    final trimmed = answer.trim();
    if (trimmed.isEmpty) return;

    block.state = InputRequestState.answered;
    block.answer = trimmed;
    ref.read(notificationsProvider.notifier).markReadByTargetBlock(blockId);
    state = state.copyWith(items: [...state.items]);
    _persistNow();

    final continuation = block.continuationPrompt?.trim();
    if (continuation != null && continuation.isNotEmpty) {
      _continueAfterInputAnswer(block, trimmed);
      return;
    }

    final handled = _service.provideUserAnswer(blockId, trimmed);
    if (!handled) {
      _continueAfterRestoredInputAnswer(block, trimmed);
    }
  }
}

final agentChatProvider = NotifierProvider<AgentChatNotifier, AgentChatState>(
  AgentChatNotifier.new,
);

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/services/anthropic_client.dart';
import '../../../data/models/job.dart';
import '../models/agent_block.dart';
import '../models/chat_message.dart';
import '../tools/tool_registry.dart';
import 'agent_service.dart';
import '../../resumes/models/proposed_edit.dart';
import '../../resumes/models/resume_json.dart';

/// Real-Anthropic implementation of [AgentService] with **tool use**.
///
/// The agent loop:
///   1. POST messages + tool definitions to Anthropic.
///   2. If response is plain text → emit TextBlock, done.
///   3. If response contains tool_use → for each tool, emit a UI block,
///      execute the handler (or pause for `ask_user`), then send the
///      tool_result back to Anthropic and loop.
///
/// `ask_user` is special: it pauses the loop on a [Completer] that the
/// chat controller resolves via [provideUserAnswer] when the user submits.
class AnthropicChatService implements AgentService {
  AnthropicChatService({
    required this.registry,
    AnthropicClient? client,
    this.model = 'claude-haiku-4-5-20251001',
    String? systemPromptOverride,
  })  : _client = client ?? AnthropicClient(),
        _systemPrompt = systemPromptOverride ?? systemPrompt;

  /// The system prompt actually sent on every request. Defaults to the main
  /// chatbot's [systemPrompt]; callers may override it via
  /// [systemPromptOverride] for a one-off session with different framing.
  final String _systemPrompt;

  static const _maxLoopIterations = 8;

  /// Upper bound on retained conversation messages for a threaded session.
  /// Prior turns are kept so the agent remembers what it just did; this caps
  /// how far that memory reaches before the oldest exchanges are dropped, so
  /// a long session can't grow the request payload — and its token cost —
  /// without bound. Trimming always leaves the history starting on a real
  /// user prompt, never an orphaned tool_result.
  static const _maxConversationMessages = 30;

  /// Extended-thinking budget, in tokens. Must be ≥1024 and strictly less
  /// than [_maxTokens]; the model's visible output (text + tool calls) gets
  /// whatever is left over.
  static const _thinkingBudget = 2048;

  /// Total output ceiling. Sits well above [_thinkingBudget] so the agent has
  /// ample room for tool calls and a reply after it finishes reasoning — a
  /// tight ceiling here truncates the turn (handled as a clean failure below,
  /// but better avoided). Haiku 4.5 allows far more; only generated tokens
  /// are billed.
  static const _maxTokens = 8192;

static const systemPrompt = '''
You are Syncra, an AI career copilot inside a Flutter app. Your job is to help
the user find, tailor, and apply to jobs. Be calm, capable, and concise.

Agent workflow:
- Treat the user's message as a goal, not as a single-step question.
- Make a short internal plan and execute the safe steps with tools.
- Drive the workflow forward yourself. After each milestone, proactively offer the next concrete step — never stop with just a result and no offered next step.
- Offer next steps by calling `ask_user` with 2-3 tappable suggestion chips. Propose a specific action; never ask a vague "what would you like to do next?".
- Continue the workflow until you either finish the useful work or reach a user gate.
- Use tools to do the work. Do not just describe what you would do.

Standard job-search sequence — follow it, one gate at a time:
1. `search_jobs` renders the roles as interactive cards. Add at most one short sentence introducing them, then DO NOT end the turn. Immediately call `ask_user` to offer tailoring, e.g. "Want me to tailor your resume for one of these roles?" with chips like ["Tailor for the best match", "Let me pick a role", "Not now"].
2. If the user wants tailoring but it is unclear which role, call `ask_user` so they choose the specific job. You need a job_id (and a resume) before tailoring.
3. `tailor_resume` only PROPOSES edits. After it returns, stop and let the user review the diff. Do not call `apply_resume_edits`, `draft_email`, or `send_email` yet.
4. After the app tells you the user saved the tailored resume, offer outreach: call `ask_user` — "Want me to draft an outreach email for this role?" with chips like ["Draft the email", "Not yet"]. Only call `draft_email` after the user says yes.
5. `draft_email` produces a draft only. The user reviews and sends it from the review screen. Never call `send_email` yourself.

User gates:
- Pause only when you need information only the user can provide, or when an action requires approval.
- If you need information such as target salary, resume choice, recipient email, or preference, call `ask_user`.
- When required information is missing, call `ask_user` with 2-3 short suggestion chips unless the question is genuinely open-ended.
- Never invent personal details, resume details, recipient details, or user preferences.

Job results:
- The job cards are interactive (the user can swipe and tap). Do not re-list the jobs in prose — one short sentence is enough, then follow the sequence above and offer to tailor.

Resume tailoring:
- When tailoring a resume, propose changes — never overwrite directly.
- The `tailor_resume` tool only proposes edits. It does not apply edits, render PDFs, or save files.
- After `tailor_resume` returns proposed edits, stop and wait. The user reviews the edits in the diff viewer.
- Do not call `apply_resume_edits`, `draft_email`, or `send_email` until the user has accepted edits.
- If the app later tells you the user approved and saved a tailored resume, continue the original workflow from there without asking the user to repeat the task.

Building a resume from scratch:
- If the user has no resume to upload, offer to build one with `build_resume`.
- Collect the details conversationally with `ask_user`: contact info first, then each work experience (company, role, dates, 2-4 achievement bullets), then education and skills. Ask in small batches — not one field at a time — and let the user paste what they already have.
- When you have enough, call `build_resume` ONCE with the full structure. It renders a preview only; it does NOT save. The user previews the PDF and taps Save.
- NEVER invent employers, titles, dates, or metrics. Use only what the user gave you and omit fields you don't have.
- Once saved, the new resume becomes a base resume the user can tailor to jobs — continue the workflow from there.
Match presentation:
- The matching system is purely qualitative. NEVER show the user a numeric score, percentage, rating, or any 0-100 value for a match.
- When you present matches (including in a table), show match strength using ONLY the `match` label from match_jobs — e.g. "Strong match", "Partial match", "Possible match", or "Needs review".
- Use a single "Match" column with that label. Do not add a score/number column, and do not invent your own numbers.
- If match_jobs returns "Needs review" for jobs, present them normally as needing a quick review — do not describe it as an error or failure.

Email and external actions:
- Drafting an email is safe; sending an email is not.
- Never call `send_email` unless the app provides an explicit user-confirmation token or says the user tapped Send.
- If outreach is the next step and recipient information is missing, call `lookup_hiring_manager` or `ask_user`.

Progress and style:
- Surface progress as you go. The UI shows each tool call live.
- Prefer calling tools over guessing.
- When you respond with text, keep it to 1-3 short sentences and end with a clear next step or question.
''';

  final ToolRegistry registry;
  final AnthropicClient _client;
  final String model;

  /// Pending `ask_user` calls, keyed by the InputRequestBlock id.
  final Map<String, Completer<String>> _pendingAsks = {};

  /// Running Anthropic message history for threaded turns. Every user prompt,
  /// assistant turn, and tool_result batch is appended here so a later
  /// [runPrompt] call sees what the agent did earlier — the jobs it searched,
  /// the `ask_user` answers, the resume it tailored. Cleared by
  /// [resetConversation]; non-threaded turns (the brief) never touch it.
  final List<Map<String, dynamic>> _conversation = [];

  int _seq = 0;

  bool get hasApiKey => _client.hasApiKey;

  @override
  Stream<AgentEvent> runPrompt({
    required String prompt,
    List<ChatAttachment> attachments = const [],
    bool threaded = true,
  }) async* {
    _seq += 1;
    final turnPrefix = 'turn$_seq-';
    int blockSeq = 0;
    String nextBlockId(String kind) => '$turnPrefix$kind-${++blockSeq}';

    final attachmentNote = attachments.isEmpty
        ? ''
        : '''

    User attached resumes:
    ${attachments.map((a) => '- resume_id: ${a.id}\n  name: ${a.name}').join('\n')}
    When a resume tool accepts resume_id, use the matching resume_id above.
    ''';
    final userText = '$prompt$attachmentNote';

    // The list we POST and then mutate during the loop. A threaded turn
    // continues the running [_conversation] so the agent sees its earlier
    // turns; a non-threaded turn (the morning brief) runs as an isolated
    // one-shot that neither reads nor writes shared history.
    final List<Map<String, dynamic>> messages;
    if (threaded) {
      _appendUserMessage(userText);
      _trimConversation();
      messages = _conversation;
    } else {
      messages = [
        {'role': 'user', 'content': userText},
      ];
    }

    try {
      var consecutiveFailedToolTurns = 0;
      // The job rail rendered this turn, if any. `search_jobs` mints it;
      // `match_jobs` (and any repeat search) re-scores it in place instead of
      // stacking a second identical rail below the first.
      String? activeJobsRailId;
      for (var iteration = 0; iteration < _maxLoopIterations; iteration++) {
        final response = await _callAnthropic(messages);
        final content = response['content'] as List? ?? const [];
        final stopReason = response['stop_reason'] as String? ?? '';

        // A truncated turn (hit the output ceiling) can carry an incomplete
        // tool_use block; appending it to history would leave a malformed
        // turn the next request can't continue. Bail cleanly instead — in a
        // threaded session the conversation stays ending on the user prompt,
        // so the user's next message simply folds in.
        if (stopReason == 'max_tokens') {
          yield TurnFailed(
            'That response got cut off before I finished. Try a narrower '
            'request, or ask for one step at a time.',
          );
          return;
        }

        // Record the assistant turn verbatim so the next request has full context.
        messages.add({'role': 'assistant', 'content': content});

        final toolResults = <Map<String, dynamic>>[];
        var toolFailuresThisTurn = 0;
        var toolSuccessesThisTurn = 0;
        bool shouldPauseAfterTailorResume = false;
        String? tailorPauseMessage;
        bool shouldPauseAfterBuildResume = false;
        String? buildResumePauseMessage;
        bool shouldPauseAfterDraftEmail = false;
        String? draftPauseMessage;
        bool shouldPauseAfterResumeEmail = false;
        String? resumeEmailPauseMessage;
        for (final raw in content) {
          if (raw is! Map<String, dynamic>) continue;
          final type = raw['type'] as String?;

          if (type == 'thinking') {
            // Extended-thinking block. The full block (with its signature)
            // is already preserved in `messages` via the verbatim assistant
            // content above — required when thinking is paired with tools.
            final thought = (raw['thinking'] as String?)?.trim() ?? '';
            if (thought.isEmpty) continue;
            yield BlockAdded(
              ThinkingBlock(id: nextBlockId('think'), content: thought),
            );
          } else if (type == 'text') {
            final text = (raw['text'] as String?)?.trim() ?? '';
            if (text.isEmpty) continue;
            yield BlockAdded(TextBlock(id: nextBlockId('text'), text: text));
          } else if (type == 'tool_use') {
            final toolUseId = raw['id'] as String;
            final name = raw['name'] as String;
            final input = (raw['input'] as Map?)?.cast<String, dynamic>() ?? {};

            if (name == 'ask_user') {
              final block = InputRequestBlock(
                id: nextBlockId('ask'),
                question: (input['question'] as String?) ?? 'Anything to add?',
                suggestions: List<String>.from(
                  (input['suggestions'] as List?) ?? const [],
                ),
              );
              yield BlockAdded(block);

              final completer = Completer<String>();
              _pendingAsks[block.id] = completer;
              final answer = await completer.future;

              toolResults.add({
                'type': 'tool_result',
                'tool_use_id': toolUseId,
                'content': answer,
              });
              toolSuccessesThisTurn += 1;
            } else {
              final tool = registry.toolFor(name);
              final handler = registry.handlerFor(name);
              final toolBlock = ToolCallBlock(
                id: nextBlockId('tool'),
                name: name,
                label: tool?.uiLabel ?? '$name…',
                icon: tool?.uiIcon ?? Icons.bolt_rounded,
                detail: _formatToolDetail(input),
              );
              yield BlockAdded(toolBlock);

              if (handler == null) {
                yield ToolCallCompleted(
                  blockId: toolBlock.id,
                  summary: 'Tool unavailable',
                  status: ToolCallStatus.failed,
                  detail: _formatToolDetail(
                    input,
                    output: 'Tool "$name" is not registered.',
                  ),
                );
                toolResults.add({
                  'type': 'tool_result',
                  'tool_use_id': toolUseId,
                  'content': 'Error: tool "$name" is not registered.',
                  'is_error': true,
                });
                toolFailuresThisTurn += 1;
                continue;
              }

              try {
                final result = await handler(input);
                yield ToolCallCompleted(
                  blockId: toolBlock.id,
                  summary: result.summary,
                  status: result.isError
                      ? ToolCallStatus.failed
                      : ToolCallStatus.done,
                  detail: _formatToolDetail(input, output: result.data),
                );

                if (result.isError) {
                  toolFailuresThisTurn += 1;
                } else {
                  toolSuccessesThisTurn += 1;
                } 
                if (!result.isError &&
                    (name == 'search_jobs' || name == 'match_jobs')) {
                  final jobs = _jobsFromData(result.data);
                  if (jobs.isNotEmpty) {
                    if (activeJobsRailId != null) {
                      // A rail is already on screen — `match_jobs` re-scoring
                      // the roles `search_jobs` surfaced, or a repeat search.
                      // Update it in place so the same roles don't render twice.
                      yield JobsBlockUpdated(
                        blockId: activeJobsRailId,
                        jobs: jobs,
                      );
                    } else {
                      final id = nextBlockId('jobs');
                      activeJobsRailId = id;
                      yield BlockAdded(JobsBlock(id: id, jobs: jobs));
                    }
                  }
                }

                if (!result.isError &&
                    name == 'tailor_resume' &&
                    _hasProposedEditsPayload(result.data)) {
                  final editsBlock = _proposedEditsBlockFromData(
                    id: nextBlockId('edits'),
                    data: result.data,
                  );

                  if (editsBlock != null) {
                    yield BlockAdded(editsBlock);
                  }

                  shouldPauseAfterTailorResume = true;
                  tailorPauseMessage = _tailorPauseMessage(result.data);
                }

                if (!result.isError && name == 'build_resume') {
                  final draftBlock = _resumeDraftBlockFromData(
                    id: nextBlockId('resume'),
                    data: result.data,
                  );
                  if (draftBlock != null) {
                    yield BlockAdded(draftBlock);
                    shouldPauseAfterBuildResume = true;
                    buildResumePauseMessage =
                        'I drafted your resume below. Preview it, then save it '
                        "to your resumes — nothing is saved until you tap Save.";
                  }
                }

                if (!result.isError && name == 'draft_email') {
                  final draftBlock = _emailDraftBlockFromData(
                    id: nextBlockId('email'),
                    data: result.data,
                  );
                  if (draftBlock != null) {
                    yield BlockAdded(draftBlock);
                    shouldPauseAfterDraftEmail = true;
                    draftPauseMessage =
                        "I drafted the email below. Review it and save it to "
                        "your Gmail Drafts — I won't send anything myself.";
                  }
                }

                // After the tailored PDF is rendered, automatically draft a
                // self-delivery email with the resume attached so the user can
                // save a copy to their own inbox in one tap.
                if (!result.isError && name == 'apply_resume_edits') {
                  final resumeEmailBlock = _resumeEmailBlockFromData(
                    id: nextBlockId('email'),
                    data: result.data,
                  );
                  if (resumeEmailBlock != null) {
                    yield BlockAdded(resumeEmailBlock);
                    shouldPauseAfterResumeEmail = true;
                    resumeEmailPauseMessage =
                        'Your tailored resume is ready. I drafted an email to '
                        'you with it attached — review it and save it to your '
                        "Gmail Drafts. I won't send anything myself.";
                  }
                }

                toolResults.add({
                  'type': 'tool_result',
                  'tool_use_id': toolUseId,
                  'content': _serialize(result.data),
                  if (result.isError) 'is_error': true,
                });
              } catch (e) {
                yield ToolCallCompleted(
                  blockId: toolBlock.id,
                  summary: 'Failed: ${_shortError(e)}',
                  status: ToolCallStatus.failed,
                  detail: _formatToolDetail(input, output: 'Error: $e'),
                );
                toolResults.add({
                  'type': 'tool_result',
                  'tool_use_id': toolUseId,
                  'content': 'Error: $e',
                  'is_error': true,
                });
                toolFailuresThisTurn += 1;
              }
            }
          }
        }

        // No tools used → conversation is done.
        if (stopReason != 'tool_use' || toolResults.isEmpty) {
          yield const TurnCompleted();
          return;
        }

        if (toolFailuresThisTurn > 0 && toolSuccessesThisTurn == 0) {
          consecutiveFailedToolTurns += 1;
        } else {
          consecutiveFailedToolTurns = 0;
        }

        if (consecutiveFailedToolTurns >= 2) {
          // Record this turn's tool_results before bailing so the threaded
          // conversation stays well-formed — no tool_use left unanswered.
          messages.add({'role': 'user', 'content': toolResults});
          yield BlockAdded(TextBlock(
            id: nextBlockId('text'),
            text:
                'I hit repeated tool failures while trying to complete that. Try narrowing the request, or give me the job/resume details directly.',
          ));
          yield const TurnCompleted();
          return;
        }

        // After `tailor_resume`, the proposed edits are auto-applied and shown
        // as a read-only diff. Stop the turn here so the user can see what
        // changed; don't feed the result back to Claude, which would let it
        // immediately chain into draft_email or apply_resume_edits.
        if (shouldPauseAfterTailorResume) {
          // Record the tool_results so the paused turn leaves a well-formed
          // conversation — every tool_use needs a matching tool_result before
          // the next threaded turn POSTs. We deliberately do not loop on them
          // here: the turn ends so the user sees the applied edits before the
          // agent moves on to apply_resume_edits or draft_email.
          messages.add({'role': 'user', 'content': toolResults});
          yield BlockAdded(TextBlock(
            id: nextBlockId('text'),
            text: tailorPauseMessage ??
                'I found proposed resume edits. Review them before I continue.',
          ));
          yield const TurnCompleted();
          return;
        }

        // `build_resume` renders a preview only — saving is a user tap on the
        // draft card. Stop the turn so the user previews and saves before the
        // agent chains into anything that depends on the new resume.
        if (shouldPauseAfterBuildResume) {
          messages.add({'role': 'user', 'content': toolResults});
          yield BlockAdded(TextBlock(
            id: nextBlockId('text'),
            text: buildResumePauseMessage ??
                'I drafted your resume. Preview it before saving.',
          ));
          yield const TurnCompleted();
          return;
        }

        // `draft_email` is user-gated the same way: the email draft card is the
        // only path that can save to Gmail (and the agent can't send at all).
        // Stop here so the user reviews the draft before anything reaches their
        // Drafts folder, and don't loop the result back into `send_email`.
        if (shouldPauseAfterDraftEmail) {
          messages.add({'role': 'user', 'content': toolResults});
          yield BlockAdded(TextBlock(
            id: nextBlockId('text'),
            text: draftPauseMessage ??
                'I drafted an email. Review it before I continue.',
          ));
          yield const TurnCompleted();
          return;
        }

        // The auto-drafted "here's your tailored resume" email is gated the
        // same way: stop so the user reviews and saves it before anything more.
        if (shouldPauseAfterResumeEmail) {
          messages.add({'role': 'user', 'content': toolResults});
          yield BlockAdded(TextBlock(
            id: nextBlockId('text'),
            text: resumeEmailPauseMessage ??
                'I drafted an email with your tailored resume attached. '
                    'Review it before I continue.',
          ));
          yield const TurnCompleted();
          return;
        }

        messages.add({'role': 'user', 'content': toolResults});
      }

      // Safety net: too many iterations.
      yield TurnFailed(
        'I reached my safety limit before finishing that request. Try '
        'narrowing the task, for example: “find 5 UX jobs” or “tailor my '
        'resume for this specific job.”',
      );
    } catch (e) {
      yield TurnFailed("Couldn't reach Claude — ${_shortError(e)}");
    }
  }

  @override
  void provideUserAnswer(String blockId, String answer) {
    final completer = _pendingAsks.remove(blockId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(answer);
    }
  }

  @override
  void resetConversation() => _conversation.clear();

  /// Closes the underlying Anthropic client (and its HTTP connection pool).
  /// Call when the owning notifier is disposed. Not part of the
  /// [AgentService] interface — hence no `@override`.
  void dispose() => _client.dispose();

  /// Appends a user turn to [_conversation]. When the trailing message is
  /// already a `user` turn — the tool_result batch left by a tailor-resume
  /// pause or a bailed-out turn — the new prompt is folded into it instead of
  /// starting a second consecutive user turn, which Anthropic rejects.
  void _appendUserMessage(String text) {
    final last = _conversation.isEmpty ? null : _conversation.last;
    if (last != null && last['role'] == 'user') {
      final existing = last['content'];
      last['content'] = <dynamic>[
        if (existing is List)
          ...existing
        else
          {'type': 'text', 'text': '$existing'},
        {'type': 'text', 'text': text},
      ];
    } else {
      _conversation.add({'role': 'user', 'content': text});
    }
  }

  /// Caps [_conversation] at [_maxConversationMessages] so a long session
  /// can't grow the request payload without bound. Drops the oldest messages,
  /// but only down to a real user prompt — never leaving the history starting
  /// on an orphaned tool_result whose tool_use parent would be gone.
  void _trimConversation() {
    if (_conversation.length <= _maxConversationMessages) return;
    final overflow = _conversation.length - _maxConversationMessages;
    for (var i = overflow; i < _conversation.length; i++) {
      final msg = _conversation[i];
      if (msg['role'] == 'user' && !_carriesToolResult(msg['content'])) {
        _conversation.removeRange(0, i);
        return;
      }
    }
  }

  bool _carriesToolResult(Object? content) =>
      content is List &&
      content.any((b) => b is Map && b['type'] == 'tool_result');

  /// Builds the `thinking` block for [model]. The request shape changed with
  /// the 4.6 generation: Sonnet 4.6 and Opus 4.6/4.7/4.8 take adaptive
  /// thinking (the model decides its own depth — no budget), while Haiku 4.5
  /// and older take the legacy fixed `budget_tokens` form. This matters because
  /// `budget_tokens` is *rejected* on Opus 4.7+ (HTTP 400), so hardcoding it
  /// would break the agent the moment [model] is swapped to a newer one.
  static Map<String, dynamic> _thinkingConfig(String model) {
    if (_usesAdaptiveThinking(model)) {
      return {'type': 'adaptive'};
    }
    return {'type': 'enabled', 'budget_tokens': _thinkingBudget};
  }

  /// True when [model] is the 4.6 generation or newer (major > 4, or major 4
  /// with minor ≥ 6) — those use adaptive thinking. Parses the `-<major>-<minor>`
  /// in the model id (e.g. `claude-opus-4-8` → 4.8, `claude-haiku-4-5-…` → 4.5).
  /// An unrecognized id falls back to the legacy form, which is safe on older
  /// models and the only thing Haiku 4.5 accepts.
  static bool _usesAdaptiveThinking(String model) {
    final match = RegExp(r'-(\d+)-(\d+)').firstMatch(model);
    if (match == null) return false;
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    return major > 4 || (major == 4 && minor >= 6);
  }

  Future<Map<String, dynamic>> _callAnthropic(
    List<Map<String, dynamic>> messages,
  ) async {
    final tools = [
      ToolRegistry.askUserTool.toApiJson(),
      ...registry.definitions.map((t) => t.toApiJson()),
    ];

    // Transport (auth, retry/backoff, error handling) lives in the shared
    // AnthropicClient; this builds the payload and logs cache effectiveness.
    final response = await _client.createMessage({
      'model': model,
      'max_tokens': _maxTokens,
      'thinking': _thinkingConfig(model),
      // Prompt caching. Request render order is tools → system → messages,
      // so a cache_control breakpoint on the system block caches the whole
      // static prefix — tool schemas AND system prompt — in one entry.
      // That prefix is byte-identical on every loop iteration and every
      // threaded turn; the first request writes it (~1.25x input cost),
      // every request inside the 5-minute TTL reads it (~0.1x).
      'system': [
        {
          'type': 'text',
          'text': _systemPrompt,
          'cache_control': {'type': 'ephemeral'},
        },
      ],
      'tools': tools,
      // Second breakpoint: the top-level cache_control auto-places on the
      // last message block, so the growing conversation tail is cached too
      // — each loop iteration re-reads the prior turns instead of re-paying
      // for them. Two breakpoints total, well under the 4-per-request cap.
      'cache_control': {'type': 'ephemeral'},
      'messages': messages,
    });

    _logCacheUsage(response['usage']);
    return response;
  }

  /// Builds the swipeable job-rail card from a `search_jobs` result. The tool
  /// returns lean job descriptors; this parses them into [Job]s with safe
  /// fallbacks for the fields a raw search result doesn't carry (skills, the
  /// agent's reasoning, etc.). Returns null when there are no usable jobs, so
  /// the turn falls back to the plain tool summary rather than an empty rail.
  /// Parses a `search_jobs` / `match_jobs` result into the rail's [Job] list.
  /// Returns an empty list when there are no usable jobs, so the caller can
  /// fall back to the plain tool summary rather than an empty rail.
  List<Job> _jobsFromData(Object? data) {
    if (data is! Map) return const [];
    final rawJobs = data['jobs'];
    if (rawJobs is! List) return const [];

    final jobs = <Job>[];
    for (final raw in rawJobs) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final jobId = m['id']?.toString() ?? '';
      final title = (m['title'] as String?)?.trim() ?? '';
      if (jobId.isEmpty || title.isEmpty) continue;
      jobs.add(Job(
        id: jobId,
        title: title,
        company: (m['company'] as String?)?.trim() ?? '',
        location: (m['location'] as String?)?.trim() ?? '',
        salary: (m['salary'] as String?)?.trim() ?? '',
        category: _jobCategoryFromName(m['category'] as String?),
        matchScore: (m['match'] as num?)?.toInt() ?? 0,
        agentAction: '',
        agentJustification: '',
        skills: const [],
        missingSkills: const [],
        why: (m['description_excerpt'] as String?)?.trim() ?? '',
      ));
    }

    return jobs;
  }

  /// Lenient enum mapping for the `category` string a job descriptor carries.
  /// Accepts both the enum name (`inputNeeded`) and the snake_case form
  /// (`input_needed`); anything unrecognised falls back to a strong match.
  JobCategory _jobCategoryFromName(String? name) => switch (name) {
        'ready' => JobCategory.ready,
        'inputNeeded' || 'input_needed' => JobCategory.inputNeeded,
        'exploration' => JobCategory.exploration,
        _ => JobCategory.ready,
      };

  ProposedEditsBlock? _proposedEditsBlockFromData({
    required String id,
    required Object? data,
  }) {
    if (data is! Map) return null;

    final rawEdits = data['proposed_edits'];
    if (rawEdits is! List) return null;

    final edits = rawEdits
        .whereType<Map>()
        .map((raw) => ProposedEdit.fromJson(Map<String, dynamic>.from(raw)))
        .where((edit) => edit.isValid)
        .toList(growable: false);

    if (edits.isEmpty) return null;

    // Tailoring auto-applies its edits: the card renders as a settled,
    // read-only diff of what changed rather than an accept/reject prompt.
    return ProposedEditsBlock.applied(
      id: id,
      edits: edits,
      jobId: data['job_id']?.toString(),
      resumeId: data['resume_id']?.toString(),
    );
  }

  bool _hasProposedEditsPayload(Object? data) {
    if (data is! Map) return false;
    final proposedEdits = data['proposed_edits'];
    return proposedEdits is List;
  }

  /// Builds the from-scratch resume draft card from a `build_resume` tool
  /// result. Returns null when the payload has no usable resume (missing name)
  /// so the turn falls back to the plain tool summary.
  ResumeDraftBlock? _resumeDraftBlockFromData({
    required String id,
    required Object? data,
  }) {
    if (data is! Map) return null;
    final raw = data['resume_json'];
    if (raw is! Map) return null;

    final resume = ResumeJson.fromJson(raw.cast<String, dynamic>());
    if (resume.header.name.trim().isEmpty) return null;

    return ResumeDraftBlock(
      id: id,
      resume: resume,
      fileName: _resumeFileName(data['name'] as String?),
    );
  }

  /// Filesystem-safe file name for a built resume, derived from the candidate
  /// name (e.g. "Jane Doe" → `Jane_Doe_Resume.pdf`).
  String _resumeFileName(String? name) {
    final safe = (name ?? '')
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return safe.isEmpty ? 'Resume.pdf' : '${safe}_Resume.pdf';
  }

  /// Builds the inline review card from a `draft_email` tool result. Returns
  /// null when the draft is unusable (missing recipient/subject/body) so the
  /// turn falls back to the plain tool summary rather than an empty card.
  EmailDraftBlock? _emailDraftBlockFromData({
    required String id,
    required Object? data,
  }) {
    if (data is! Map) return null;
    final recipient = (data['recipient'] as String?)?.trim() ?? '';
    final subject = (data['subject'] as String?)?.trim() ?? '';
    final body = (data['body'] as String?)?.trim() ?? '';
    if (recipient.isEmpty || subject.isEmpty || body.isEmpty) return null;

    // draft_email tailors the resume to the job and flags the PDF to attach;
    // the view downloads the bytes by id. Absent (older results) → no file.
    final attachmentId = (data['attachment_resume_id'] as String?)?.trim();
    final attachmentName = (data['attachment_filename'] as String?)?.trim();

    return EmailDraftBlock(
      id: id,
      recipient: recipient,
      subject: subject,
      body: body,
      attachmentResumeId:
          (attachmentId == null || attachmentId.isEmpty) ? null : attachmentId,
      attachmentFilename: (attachmentName == null || attachmentName.isEmpty)
          ? null
          : attachmentName,
    );
  }

  /// Builds the self-delivery email card from an `apply_resume_edits` result.
  /// Addresses it to the signed-in user's own Gmail and flags the tailored PDF
  /// for attachment (the view downloads the bytes by id). Returns null when
  /// there is no signed-in email or no tailored resume id — in that case the
  /// turn just loops the result back to the agent as before.
  EmailDraftBlock? _resumeEmailBlockFromData({
    required String id,
    required Object? data,
  }) {
    if (data is! Map) return null;
    final resumeId = (data['tailored_resume_id'] as String?)?.trim() ?? '';
    if (resumeId.isEmpty) return null;

    final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
    if (email.isEmpty) return null;

    final rawName = (data['name'] as String?)?.trim();
    final filename = (rawName == null || rawName.isEmpty)
        ? 'tailored_resume.pdf'
        : (rawName.toLowerCase().endsWith('.pdf') ? rawName : '$rawName.pdf');

    return EmailDraftBlock(
      id: id,
      recipient: email,
      subject: 'Your tailored resume',
      body: 'Hi,\n\n'
          'Here is your resume tailored for this role, attached as a PDF. '
          'Save this draft to keep a copy in your inbox, or forward it when '
          'you apply.\n\n'
          'Best,\nSyncra',
      attachmentResumeId: resumeId,
      attachmentFilename: filename,
    );
  }

  String _tailorPauseMessage(Object? data) {
    var count = 0;
    if (data is Map && data['proposed_edits'] is List) {
      count = (data['proposed_edits'] as List).length;
    }

    if (count <= 0) {
      return 'I tried to tailor your resume, but no edits were generated. Check the result before continuing.';
    }

    final plural = count == 1 ? 'edit' : 'edits';
    return "I tailored your resume — $count $plural applied. Here's a diff "
        'of what changed.';
  }

  /// Formats a tool call's input args — and, once available, its output — for
  /// the drill-down panel. Pretty-prints JSON and clamps length so the inline
  /// panel stays compact.
  String _formatToolDetail(Map<String, dynamic> input, {Object? output}) {
    final buf = StringBuffer()
      ..writeln('▸ Input')
      ..write(_prettyJson(input));
    if (output != null) {
      buf
        ..writeln()
        ..writeln()
        ..writeln('▸ Output')
        ..write(_prettyJson(output));
    }
    final text = buf.toString();
    return text.length > 1600
        ? '${text.substring(0, 1600)}\n…(truncated)'
        : text;
  }

  String _prettyJson(Object? value) {
    if (value == null) return 'null';
    if (value is String) return value;
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  String _serialize(Object? data) {
    if (data == null) return 'null';
    if (data is String) return data;
    return jsonEncode(data);
  }

  /// Logs prompt-cache effectiveness in debug builds. After the first
  /// request in a 5-minute window the bulk of the prefix should land in
  /// `cache_read_input_tokens`; if `read` stays 0 across a loop, a silent
  /// invalidator has crept into tools/system/model (see prompt-caching docs).
  void _logCacheUsage(Object? usage) {
    if (!kDebugMode || usage is! Map) return;
    debugPrint(
      'anthropic cache — write: ${usage['cache_creation_input_tokens'] ?? 0}, '
      'read: ${usage['cache_read_input_tokens'] ?? 0}, '
      'uncached: ${usage['input_tokens'] ?? 0}',
    );
  }

  String _shortError(Object e) {
    final s = e.toString().replaceFirst('Exception: ', '');
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }
}

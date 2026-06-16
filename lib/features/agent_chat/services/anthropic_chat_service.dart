import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/services/anthropic_client.dart';
import '../../../data/models/job.dart';
import '../../email/models/recipient_resolution.dart';
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
  }) : _client = client ?? AnthropicClient(),
       _systemPrompt = systemPromptOverride ?? systemPrompt;

  /// The system prompt actually sent on every request. Defaults to the main
  /// chatbot's [systemPrompt]; callers may override it via
  /// [systemPromptOverride] for a one-off session with different framing.
  final String _systemPrompt;

  /// Per-turn autonomy directive (Assist / Auto-draft / Autopilot), set by the
  /// chat controller before each [runPrompt]. Sent as a *second* system block
  /// so the cacheable static prefix stays byte-identical while this small,
  /// user-specific instruction overrides the default chaining/gate behavior.
  /// Empty for the morning brief, which never sets it.
  String _autonomyDirective = '';

  @override
  void setAutonomyDirective(String directive) =>
      _autonomyDirective = directive.trim();

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
- Make a short internal plan and execute the safe steps with tools. Use tools to do the work — do not just
describe what you would do.
- Drive the workflow forward yourself toward that goal, narrating each decision in one short line as you go.
- HOW OFTEN you pause for the user — whether you chain steps or stop after each one — is NOT decided here. It
is set entirely by your ACTIVE AUTONOMY MODE (a separate system message). Do not hard-code a pace in this
prompt; follow the mode.
- When you do offer a next step, call `ask_user` with 2-3 tappable suggestion chips proposing a specific
action; never ask a vague "what would you like to do next?".
- Continue until you finish the work the user's goal implies or reach a user gate.
- Your ACTIVE AUTONOMY MODE is one of Assist / Auto-draft / Autopilot. It governs pacing and overrides any
pacing hint elsewhere in this prompt. If none is given, behave as Autopilot.

Career Memory:
- After `ask_user` returns an answer, inspect whether the answer contains a stable career fact.
- If the answer includes reusable skills, experience, preferences, constraints, target roles, location, salary, availability, or missing_info, call `remember_fact` before continuing the workflow.
- Use categories exactly: `skill`, `experience`, `preference`, `constraint`, `target_role`, `location`, `salary`, `availability`, `missing_info`, or `other`.
- Do not call `remember_fact` for one-off task choices, temporary job selections, button-like approvals, or sensitive personal attributes.
- Keep the saved `detail` factual and short. Do not infer beyond what the user said.
- When `read_resume`, `tailor_resume`, or `draft_email` receives `learned_facts`, use them only as confirmed user context.
- If learned facts materially affect matching, tailoring, or outreach, briefly say so in user-visible text with the phrase "Used Career Memory".
- Keep memory-use explanations short: mention at most 1-2 relevant facts, and do not list every stored memory.

Progressive autonomy / request scope:
- How far a job-search request expands is governed by your ACTIVE AUTONOMY MODE, not by the wording.
- In Assist mode ONLY, treat a bare discovery request — "find jobs", "search remote frontend roles", "I want
  full stack roles", "show me jobs" — as discovery-only: call `search_jobs`, show the job cards, add at most one
  short sentence, then call `ask_user` with 2-3 next-step chips. Do not call `read_resume`, `match_jobs`,
  `save_to_pipeline`, `tailor_resume`, `lookup_hiring_manager`, or `draft_email` until the user picks a step.
- In Auto-draft and Autopilot modes, the SAME request is a full apply goal: chain `search_jobs` -> `read_resume`
  -> `match_jobs` -> `save_to_pipeline` for the top matches, then `tailor_resume` -> `draft_email` for the
  strongest ones, stopping only at the two human gates. Do not pause to ask which roles unless genuinely ambiguous.
- Never invent personal, resume, or recipient details to keep moving.
- If the user asks to match jobs, read the resume and call `match_jobs`.
- If the user asks to save jobs, match them first when resume context is available, then call `save_to_pipeline`.
- If the user asks to tailor a resume, call `tailor_resume` and stop for review.
- If the user asks to draft outreach, draft only after the needed job/resume context exists, any required
  approval gate has passed, and you have called `resolve_company_contact` for that job/company.

Standard job-search sequence — follow it, one gate at a time:
1. `search_jobs` renders the roles as interactive cards. Add at most one short sentence introducing them.
   In Assist mode, if the user only asked to find/search/show jobs, stop here and call `ask_user` with
   next-step chips such as ["Match these with my resume", "Save best to Pipeline", "Tailor for the top role"].
   In Auto-draft / Autopilot, keep going without asking: match, save the top roles, then tailor and draft them.
2. If the user requested matching, call `read_resume` after `search_jobs`, then call `match_jobs`.
3. If the user requested saving, call `save_to_pipeline` after matching or after the user approves which jobs
   to save.
4. If the user wants tailoring but it is unclear which role, call `ask_user` so they choose the specific job.
   You need a job_id and a resume before tailoring.
5. `tailor_resume` only PROPOSES edits. After it returns, stop and let the user review the diff. Do not call
   `apply_resume_edits`, `draft_email`, or `send_email` yet.
6. After the app tells you the user saved the tailored resume, continue toward the user's goal: the usual next
   step is to draft recruiter outreach for that role. Whether you draft it immediately or first offer it with
   `ask_user` is set by your active autonomy mode, not decided here.
7. Before `draft_email`, call `resolve_company_contact` for the job/company. If it returns confidence `low`
   or `none`, you may still draft, but you must tell the user to verify or replace the recipient and stop
   before sending.
8. `draft_email` produces a draft only. The user reviews and sends it from the review screen. Never call
   `send_email` yourself.

User gates:
- There are exactly two hard human gates in the apply flow, and both are handled by the app UI — not by an
  `ask_user`: (1) the user reviews and SAVES the tailored resume, and (2) the user taps SEND on the email draft.
  Drive the workflow right up to each gate, then stop and let the app surface it.
- Beyond those two gates, pause only when you genuinely need information only the user can provide (e.g. target
  salary, which resume, a recipient email you cannot look up, or a preference). Then call `ask_user`.
- When required information is missing, call `ask_user` with 2-3 short suggestion chips unless the question is genuinely open-ended.
- Do not insert extra approval asks between steps the user already requested. Never invent personal details, resume details, recipient details, or user preferences.

Recipient Intelligence:
- JSearch job data does not provide recruiter/company emails. Use `resolve_company_contact` before `draft_email`.
- A `guessedPattern` recipient such as `careers@domain` is low confidence only. Never describe it as real,
  confirmed, safe, verified, or guaranteed.
- If recipient confidence is `low` or `none`, draft only and stop. Tell the user to verify or replace the
  recipient in the review screen. Do not call `send_email`.
- Never call `send_email` autonomously. The existing confirmation-token flow is the only send path.

Job results:
- The job cards are interactive (the user can swipe and tap). Do not re-list the jobs in prose — one short sentence is enough, then follow the sequence above and offer to tailor.

Resume tailoring:
- When tailoring a resume, propose changes — never overwrite directly.
- The `tailor_resume` tool only proposes edits. It does not apply edits, render PDFs, or save files.
- After `tailor_resume` returns proposed edits, stop and wait. The user reviews the edits in the diff viewer.
- Do not call `apply_resume_edits`, `draft_email`, or `send_email` until the user has accepted edits.
- Preserve supported resume facts only. Do not add unsupported employers, roles, dates, degrees, certifications,
  tools, skills, metrics, years of experience, or achievements just because a job description mentions them.
- Keep skill changes deduplicated. Do not add a skill that already appears elsewhere, and never output a bracketed
  repeated skill list as one skill item.
- If the app asks you to repair a tailored resume after an integrity check, call `tailor_resume` again for the same
  source resume and job, then stop at the replacement diff. Do not use `apply_resume_edits` for repairs.
- If the app later tells you the user approved and saved a tailored resume, continue the original workflow from there without asking the user to repeat the task.
- For a partial match ("Several Match") with missing skills, tailor using only the user's real resume facts and
  briefly note the gap in user-visible text. Do NOT stop to ask whether they have the missing skill, and never
  add that skill to the resume unless the user explicitly provided it.

Building a resume from scratch:
- If the user has no resume to upload, offer to build one with `build_resume`.
- Collect the details conversationally with `ask_user`: contact info first, then each work experience (company, role, dates, 2-4 achievement bullets), then education and skills. Ask in small batches — not one field at a time — and let the user paste what they already have.
- When you have enough, call `build_resume` ONCE with the full structure. It renders a preview only; it does NOT save. The user previews the PDF and taps Save.
- NEVER invent employers, titles, dates, or metrics. Use only what the user gave you and omit fields you don't have.
- Once saved, the new resume becomes a base resume the user can tailor to jobs — continue the workflow from there.
Match presentation:
- The matching system is purely qualitative. NEVER show the user a numeric score, percentage, rating, or any 0-100 value for a match. Do not mention numbers like "75" or "87" even if you saw one earlier.
- There are exactly three match labels: "All Match", "Several Match", "No Match". When you present matches, show match strength using ONLY the `match` label from match_jobs — never any other wording and never a number.
- Do not invent your own numbers or add a score column.

Formatting — never use tables:
- NEVER output a Markdown table. Do not produce `|`-delimited rows or a `--- | ---` separator row under any circumstances. Tables render badly and overflow on phones.
- The job cards / swipeable rail are how roles are compared. Do not rebuild that comparison as a table, even if the user asks you to "give me each", "list", or "compare" them.
- When you must present several roles or a comparison in text, use short prose or a simple bulleted list — one role per bullet, e.g. "- **Role title** — Company · All Match · one-line why".

Email and external actions:
- Drafting an email is safe; sending an email is not.
- Never call `send_email` unless the app provides an explicit user-confirmation token or says the user tapped Send.
- If outreach is the next step, call `resolve_company_contact` before `draft_email`; ask the user only when the recipient is still missing or needs information only they can provide.

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
          yield BlockAdded(
            TextBlock(
              id: nextBlockId('text'),
              text:
                  'I hit repeated tool failures while trying to complete that. Try narrowing the request, or give me the job/resume details directly.',
            ),
          );
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
          yield BlockAdded(
            TextBlock(
              id: nextBlockId('text'),
              text:
                  tailorPauseMessage ??
                  'I found proposed resume edits. Review them before I continue.',
            ),
          );
          yield const TurnCompleted();
          return;
        }

        // `build_resume` renders a preview only — saving is a user tap on the
        // draft card. Stop the turn so the user previews and saves before the
        // agent chains into anything that depends on the new resume.
        if (shouldPauseAfterBuildResume) {
          messages.add({'role': 'user', 'content': toolResults});
          yield BlockAdded(
            TextBlock(
              id: nextBlockId('text'),
              text:
                  buildResumePauseMessage ??
                  'I drafted your resume. Preview it before saving.',
            ),
          );
          yield const TurnCompleted();
          return;
        }

        // `draft_email` is user-gated the same way: the email draft card is the
        // only path that can save to Gmail (and the agent can't send at all).
        // Stop here so the user reviews the draft before anything reaches their
        // Drafts folder, and don't loop the result back into `send_email`.
        if (shouldPauseAfterDraftEmail) {
          messages.add({'role': 'user', 'content': toolResults});
          yield BlockAdded(
            TextBlock(
              id: nextBlockId('text'),
              text:
                  draftPauseMessage ??
                  'I drafted an email. Review it before I continue.',
            ),
          );
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
  bool provideUserAnswer(String blockId, String answer) {
    final completer = _pendingAsks.remove(blockId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(answer);
      return true;
    }
    return false;
  }

  @override
  void restoreConversationContext(List<ChatItem> items, {Job? threadJob}) {
    _pendingAsks.clear();
    _conversation.clear();

    final restoredContext = buildRestoredConversationContextForAgent(
      items,
      threadJob: threadJob,
    ).trim();

    if (restoredContext.isEmpty) return;

    _conversation.add({'role': 'user', 'content': restoredContext});
    _conversation.add({
      'role': 'assistant',
      'content':
          'Understood. I will use this restored Syncra conversation context to continue.',
    });
    _trimConversation();
  }

  @override
  void resetConversation() {
    _pendingAsks.clear();
    _conversation.clear();
  }

  @override
  List<Map<String, dynamic>> exportConversation() {
    final copy = List<Map<String, dynamic>>.from(_conversation);
    // A debounced persist can snapshot the history mid-loop — right after an
    // assistant `tool_use` turn but before its `tool_result` is appended.
    // Replaying a tool_use with no matching tool_result is an Anthropic 400,
    // so drop any such trailing turn(s); the conversation then ends on a safe
    // boundary (a tool_result that answers the prior call, or assistant text).
    while (copy.isNotEmpty && _endsOnUnansweredToolUse(copy)) {
      copy.removeLast();
    }
    return copy;
  }

  static bool _endsOnUnansweredToolUse(List<Map<String, dynamic>> messages) {
    final last = messages.last;
    if (last['role'] != 'assistant') return false;
    final content = last['content'];
    return content is List &&
        content.any((b) => b is Map && b['type'] == 'tool_use');
  }

  @override
  void importConversation(List<Map<String, dynamic>> messages) {
    _pendingAsks.clear();
    _conversation
      ..clear()
      ..addAll(messages);
    // Re-apply the same cap the live loop uses so a restored long session
    // can't exceed the request budget, and never starts on an orphaned
    // tool_result whose tool_use parent was trimmed away.
    _trimConversation();
  }

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
        // The active autonomy mode rides in a second, uncached block so it can
        // change per user / per turn without invalidating the cached prefix
        // above. Placed last so it wins over the static prompt's defaults.
        if (_autonomyDirective.isNotEmpty)
          {'type': 'text', 'text': _autonomyDirective},
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

      final justification =
          ((m['justification'] as String?) ??
                  (m['agent_justification'] as String?) ??
                  '')
              .trim();
      final description =
          ((m['description_excerpt'] as String?) ??
                  (m['description'] as String?) ??
                  (m['why'] as String?) ??
                  '')
              .trim();

      // `match_jobs` is the only tool that scores a role against the resume; its
      // result is the only one carrying the qualitative `match` label (plus a
      // justification / matched skills). `search_jobs` carries just the
      // catalogue's stored category, which is NOT a real fit signal — so leave
      // such roles unmatched and the rail keeps the match pill hidden until the
      // AI has actually scored them.
      final matched =
          m.containsKey('match') ||
          m.containsKey('matched_skills') ||
          m.containsKey('justification');

      jobs.add(
        Job(
          id: jobId,
          title: title,
          company: (m['company'] as String?)?.trim() ?? '',
          location: (m['location'] as String?)?.trim() ?? '',
          salary: (m['salary'] as String?)?.trim() ?? '',
          category: _jobCategoryFromName(m['category'] as String?),
          matchScore: _matchScoreFromData(m),
          agentAction: (m['agent_action'] as String?)?.trim() ?? '',
          agentJustification: justification,
          skills: _stringList(m['matched_skills'] ?? m['skills']),
          missingSkills: _stringList(m['missing_skills'] ?? m['missing']),
          why: description,
          matched: matched,
        ),
      );
    }

    return jobs;
  }

  /// Internal-only sort signal — never shown to the user. `search_jobs`
  /// carries no `match` field; `match_jobs` puts the *qualitative* label there
  /// ("All Match" / "Several Match" / "No Match"), never a number. A blind
  /// `as num?` cast on that label threw "type 'String' is not a subtype of
  /// type 'num?'", which the loop surfaced as a failed tool even though
  /// scoring had succeeded. Accept a real number when one is present, derive a
  /// coarse rank from the qualitative label otherwise, and default to 0.
  int _matchScoreFromData(Map<String, dynamic> m) {
    final raw = m['match'] ?? m['match_score'];
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final parsed = int.tryParse(raw.trim());
      if (parsed != null) return parsed;
      return switch (raw.trim().toLowerCase()) {
        'all match' => 3,
        'several match' => 2,
        'no match' => 1,
        _ => 0,
      };
    }
    return 0;
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
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
    final jobId = (data['job_id'] as String?)?.trim() ?? '';
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
      jobId: jobId.isEmpty ? null : jobId,
      recipientDomain:
          _cleanDataString(data['domain']) ??
          _cleanDataString(data['recipientDomain']),
      recipientConfidence: _recipientConfidenceFromData(data),
      recipientSource: _recipientSourceFromData(data),
      recipientSourceUrl:
          _cleanDataString(data['recipientSourceUrl']) ??
          _cleanDataString(data['sourceUrl']),
      recipientReason:
          _cleanDataString(data['recipientReason']) ??
          _cleanDataString(data['reason']),
      canAutoSend: data['canAutoSend'] == true,
      attachmentResumeId: (attachmentId == null || attachmentId.isEmpty)
          ? null
          : attachmentId,
      attachmentFilename: (attachmentName == null || attachmentName.isEmpty)
          ? null
          : attachmentName,
      // Freshly built from a live draft_email result — eligible for one-shot
      // auto-send. Restored history (chat_snapshot_codec) leaves this false.
      autoSendPending: true,
    );
  }

  String? _cleanDataString(Object? value) {
    final raw = value?.toString().trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  RecipientConfidence _recipientConfidenceFromData(Map<dynamic, dynamic> data) {
    final raw =
        _cleanDataString(data['recipientConfidence']) ??
        _cleanDataString(data['confidence']);
    if (raw == null) return RecipientConfidence.low;
    for (final confidence in RecipientConfidence.values) {
      if (confidence.name == raw) return confidence;
    }
    return RecipientConfidence.low;
  }

  RecipientSource _recipientSourceFromData(Map<dynamic, dynamic> data) {
    final raw =
        _cleanDataString(data['recipientSource']) ??
        _cleanDataString(data['source']);
    if (raw == null) return RecipientSource.guessedPattern;
    for (final source in RecipientSource.values) {
      if (source.name == raw) return source;
    }
    return RecipientSource.guessedPattern;
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

@visibleForTesting
String buildRestoredConversationContextForAgent(
  List<ChatItem> items, {
  Job? threadJob,
}) {
  if (items.isEmpty && threadJob == null) return '';

  final lines = <String>[
    'Previous Syncra conversation context restored from a saved UI snapshot.',
    'Use this only as context. Do not claim that tools ran again during restore.',
  ];

  if (threadJob != null) {
    lines.add('Active job thread: ${_restoredJobLabel(threadJob)}.');
  }

  final recentItems = items.length > 24
      ? items.sublist(items.length - 24)
      : items;

  for (final item in recentItems) {
    switch (item) {
      case UserMessage():
        final text = item.text.trim();
        if (text.isNotEmpty) {
          lines.add('User asked: ${_clipRestoredContext(text)}');
        }
        if (item.attachments.isNotEmpty) {
          final attachments = item.attachments
              .map((a) => '${a.name} (${a.id})')
              .join(', ');
          lines.add('User attached resume(s): $attachments.');
        }

      case AgentTurn():
        for (final block in item.blocks) {
          lines.addAll(_restoredBlockLines(block));
        }
        if (item.status == AgentTurnStatus.failed) {
          final error = item.errorMessage?.trim();
          lines.add(
            error == null || error.isEmpty
                ? 'The previous agent turn failed.'
                : 'The previous agent turn failed: ${_clipRestoredContext(error)}',
          );
        } else if (item.status == AgentTurnStatus.stopped) {
          lines.add('The previous agent turn was stopped before completion.');
        }
    }
  }

  final context = lines.join('\n');
  const maxChars = 10000;
  if (context.length <= maxChars) return context;

  return '${lines.first}\n...\n${context.substring(context.length - maxChars)}';
}

Iterable<String> _restoredBlockLines(AgentBlock block) sync* {
  switch (block) {
    case ThinkingBlock():
      // Do not feed restored thinking back as model context. User-visible text,
      // cards, tools, and decisions below are enough to continue safely.
      return;

    case TextBlock():
      final text = block.text.trim();
      if (text.isNotEmpty) {
        yield 'Syncra said: ${_clipRestoredContext(text)}';
      }

    case ToolCallBlock():
      final result = block.resultSummary?.trim();
      final status = block.status.name;
      if (result == null || result.isEmpty) {
        yield 'Syncra ran tool ${block.name} with status $status.';
      } else {
        yield 'Syncra ran tool ${block.name} with status $status: ${_clipRestoredContext(result)}';
      }

    case JobsBlock():
      if (block.jobs.isEmpty) return;
      final shown = block.jobs.take(3).map(_restoredJobLabel).join('; ');
      final more = block.jobs.length > 3
          ? ' and ${block.jobs.length - 3} more'
          : '';
      yield 'Syncra showed ${block.jobs.length} job card(s): $shown$more.';

    case ProposedEditsBlock():
      final jobPart = block.jobId == null ? '' : ' for job ${block.jobId}';
      final resumePart =
          block.resolvedResumeId ?? block.resumeId ?? block.savedResumeId;
      final resumeText = resumePart == null ? '' : ' using resume $resumePart';
      final savedText = block.savedResumeId == null
          ? ''
          : ' Saved tailored resume id: ${block.savedResumeId}.';
      yield 'Syncra has a proposed-edits card in state ${block.state.name}$jobPart$resumeText with ${block.edits.length} edit(s), ${block.acceptedCount} accepted, ${block.appliedCount} applied, and ${block.skippedCount} skipped.$savedText';

    case ResumeDraftBlock():
      final savedText = block.savedResumeId == null
          ? ''
          : ' Saved resume id: ${block.savedResumeId}.';
      final errorText = block.error == null || block.error!.trim().isEmpty
          ? ''
          : ' Error: ${_clipRestoredContext(block.error!)}';
      yield 'Syncra has a built-resume draft "${block.fileName}" in state ${block.state.name}.$savedText$errorText';

    case InputRequestBlock():
      if (block.state == InputRequestState.answered) {
        yield 'Syncra asked: ${_clipRestoredContext(block.question)} User answered: ${_clipRestoredContext(block.answer ?? '')}';
      } else {
        yield 'Syncra is waiting for user input: ${_clipRestoredContext(block.question)}';
      }

    case ActionProposalBlock():
      yield 'Syncra showed an action proposal "${block.title}" in state ${block.state.name}: ${_clipRestoredContext(block.description)}';

    case EmailDraftBlock():
      final attachmentText = block.attachmentResumeId == null
          ? ''
          : ' Attachment resume id: ${block.attachmentResumeId}.';
      final savedText = block.savedDraftId == null
          ? ''
          : ' Gmail draft id: ${block.savedDraftId}.';
      yield 'Syncra drafted an email to ${block.recipient} with subject "${block.subject}" in status ${block.status.name}.$attachmentText$savedText';
  }
}

String _restoredJobLabel(Job job) {
  final title = job.title.trim().isEmpty ? 'Untitled role' : job.title.trim();
  final company = job.company.trim().isEmpty
      ? 'Unknown company'
      : job.company.trim();
  final location = job.location.trim().isEmpty
      ? 'Unknown location'
      : job.location.trim();
  return '$title at $company in $location (${job.matchLabel}, id: ${job.id})';
}

String _clipRestoredContext(String value, {int max = 420}) {
  final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.length <= max) return clean;
  return '${clean.substring(0, max)}…';
}

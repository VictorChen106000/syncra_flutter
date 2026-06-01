import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../data/models/job.dart';
import '../../resumes/models/proposed_edit.dart';
import '../../resumes/models/resume_json.dart';

/// One unit of agent output inside an [AgentTurn].
///
/// A turn is a sequence of blocks (thinking → tool calls → text → proposals).
/// New block types can be added without touching the controller — just
/// implement a render branch in `agent_turn_view.dart`.
sealed class AgentBlock {
  AgentBlock({required this.id});
  final String id;
}

/// The agent's internal reasoning. Shown collapsed by default, like Claude's
/// "Thinking" disclosure.
class ThinkingBlock extends AgentBlock {
  ThinkingBlock({required super.id, required this.content});
  final String content;
}

enum ToolCallStatus { running, done, failed }

/// A tool the agent invoked. While [status] is [ToolCallStatus.running] the
/// UI shows a spinner; once [status] flips to [ToolCallStatus.done] the
/// [resultSummary] is rendered as a one-line outcome.
class ToolCallBlock extends AgentBlock {
  ToolCallBlock({
    required super.id,
    required this.name,
    required this.label,
    required this.icon,
    this.status = ToolCallStatus.running,
    this.resultSummary,
    this.detail,
  });

  final String name;
  final String label;
  final IconData icon;
  ToolCallStatus status;
  String? resultSummary;

  /// Optional drill-down: the tool's inputs/outputs, shown when the user taps
  /// the call to inspect it. Null when there's nothing more to reveal. Set at
  /// construction with the input args, then replaced with input + output once
  /// the call completes — hence mutable, like [status] and [resultSummary].
  String? detail;
}

/// Plain prose from the agent (markdown-free for now).
class TextBlock extends AgentBlock {
  TextBlock({required super.id, required this.text});
  final String text;
}

/// A list of job matches the agent surfaced via `search_jobs`. Rendered as a
/// horizontally-swipeable rail of "prompt cards" — the same card language as
/// the dashboard — instead of the agent narrating the roles as prose. The rail
/// is read-only chrome; tapping a card opens the shared job action sheet.
class JobsBlock extends AgentBlock {
  JobsBlock({required super.id, required this.jobs});

  /// Mutable so `match_jobs` can re-score the rail in place — see
  /// [JobsBlockUpdated]. A fresh search still mints a new block.
  List<Job> jobs;
}

/// Where a single proposed edit stands in the user's review. Each edit starts
/// [pending] and the user flips it to [accepted] or [rejected] in the diff
/// viewer before applying.
enum EditDecision { pending, accepted, rejected }

/// Lifecycle of the whole proposed-edits card. While [reviewing] the user can
/// toggle individual edits; tapping Apply flips to [applying] while the
/// tailored PDF renders, then [applied] (preview ready, not yet saved). The
/// card settles to [dismissed] if the user dismisses it instead.
enum ProposedEditsState { reviewing, applying, applied, dismissed }

/// PR-style resume edits proposed by `tailor_resume`.
///
/// The diff viewer renders one row per [edits] entry with Accept / Reject
/// controls. Per-edit choices live in [decisions] (index-aligned with [edits]);
/// the overall card lifecycle lives in [state]. Both are mutable so the
/// notifier can flip them in place and re-emit, matching [ActionProposalBlock].
class ProposedEditsBlock extends AgentBlock {
  ProposedEditsBlock({
    required super.id,
    required this.edits,
    this.jobId,
    this.resumeId,
    List<EditDecision>? decisions,
    this.state = ProposedEditsState.reviewing,
  }) : decisions =
           decisions ??
           List<EditDecision>.filled(edits.length, EditDecision.pending);

  /// Builds a card that is already settled as **applied**, every edit
  /// auto-accepted. The tailor flow uses this: it applies the proposed edits
  /// directly instead of asking the user to accept/reject each one, so the
  /// card renders as a read-only record of what changed.
  factory ProposedEditsBlock.applied({
    required String id,
    required List<ProposedEdit> edits,
    String? jobId,
    String? resumeId,
  }) {
    return ProposedEditsBlock(
      id: id,
      edits: edits,
      jobId: jobId,
      resumeId: resumeId,
      decisions:
          List<EditDecision>.filled(edits.length, EditDecision.accepted),
      state: ProposedEditsState.applied,
    );
  }

  final List<ProposedEdit> edits;
  final String? jobId;
  final String? resumeId;

  /// Per-edit review choice, index-aligned with [edits]. Mutable: the notifier
  /// updates an entry then re-emits the chat state.
  final List<EditDecision> decisions;

  /// Whole-card lifecycle. Mutable for the same reason as [decisions].
  ProposedEditsState state;

  /// The rendered-but-unsaved tailored PDF, set once [state] reaches
  /// [ProposedEditsState.applied]. The preview screen reads this; it's only
  /// persisted to the resume library when the user taps Save (see
  /// [savedResumeId]). Mutable so the notifier can fill it in after rendering.
  Uint8List? previewBytes;

  /// The [ResumeJson] behind [previewBytes] — handed to the orchestrator's
  /// save step so the new resume doc caches its parsed structure.
  ResumeJson? previewResume;

  /// The source resume id actually used to render (resolved from [resumeId],
  /// or the latest manual resume when the card carried none).
  String? resolvedResumeId;

  /// Set once the previewed PDF has been saved to the resume library. While
  /// null, the preview exists only in memory.
  String? savedResumeId;

  /// How many accepted edits actually landed / were skipped during render.
  int appliedCount = 0;
  int skippedCount = 0;

  /// Last apply/save error, surfaced in the card so the user can retry.
  String? applyError;

  bool get isSaved => savedResumeId != null;

  int get acceptedCount =>
      decisions.where((d) => d == EditDecision.accepted).length;

  bool get hasPending => decisions.any((d) => d == EditDecision.pending);

  /// The edits the user accepted — the payload handed to the resume-apply
  /// logic when the card is applied.
  List<ProposedEdit> get acceptedEdits => [
    for (var i = 0; i < edits.length; i++)
      if (decisions[i] == EditDecision.accepted) edits[i],
  ];
}

enum InputRequestState { pending, answered }

/// The agent paused mid-loop because it needs information only the user can
/// provide. Renders as an inline text field (plus optional suggestion chips)
/// inside the chat transcript. Once the user submits an answer, the agent
/// loop resumes with that answer as the `ask_user` tool result.
class InputRequestBlock extends AgentBlock {
  InputRequestBlock({
    required super.id,
    required this.question,
    this.suggestions = const [],
    this.continuationPrompt,
    this.state = InputRequestState.pending,
    this.answer,
  });

  final String question;
  final List<String> suggestions;

  /// Hidden instruction sent back into the threaded agent loop after the user
  /// answers this input request. Real `ask_user` blocks do not need this
  /// because `AnthropicChatService` already has a pending tool-use completer.
  /// Locally-created opener questions use it to continue the workflow.
  final String? continuationPrompt;

  InputRequestState state;
  String? answer;
}

enum ActionState { pending, accepted, dismissed }

/// A concrete action the agent wants to take. Surfaces Accept / Make changes
/// buttons so the user stays in control.
class ActionProposalBlock extends AgentBlock {
  ActionProposalBlock({
    required super.id,
    required this.icon,
    required this.title,
    required this.description,
    this.acceptLabel = 'Accept',
    this.editLabel = 'Make changes',
    this.continuationPrompt,
    this.state = ActionState.pending,
  });

  final IconData icon;
  final String title;
  final String description;
  final String acceptLabel;
  final String editLabel;

  /// Hidden instruction sent back into the threaded agent loop after the user
  /// accepts this proposal. This is what makes approval cards continue the
  /// workflow instead of behaving like dead-end UI state.
  final String? continuationPrompt;

  ActionState state;
}

/// Lifecycle of an [EmailDraftBlock]. While [reviewing] the user can open the
/// review sheet; once they save it to Gmail Drafts the card settles to
/// [saved]. There is no "sent" state — the chat path only ever saves drafts;
/// the user finishes and sends from Gmail themselves.
enum EmailDraftStatus { reviewing, saved }

/// An email the agent drafted — either a cold outreach via `draft_email`, or a
/// self-delivery of a freshly tailored resume fired automatically after
/// `apply_resume_edits`. Surfaced inline so the user can open the review sheet,
/// edit the recipient/subject/body, and save it to their Gmail Drafts. Nothing
/// is ever sent from here — the review sheet runs in draft mode (see
/// `EmailReviewPage`/`EmailReviewMode.draft`).
///
/// Like [ProposedEditsBlock], the agent pauses after emitting this so it can't
/// barrel on into `send_email`; the user gates the next step.
class EmailDraftBlock extends AgentBlock {
  EmailDraftBlock({
    required super.id,
    required this.recipient,
    required this.subject,
    required this.body,
    this.status = EmailDraftStatus.reviewing,
    this.savedDraftId,
    this.attachmentResumeId,
    this.attachmentFilename,
  });

  final String recipient;
  final String subject;
  final String body;

  /// When set, the review sheet attaches this resume's PDF to the draft. Holds
  /// the resume id (manual or tailored) — the view downloads the bytes lazily
  /// via `bytesFor` when the user opens the sheet. Null for plain text drafts.
  final String? attachmentResumeId;

  /// Display filename for the attached resume PDF (e.g. `tailored_acme.pdf`).
  /// Null when there is no attachment.
  final String? attachmentFilename;

  /// Whole-card lifecycle. Mutable so the notifier can flip it to [saved]
  /// once the draft lands in Gmail and re-emit the chat state.
  EmailDraftStatus status;

  /// The Gmail draft id, set once the draft has been created. While null,
  /// nothing has been saved yet.
  String? savedDraftId;
}

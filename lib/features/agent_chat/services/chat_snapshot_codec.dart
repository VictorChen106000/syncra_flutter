import 'package:flutter/material.dart';

import '../../../data/models/job.dart';
import '../../resumes/models/proposed_edit.dart';
import '../../resumes/models/resume_integrity_result.dart';
import '../../resumes/models/resume_json.dart';
import '../models/agent_block.dart';
import '../models/chat_message.dart';

/// Converts the chat transcript UI model to/from Firestore-safe JSON maps.
///
/// This codec is intentionally defensive: unknown or malformed blocks return
/// null instead of throwing, so one bad historical snapshot never prevents the
/// whole conversation from opening.
class ChatSnapshotCodec {
  const ChatSnapshotCodec._();

  static Map<String, dynamic> encodeItem(ChatItem item) {
    return switch (item) {
      UserMessage() => _encodeUserMessage(item),
      AgentTurn() => _encodeAgentTurn(item),
    };
  }

  static ChatItem? decodeItem(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<dynamic, dynamic>.from(raw);
    final kind = _kindOf(map);
    final id = _string(map, 'id')?.trim();
    if (id == null || id.isEmpty) return null;

    switch (kind) {
      case 'user':
      case 'user_message':
        final text = _string(map, 'text')?.trim();
        if (text == null || text.isEmpty) return null;
        return UserMessage(
          id: id,
          text: text,
          attachments: _decodeAttachments(map['attachments']),
        );
      case 'agent':
        return _decodeLegacyAgentTurn(id, map);
      case 'agent_turn':
        return _decodeAgentTurn(id, map);
      default:
        return null;
    }
  }

  static Map<String, dynamic> encodeBlock(AgentBlock block) {
    return switch (block) {
      ThinkingBlock() => {
        'kind': 'thinking',
        'id': block.id,
        'content': block.content,
      },
      ToolCallBlock() => {
        'kind': 'tool_call',
        'id': block.id,
        'name': block.name,
        'label': block.label,
        'iconKey': _iconKeyFor(block.icon, fallbackToolName: block.name),
        'status': _encodeToolStatus(block.status),
        if (_clean(block.resultSummary) != null)
          'resultSummary': _clean(block.resultSummary),
        if (_clean(block.detail) != null) 'detail': _clean(block.detail),
      },
      TextBlock() => {'kind': 'text', 'id': block.id, 'text': block.text},
      JobsBlock() => {
        'kind': 'jobs',
        'id': block.id,
        'jobs': [for (final job in block.jobs) job.toJson()],
      },
      ProposedEditsBlock() => _encodeProposedEditsBlock(block),
      ResumeDraftBlock() => _encodeResumeDraftBlock(block),
      InputRequestBlock() => _encodeInputRequestBlock(block),
      ActionProposalBlock() => _encodeActionProposalBlock(block),
      EmailDraftBlock() => _encodeEmailDraftBlock(block),
    };
  }

  static AgentBlock? decodeBlock(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<dynamic, dynamic>.from(raw);
    final kind = _kindOf(map);
    final id = _string(map, 'id')?.trim();
    if (id == null || id.isEmpty) return null;

    switch (kind) {
      case 'thinking':
      case 'thinking_block':
        final content = _string(map, 'content')?.trim();
        if (content == null || content.isEmpty) return null;
        return ThinkingBlock(id: id, content: content);
      case 'tool':
      case 'tool_call':
      case 'tool_call_block':
        final name = _string(map, 'name')?.trim() ?? 'tool';
        final label = _string(map, 'label')?.trim() ?? name;
        final status = _decodeToolStatus(_string(map, 'status'));
        return ToolCallBlock(
          id: id,
          name: name,
          label: label,
          icon: _iconFromKey(_string(map, 'iconKey'), toolName: name),
          status: status == ToolCallStatus.running
              ? ToolCallStatus.failed
              : status,
          resultSummary: status == ToolCallStatus.running
              ? 'Interrupted before completion.'
              : _clean(_string(map, 'resultSummary')),
          detail: _clean(_string(map, 'detail')),
        );
      case 'text':
      case 'textblock':
      case 'text_block':
        final text = _string(map, 'text')?.trim();
        if (text == null || text.isEmpty) return null;
        return TextBlock(id: id, text: text);
      case 'jobs':
      case 'jobs_block':
        final jobs = _decodeJobs(map['jobs']);
        if (jobs.isEmpty) return null;
        return JobsBlock(id: id, jobs: jobs);
      case 'proposed_edits':
      case 'proposed_edits_block':
        return _decodeProposedEditsBlock(id, map);
      case 'resume_draft':
      case 'resume_draft_block':
        return _decodeResumeDraftBlock(id, map);
      case 'input_request':
      case 'input_request_block':
        return _decodeInputRequestBlock(id, map);
      case 'action_proposal':
      case 'action_proposal_block':
        return _decodeActionProposalBlock(id, map);
      case 'email_draft':
      case 'email_draft_block':
        return _decodeEmailDraftBlock(id, map);
      default:
        return null;
    }
  }

  static Map<String, dynamic> _encodeUserMessage(UserMessage item) {
    return {
      'kind': 'user',
      'id': item.id,
      'text': item.text,
      if (item.attachments.isNotEmpty)
        'attachments': [
          for (final attachment in item.attachments)
            {'id': attachment.id, 'name': attachment.name},
        ],
    };
  }

  static Map<String, dynamic> _encodeAgentTurn(AgentTurn item) {
    final status = item.status == AgentTurnStatus.streaming
        ? AgentTurnStatus.stopped
        : item.status;
    return {
      'kind': 'agent_turn',
      'id': item.id,
      'status': status.name,
      if (_clean(item.errorMessage) != null) 'errorMessage': item.errorMessage,
      'blocks': [for (final block in item.blocks) encodeBlock(block)],
    };
  }

  static AgentTurn? _decodeAgentTurn(String id, Map<dynamic, dynamic> map) {
    final blocks = _decodeBlocks(map['blocks']);
    if (blocks.isEmpty) return null;
    final status = _decodeTurnStatus(_string(map, 'status'));
    return AgentTurn(
      id: id,
      blocks: blocks,
      status: status == AgentTurnStatus.streaming
          ? AgentTurnStatus.stopped
          : status,
      errorMessage: _clean(_string(map, 'errorMessage')),
    );
  }

  static AgentTurn? _decodeLegacyAgentTurn(
    String id,
    Map<dynamic, dynamic> map,
  ) {
    final text = _clean(_string(map, 'text')) ?? _legacyTextFromBlocks(map);
    if (text == null || text.isEmpty) return null;
    return AgentTurn(
      id: id,
      blocks: [TextBlock(id: '$id-text', text: text)],
      status: AgentTurnStatus.done,
    );
  }

  static Map<String, dynamic> _encodeProposedEditsBlock(
    ProposedEditsBlock block,
  ) {
    return {
      'kind': 'proposed_edits',
      'id': block.id,
      if (_clean(block.jobId) != null) 'jobId': block.jobId,
      if (_clean(block.resumeId) != null) 'resumeId': block.resumeId,
      if (_clean(block.resolvedResumeId) != null)
        'resolvedResumeId': block.resolvedResumeId,
      if (_clean(block.savedResumeId) != null)
        'savedResumeId': block.savedResumeId,
      'state': block.state.name,
      'edits': [for (final edit in block.edits) edit.toJson()],
      'decisions': [for (final decision in block.decisions) decision.name],
      'appliedCount': block.appliedCount,
      'skippedCount': block.skippedCount,
      if (block.integrity != null)
        'integrity_result': block.integrity!.toJson(),
      if (block.integrityRepairAttempted)
        'integrityRepairAttempted': block.integrityRepairAttempted,
      if (block.integrityAutoRepairing)
        'integrityAutoRepairing': block.integrityAutoRepairing,
      if (_clean(block.supersededByBlockId) != null)
        'supersededByBlockId': block.supersededByBlockId,
      if (_clean(block.applyError) != null) 'applyError': block.applyError,
      if (_clean(block.previewStoragePath) != null)
        'previewStoragePath': block.previewStoragePath,
      if (block.previewResume != null)
        'previewResume': block.previewResume!.toJson(),
    };
  }

  static ProposedEditsBlock? _decodeProposedEditsBlock(
    String id,
    Map<dynamic, dynamic> map,
  ) {
    final edits = _decodeProposedEdits(map['edits']);
    if (edits.isEmpty) return null;
    final decisions = _decodeEditDecisions(map['decisions'], edits.length);
    final block = ProposedEditsBlock(
      id: id,
      edits: edits,
      jobId: _clean(_string(map, 'jobId')),
      resumeId: _clean(_string(map, 'resumeId')),
      decisions: decisions,
      state: _decodeProposedEditsState(_string(map, 'state')),
    );
    block.resolvedResumeId = _clean(_string(map, 'resolvedResumeId'));
    block.savedResumeId = _clean(_string(map, 'savedResumeId'));
    block.appliedCount = _int(map['appliedCount']);
    block.skippedCount = _int(map['skippedCount']);
    block.integrity = _decodeIntegrityResult(
      map['integrity_result'] ?? map['integrity'],
    );
    block.integrityRepairAttempted = _bool(map['integrityRepairAttempted']);
    block.integrityAutoRepairing = _bool(map['integrityAutoRepairing']);
    block.supersededByBlockId = _clean(_string(map, 'supersededByBlockId'));
    block.applyError = _clean(_string(map, 'applyError'));
    block.previewStoragePath = _clean(_string(map, 'previewStoragePath'));
    block.previewResume = _decodeResumeJson(map['previewResume']);
    return block;
  }

  static Map<String, dynamic> _encodeResumeDraftBlock(ResumeDraftBlock block) {
    return {
      'kind': 'resume_draft',
      'id': block.id,
      'fileName': block.fileName,
      'state': block.state.name,
      'resume': block.resume.toJson(),
      if (_clean(block.savedResumeId) != null)
        'savedResumeId': block.savedResumeId,
      if (_clean(block.previewStoragePath) != null)
        'previewStoragePath': block.previewStoragePath,
      if (_clean(block.error) != null) 'error': block.error,
    };
  }

  static ResumeDraftBlock? _decodeResumeDraftBlock(
    String id,
    Map<dynamic, dynamic> map,
  ) {
    final resume = _decodeResumeJson(map['resume']);
    final fileName = _string(map, 'fileName')?.trim();
    if (resume == null || fileName == null || fileName.isEmpty) return null;
    final block = ResumeDraftBlock(
      id: id,
      resume: resume,
      fileName: fileName,
      state: _decodeResumeDraftState(_string(map, 'state')),
    );
    block.savedResumeId = _clean(_string(map, 'savedResumeId'));
    block.previewStoragePath = _clean(_string(map, 'previewStoragePath'));
    block.error = _clean(_string(map, 'error'));
    return block;
  }

  static Map<String, dynamic> _encodeInputRequestBlock(
    InputRequestBlock block,
  ) {
    return {
      'kind': 'input_request',
      'id': block.id,
      'question': block.question,
      'suggestions': block.suggestions,
      if (_clean(block.continuationPrompt) != null)
        'continuationPrompt': block.continuationPrompt,
      'state': block.state.name,
      if (_clean(block.answer) != null) 'answer': block.answer,
    };
  }

  static InputRequestBlock? _decodeInputRequestBlock(
    String id,
    Map<dynamic, dynamic> map,
  ) {
    final question = _string(map, 'question')?.trim();
    if (question == null || question.isEmpty) return null;
    return InputRequestBlock(
      id: id,
      question: question,
      suggestions: _stringList(map['suggestions']),
      continuationPrompt: _clean(_string(map, 'continuationPrompt')),
      state: _decodeInputRequestState(_string(map, 'state')),
      answer: _clean(_string(map, 'answer')),
    );
  }

  static Map<String, dynamic> _encodeActionProposalBlock(
    ActionProposalBlock block,
  ) {
    return {
      'kind': 'action_proposal',
      'id': block.id,
      'iconKey': _iconKeyFor(block.icon),
      'title': block.title,
      'description': block.description,
      'acceptLabel': block.acceptLabel,
      'editLabel': block.editLabel,
      if (_clean(block.continuationPrompt) != null)
        'continuationPrompt': block.continuationPrompt,
      'state': block.state.name,
    };
  }

  static ActionProposalBlock? _decodeActionProposalBlock(
    String id,
    Map<dynamic, dynamic> map,
  ) {
    final title = _string(map, 'title')?.trim();
    final description = _string(map, 'description')?.trim();
    if (title == null ||
        title.isEmpty ||
        description == null ||
        description.isEmpty) {
      return null;
    }
    return ActionProposalBlock(
      id: id,
      icon: _iconFromKey(_string(map, 'iconKey')),
      title: title,
      description: description,
      acceptLabel: _string(map, 'acceptLabel')?.trim() ?? 'Accept',
      editLabel: _string(map, 'editLabel')?.trim() ?? 'Make changes',
      continuationPrompt: _clean(_string(map, 'continuationPrompt')),
      state: _decodeActionState(_string(map, 'state')),
    );
  }

  static Map<String, dynamic> _encodeEmailDraftBlock(EmailDraftBlock block) {
    return {
      'kind': 'email_draft',
      'id': block.id,
      'recipient': block.recipient,
      'subject': block.subject,
      'body': block.body,
      if (_clean(block.jobId) != null) 'jobId': block.jobId,
      'status': block.status.name,
      if (_clean(block.savedDraftId) != null)
        'savedDraftId': block.savedDraftId,
      if (_clean(block.attachmentResumeId) != null)
        'attachmentResumeId': block.attachmentResumeId,
      if (_clean(block.attachmentFilename) != null)
        'attachmentFilename': block.attachmentFilename,
    };
  }

  static EmailDraftBlock? _decodeEmailDraftBlock(
    String id,
    Map<dynamic, dynamic> map,
  ) {
    final recipient = _string(map, 'recipient')?.trim();
    final subject = _string(map, 'subject')?.trim();
    final body = _string(map, 'body')?.trim();
    if (recipient == null ||
        recipient.isEmpty ||
        subject == null ||
        subject.isEmpty ||
        body == null ||
        body.isEmpty) {
      return null;
    }
    return EmailDraftBlock(
      id: id,
      recipient: recipient,
      subject: subject,
      body: body,
      jobId: _clean(_string(map, 'jobId')),
      status: _decodeEmailDraftStatus(_string(map, 'status')),
      savedDraftId: _clean(_string(map, 'savedDraftId')),
      attachmentResumeId: _clean(_string(map, 'attachmentResumeId')),
      attachmentFilename: _clean(_string(map, 'attachmentFilename')),
    );
  }

  static List<AgentBlock> _decodeBlocks(Object? raw) {
    if (raw is! List) return const [];
    return raw.map(decodeBlock).whereType<AgentBlock>().toList(growable: false);
  }

  static List<ChatAttachment> _decodeAttachments(Object? raw) {
    if (raw is! List) return const [];
    final attachments = <ChatAttachment>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = Map<dynamic, dynamic>.from(entry);
      final id = _string(map, 'id')?.trim();
      final name = _string(map, 'name')?.trim();
      if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
      attachments.add(ChatAttachment(id: id, name: name));
    }
    return attachments;
  }

  static List<Job> _decodeJobs(Object? raw) {
    if (raw is! List) return const [];
    final jobs = <Job>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        jobs.add(Job.fromJson(Map<String, dynamic>.from(entry)));
      } catch (_) {
        continue;
      }
    }
    return jobs;
  }

  static List<ProposedEdit> _decodeProposedEdits(Object? raw) {
    if (raw is! List) return const [];
    final edits = <ProposedEdit>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        final edit = ProposedEdit.fromJson(Map<String, dynamic>.from(entry));
        if (edit.isValid) edits.add(edit);
      } catch (_) {
        continue;
      }
    }
    return edits;
  }

  static ResumeJson? _decodeResumeJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      return ResumeJson.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  static ResumeIntegrityResult? _decodeIntegrityResult(Object? raw) {
    if (raw is! Map) return null;
    try {
      return ResumeIntegrityResult.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  static List<EditDecision> _decodeEditDecisions(Object? raw, int length) {
    final decoded = raw is List
        ? raw.map((value) => _decodeEditDecision(value?.toString())).toList()
        : <EditDecision>[];
    if (decoded.length == length) return decoded;
    return List<EditDecision>.filled(length, EditDecision.pending);
  }

  static String? _legacyTextFromBlocks(Map<dynamic, dynamic> map) {
    final blocks = map['blocks'];
    if (blocks is! List) return null;
    final buffer = StringBuffer();
    for (final block in blocks) {
      if (block is! Map) continue;
      final blockMap = Map<dynamic, dynamic>.from(block);
      final kind = _kindOf(blockMap);
      if (kind.isNotEmpty && kind != 'text' && kind != 'textblock') continue;
      final text = _string(blockMap, 'text')?.trim();
      if (text == null || text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(text);
    }
    final value = buffer.toString();
    return value.isEmpty ? null : value;
  }

  static AgentTurnStatus _decodeTurnStatus(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'failed' => AgentTurnStatus.failed,
      'stopped' => AgentTurnStatus.stopped,
      'streaming' => AgentTurnStatus.streaming,
      _ => AgentTurnStatus.done,
    };
  }

  static ToolCallStatus _decodeToolStatus(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'running' => ToolCallStatus.running,
      'failed' => ToolCallStatus.failed,
      _ => ToolCallStatus.done,
    };
  }

  static String _encodeToolStatus(ToolCallStatus status) {
    return status == ToolCallStatus.running ? 'failed' : status.name;
  }

  static EditDecision _decodeEditDecision(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'accepted' => EditDecision.accepted,
      'rejected' => EditDecision.rejected,
      _ => EditDecision.pending,
    };
  }

  static ProposedEditsState _decodeProposedEditsState(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'applying' => ProposedEditsState.applying,
      'applied' => ProposedEditsState.applied,
      'dismissed' => ProposedEditsState.dismissed,
      _ => ProposedEditsState.reviewing,
    };
  }

  static ResumeDraftState _decodeResumeDraftState(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'ready' => ResumeDraftState.ready,
      _ => ResumeDraftState.rendering,
    };
  }

  static InputRequestState _decodeInputRequestState(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'answered' => InputRequestState.answered,
      _ => InputRequestState.pending,
    };
  }

  static ActionState _decodeActionState(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'accepted' => ActionState.accepted,
      'dismissed' => ActionState.dismissed,
      _ => ActionState.pending,
    };
  }

  static EmailDraftStatus _decodeEmailDraftStatus(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'saved' => EmailDraftStatus.saved,
      _ => EmailDraftStatus.reviewing,
    };
  }

  static String _kindOf(Map<dynamic, dynamic> map) {
    return (_string(map, 'kind') ?? _string(map, 'type') ?? '')
        .trim()
        .toLowerCase();
  }

  static String? _string(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    return value is String ? value : null;
  }

  static int _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  static bool _bool(Object? raw) {
    if (raw is bool) return raw;
    return raw?.toString().trim().toLowerCase() == 'true';
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  static String _iconKeyFor(IconData icon, {String? fallbackToolName}) {
    final toolKey = _toolIconKey(fallbackToolName);
    if (toolKey != null) return toolKey;
    for (final entry in _iconsByKey.entries) {
      final value = entry.value;
      if (value.codePoint == icon.codePoint &&
          value.fontFamily == icon.fontFamily) {
        return entry.key;
      }
    }
    return 'auto_awesome';
  }

  static IconData _iconFromKey(String? raw, {String? toolName}) {
    final key = _clean(raw);
    if (key != null && _iconsByKey.containsKey(key)) return _iconsByKey[key]!;
    final toolKey = _toolIconKey(toolName);
    if (toolKey != null) return _iconsByKey[toolKey]!;
    return Icons.auto_awesome_rounded;
  }

  static String? _toolIconKey(String? toolName) {
    return switch (toolName?.trim()) {
      'search_jobs' => 'travel_explore',
      'read_resume' => 'description',
      'match_jobs' => 'analytics',
      'check_job_risk' => 'verified_user',
      'save_to_pipeline' => 'playlist_add_check',
      'tailor_resume' => 'auto_fix_high',
      'apply_resume_edits' => 'difference',
      'build_resume' => 'article',
      'draft_email' => 'mail',
      'send_email' => 'send',
      'ask_user' => 'help',
      _ => null,
    };
  }

  static const Map<String, IconData> _iconsByKey = {
    'analytics': Icons.analytics_rounded,
    'article': Icons.article_rounded,
    'auto_awesome': Icons.auto_awesome_rounded,
    'auto_fix_high': Icons.auto_fix_high_rounded,
    'description': Icons.description_rounded,
    'difference': Icons.difference_rounded,
    'help': Icons.help_outline_rounded,
    'mail': Icons.mail_outline_rounded,
    'playlist_add_check': Icons.playlist_add_check_rounded,
    'send': Icons.send_rounded,
    'travel_explore': Icons.travel_explore_rounded,
    'verified_user': Icons.verified_user_rounded,
  };
}

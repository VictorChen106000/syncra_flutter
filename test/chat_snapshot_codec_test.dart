import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/features/agent_chat/models/agent_block.dart';
import 'package:syncra/features/agent_chat/models/chat_message.dart';
import 'package:syncra/features/agent_chat/services/chat_snapshot_codec.dart';
import 'package:syncra/features/resumes/models/proposed_edit.dart';
import 'package:syncra/features/resumes/models/resume_json.dart';

void main() {
  group('ChatSnapshotCodec', () {
    test('round-trips user messages with resume attachments', () {
      final original = UserMessage(
        id: 'user-1',
        text: 'Find matching roles',
        attachments: const [
          ChatAttachment(id: 'resume-1', name: 'Alex Resume.pdf'),
        ],
      );

      final decoded = ChatSnapshotCodec.decodeItem(
        ChatSnapshotCodec.encodeItem(original),
      );

      expect(decoded, isA<UserMessage>());
      final user = decoded as UserMessage;
      expect(user.id, 'user-1');
      expect(user.text, 'Find matching roles');
      expect(user.attachments.single.id, 'resume-1');
      expect(user.attachments.single.name, 'Alex Resume.pdf');
    });

    test('round-trips tool calls, text, and job-card blocks', () {
      final turn = AgentTurn(
        id: 'turn-1',
        status: AgentTurnStatus.done,
        blocks: [
          ToolCallBlock(
            id: 'tool-1',
            name: 'search_jobs',
            label: 'Searching jobs',
            icon: Icons.travel_explore_rounded,
            status: ToolCallStatus.done,
            resultSummary: 'Found 1 role',
            detail: 'query: frontend',
          ),
          JobsBlock(id: 'jobs-1', jobs: [_job()]),
          TextBlock(id: 'text-1', text: 'I found a strong match.'),
        ],
      );

      final decoded = ChatSnapshotCodec.decodeItem(
        ChatSnapshotCodec.encodeItem(turn),
      );

      expect(decoded, isA<AgentTurn>());
      final restored = decoded as AgentTurn;
      expect(restored.status, AgentTurnStatus.done);
      expect(restored.blocks, hasLength(3));

      final tool = restored.blocks[0] as ToolCallBlock;
      expect(tool.name, 'search_jobs');
      expect(tool.status, ToolCallStatus.done);
      expect(tool.resultSummary, 'Found 1 role');

      final jobs = restored.blocks[1] as JobsBlock;
      expect(jobs.jobs.single.id, 'job-1');
      expect(jobs.jobs.single.category, JobCategory.ready);

      final text = restored.blocks[2] as TextBlock;
      expect(text.text, 'I found a strong match.');
    });

    test('round-trips proposed edits block state', () {
      final block =
          ProposedEditsBlock(
              id: 'edits-1',
              jobId: 'job-1',
              resumeId: 'resume-1',
              edits: [_edit()],
              decisions: [EditDecision.accepted],
              state: ProposedEditsState.applied,
            )
            ..resolvedResumeId = 'resume-1'
            ..savedResumeId = 'resume-2'
            ..previewStoragePath =
                'users/u1/conversation_previews/conv-1/edits-1.pdf'
            ..appliedCount = 1
            ..skippedCount = 0
            ..previewResume = _resume();

      final decoded = ChatSnapshotCodec.decodeBlock(
        ChatSnapshotCodec.encodeBlock(block),
      );

      expect(decoded, isA<ProposedEditsBlock>());
      final restored = decoded as ProposedEditsBlock;
      expect(restored.jobId, 'job-1');
      expect(restored.resumeId, 'resume-1');
      expect(restored.resolvedResumeId, 'resume-1');
      expect(restored.savedResumeId, 'resume-2');
      expect(
        restored.previewStoragePath,
        'users/u1/conversation_previews/conv-1/edits-1.pdf',
      );
      expect(restored.state, ProposedEditsState.applied);
      expect(restored.decisions.single, EditDecision.accepted);
      expect(restored.edits.single.targetPath, 'experience[0].bullets[0]');
      expect(restored.previewResume?.header.name, 'Alex Chen');
    });

    test('round-trips resume draft block state', () {
      final block =
          ResumeDraftBlock(
              id: 'draft-1',
              resume: _resume(),
              fileName: 'Alex_Chen_Resume.pdf',
              state: ResumeDraftState.ready,
            )
            ..savedResumeId = 'resume-3'
            ..previewStoragePath =
                'users/u1/conversation_previews/conv-1/draft-1.pdf';

      final decoded = ChatSnapshotCodec.decodeBlock(
        ChatSnapshotCodec.encodeBlock(block),
      );

      expect(decoded, isA<ResumeDraftBlock>());
      final restored = decoded as ResumeDraftBlock;
      expect(restored.fileName, 'Alex_Chen_Resume.pdf');
      expect(restored.state, ResumeDraftState.ready);
      expect(restored.savedResumeId, 'resume-3');
      expect(
        restored.previewStoragePath,
        'users/u1/conversation_previews/conv-1/draft-1.pdf',
      );
      expect(restored.resume.header.name, 'Alex Chen');
    });

    test('round-trips input requests, action proposals, and email drafts', () {
      final input =
          ChatSnapshotCodec.decodeBlock(
                ChatSnapshotCodec.encodeBlock(
                  InputRequestBlock(
                    id: 'input-1',
                    question: 'Which location do you prefer?',
                    suggestions: const ['Remote', 'Taipei'],
                    continuationPrompt: 'Continue with the selected location.',
                    state: InputRequestState.pending,
                  ),
                ),
              )
              as InputRequestBlock;

      expect(input.question, 'Which location do you prefer?');
      expect(input.suggestions, ['Remote', 'Taipei']);
      expect(input.state, InputRequestState.pending);

      final action =
          ChatSnapshotCodec.decodeBlock(
                ChatSnapshotCodec.encodeBlock(
                  ActionProposalBlock(
                    id: 'action-1',
                    icon: Icons.send_rounded,
                    title: 'Save draft',
                    description: 'Save this outreach email to Gmail Drafts.',
                    state: ActionState.pending,
                  ),
                ),
              )
              as ActionProposalBlock;

      expect(action.title, 'Save draft');
      expect(action.state, ActionState.pending);

      final email =
          ChatSnapshotCodec.decodeBlock(
                ChatSnapshotCodec.encodeBlock(
                  EmailDraftBlock(
                    id: 'email-1',
                    recipient: 'recruiter@example.com',
                    subject: 'Frontend Engineer application',
                    body: 'Hello, I am interested.',
                    jobId: 'job-1',
                    attachmentResumeId: 'resume-2',
                    attachmentFilename: 'Alex_Chen_Tailored.pdf',
                  ),
                ),
              )
              as EmailDraftBlock;

      expect(email.recipient, 'recruiter@example.com');
      expect(email.jobId, 'job-1');
      expect(email.attachmentResumeId, 'resume-2');
      expect(email.status, EmailDraftStatus.reviewing);
    });

    test('ignores malformed snapshots and downgrades running state safely', () {
      expect(ChatSnapshotCodec.decodeItem('bad'), isNull);
      expect(
        ChatSnapshotCodec.decodeBlock({'kind': 'unknown', 'id': 'b'}),
        isNull,
      );
      expect(
        ChatSnapshotCodec.decodeBlock({'kind': 'text', 'id': 'b'}),
        isNull,
      );

      final decoded = ChatSnapshotCodec.decodeBlock({
        'kind': 'tool_call',
        'id': 'tool-1',
        'name': 'search_jobs',
        'label': 'Searching',
        'status': 'running',
      });

      expect(decoded, isA<ToolCallBlock>());
      final tool = decoded as ToolCallBlock;
      expect(tool.status, ToolCallStatus.failed);
      expect(tool.resultSummary, 'Interrupted before completion.');
    });
  });
}

Job _job() => const Job(
  id: 'job-1',
  title: 'Frontend Engineer',
  company: 'Swiftlane',
  location: 'Remote',
  salary: r'$120k',
  category: JobCategory.ready,
  matchScore: 94,
  agentAction: 'Tailor resume',
  agentJustification: 'Strong React and TypeScript overlap.',
  skills: ['React', 'TypeScript'],
  missingSkills: [],
  why: 'Build dashboard experiences.',
);

ProposedEdit _edit() => const ProposedEdit(
  targetPath: 'experience[0].bullets[0]',
  originalText: 'Built dashboard UI.',
  proposedText: 'Built React dashboard UI for admin workflows.',
  reason: 'Highlights the dashboard ownership signal.',
);

ResumeJson _resume() => const ResumeJson(
  header: ResumeHeader(name: 'Alex Chen', email: 'alex@example.com'),
  summary: 'Product-minded frontend engineer.',
  experience: [
    ResumeExperience(
      company: 'Orbit',
      role: 'Frontend Engineer',
      start: '2024',
      bullets: ['Built dashboard UI.'],
    ),
  ],
  skillGroups: [
    ResumeSkillGroup(category: 'Frontend', items: ['React', 'TypeScript']),
  ],
);

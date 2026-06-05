import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/features/agent_chat/models/agent_block.dart';
import 'package:syncra/features/agent_chat/models/chat_message.dart';
import 'package:syncra/features/agent_chat/services/anthropic_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:syncra/features/resumes/models/proposed_edit.dart';

void main() {
  group('buildRestoredConversationContextForAgent', () {
    test(
      'summarizes user messages, attachments, jobs, edits, and email drafts',
      () {
        final context = buildRestoredConversationContextForAgent([
          UserMessage(
            id: 'user-1',
            text: 'Find jobs that fit my resume',
            attachments: const [
              ChatAttachment(id: 'resume-1', name: 'Alex Resume.pdf'),
            ],
          ),
          AgentTurn(
            id: 'turn-1',
            status: AgentTurnStatus.done,
            blocks: [
              ToolCallBlock(
                id: 'tool-1',
                name: 'search_jobs',
                label: 'Searching jobs',
                icon: Icons.travel_explore_rounded,
                status: ToolCallStatus.done,
                resultSummary: 'Found 2 roles',
              ),
              JobsBlock(id: 'jobs-1', jobs: [_job()]),
              ProposedEditsBlock.applied(
                id: 'edits-1',
                edits: [_edit()],
                jobId: 'job-1',
                resumeId: 'resume-1',
              )..savedResumeId = 'resume-2',
              EmailDraftBlock(
                id: 'email-1',
                recipient: 'recruiter@example.com',
                subject: 'Frontend Engineer application',
                body: 'Hello, I am interested.',
                jobId: 'job-1',
                status: EmailDraftStatus.saved,
                savedDraftId: 'gmail-draft-1',
                attachmentResumeId: 'resume-2',
              ),
            ],
          ),
        ], threadJob: _job());

        expect(context, contains('Previous Syncra conversation context'));
        expect(context, contains('Active job thread'));
        expect(context, contains('User asked: Find jobs that fit my resume'));
        expect(context, contains('Alex Resume.pdf'));
        expect(context, contains('Syncra ran tool search_jobs'));
        expect(context, contains('Syncra showed 1 job card'));
        expect(context, contains('Frontend Engineer at Swiftlane'));
        expect(context, contains('proposed-edits card'));
        expect(context, contains('Saved tailored resume id: resume-2'));
        expect(context, contains('drafted an email'));
        expect(context, contains('gmail-draft-1'));
      },
    );

    test('does not include restored thinking blocks as model context', () {
      final context = buildRestoredConversationContextForAgent([
        AgentTurn(
          id: 'turn-1',
          status: AgentTurnStatus.done,
          blocks: [
            ThinkingBlock(id: 'think-1', content: 'hidden reasoning'),
            TextBlock(id: 'text-1', text: 'Visible answer'),
          ],
        ),
      ]);

      expect(context, contains('Visible answer'));
      expect(context, isNot(contains('hidden reasoning')));
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
  reason: 'Highlights dashboard ownership.',
);

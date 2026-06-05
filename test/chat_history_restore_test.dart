import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/features/agent_chat/models/agent_block.dart';
import 'package:syncra/features/agent_chat/models/chat_message.dart';
import 'package:syncra/features/agent_chat/models/conversation_summary.dart';
import 'package:syncra/features/agent_chat/services/chat_history_repository.dart';

void main() {
  group('SavedConversation restore', () {
    test('restores transcript text and saved resume attachments', () {
      final saved = SavedConversation.fromMap({
        'items': [
          {
            'kind': 'user',
            'id': 'user-1',
            'text': 'Tailor this resume',
            'attachments': [
              {'id': 'resume-1', 'name': 'Daryn Resume.pdf'},
            ],
          },
          {'kind': 'agent', 'id': 'turn-1', 'text': 'I can help with that.'},
        ],
      });

      expect(saved.threadJob, isNull);
      expect(saved.items, hasLength(2));

      final user = saved.items.first as UserMessage;
      expect(user.text, 'Tailor this resume');
      expect(user.attachments.single.id, 'resume-1');
      expect(user.attachments.single.name, 'Daryn Resume.pdf');

      final agent = saved.items.last as AgentTurn;
      expect(agent.status, AgentTurnStatus.done);
      expect((agent.blocks.single as TextBlock).text, 'I can help with that.');
    });

    test('restores saved thread job metadata', () {
      final job = Job(
        id: 'job-1',
        title: 'Product Designer',
        company: 'Syncra',
        location: 'Remote',
        salary: r'$120k',
        category: JobCategory.inputNeeded,
        matchScore: 72,
        agentAction: 'Ask for portfolio context',
        agentJustification: 'Portfolio details are missing.',
        skills: const ['Figma', 'Systems thinking'],
        missingSkills: const ['Portfolio'],
        why: 'Strong design systems overlap.',
      );

      final saved = SavedConversation.fromMap({
        'items': [
          {'kind': 'user', 'id': 'user-1', 'text': 'Continue this role'},
        ],
        'threadJob': job.toJson(),
      });

      expect(saved.threadJob, isNotNull);
      expect(saved.threadJob!.id, 'job-1');
      expect(saved.threadJob!.category, JobCategory.inputNeeded);
      expect(saved.threadJob!.missingSkills, ['Portfolio']);
    });

    test('opens old or malformed conversation metadata safely', () {
      final oldConversation = SavedConversation.fromMap({
        'items': [
          {'kind': 'user', 'id': 'user-1', 'text': 'Old chat'},
        ],
      });
      final malformedThreadJob = SavedConversation.fromMap({
        'items': [
          {'kind': 'user', 'id': 'user-2', 'text': 'Still opens'},
        ],
        'threadJob': {'id': 'incomplete'},
      });

      expect(oldConversation.threadJob, isNull);
      expect(oldConversation.items.single, isA<UserMessage>());
      expect(malformedThreadJob.threadJob, isNull);
      expect(malformedThreadJob.items.single, isA<UserMessage>());
    });

    test('ignores unknown and malformed item shapes safely', () {
      final saved = SavedConversation.fromMap({
        'items': [
          'not a map',
          {'kind': 'system', 'id': 'sys-1', 'text': 'Ignore me'},
          {'kind': 'user', 'id': 42, 'text': 'Bad id'},
          {'kind': 'user', 'id': 'user-bad', 'text': 42},
          {
            'kind': 'user',
            'id': 'user-good',
            'text': 'Use this resume',
            'attachments': [
              'bad attachment',
              {'id': 'resume-missing-name'},
              {'id': 9, 'name': 'Bad id.pdf'},
              {'id': 'resume-good', 'name': 'Good.pdf'},
            ],
          },
          {'kind': 'agent', 'id': 'agent-bad', 'text': 42},
          {
            'kind': 'agent',
            'id': 'agent-good',
            'blocks': [
              {'kind': 'tool', 'text': 'Skip tool text'},
              {'kind': 'text', 'text': 'Recovered text block'},
              {'type': 'TextBlock', 'text': 'Recovered legacy text block'},
              {'kind': 'text', 'text': 42},
            ],
          },
        ],
      });

      expect(saved.items, hasLength(2));

      final user = saved.items.first as UserMessage;
      expect(user.id, 'user-good');
      expect(user.attachments, hasLength(1));
      expect(user.attachments.single.id, 'resume-good');

      final agent = saved.items.last as AgentTurn;
      expect(
        (agent.blocks.single as TextBlock).text,
        'Recovered text block\n\nRecovered legacy text block',
      );
    });

    test('treats non-list items as an empty transcript', () {
      final saved = SavedConversation.fromMap({'items': 'not a list'});

      expect(saved.items, isEmpty);
      expect(saved.threadJob, isNull);
    });

    test('restores legacy thread job category spellings', () {
      final saved = SavedConversation.fromMap({
        'items': [
          {'kind': 'user', 'id': 'user-1', 'text': 'Continue this role'},
        ],
        'threadJob': {
          'id': 'job-legacy',
          'title': 'UX Researcher',
          'company': 'Syncra',
          'location': 'Remote',
          'salary': r'$110k',
          'category': 'input-needed',
          'match': 68,
          'agent_action': 'Ask about research samples',
          'agent_justification': 'Research samples are missing.',
          'skills': ['Interviewing'],
          'missing': ['Portfolio'],
          'why': 'Research overlap.',
        },
      });

      expect(saved.threadJob, isNotNull);
      expect(saved.threadJob!.category, JobCategory.inputNeeded);
    });
  });

  test('ConversationSummary treats missing pinned field as unpinned', () {
    final summary = ConversationSummary(
      id: 'conv-1',
      title: 'Legacy chat',
      updatedAt: DateTime(2026),
    );

    expect(summary.pinned, isFalse);
  });
}

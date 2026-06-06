import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/agent_chat/models/agent_block.dart';
import 'package:syncra/features/agent_chat/models/chat_message.dart';
import 'package:syncra/features/agent_chat/presentation/widgets/agent_block_views.dart';
import 'package:syncra/features/agent_chat/state/agent_chat_notifier.dart';
import 'package:syncra/features/resumes/models/proposed_edit.dart';
import 'package:syncra/features/resumes/models/resume_integrity_result.dart';
import 'package:syncra/features/resumes/models/resume_json.dart';

ProposedEdit _edit(String id) => ProposedEdit(
  targetPath: 'experience.$id',
  originalText: 'old $id',
  proposedText: 'new $id',
  reason: 'because $id',
);

ResumeIntegrityResult _integrity(ResumeIntegrityStatus status) =>
    ResumeIntegrityResult(
      status: status,
      label: ResumeIntegrityResult.defaultLabel(status),
      summary: ResumeIntegrityResult.defaultSummary(status),
    );

const _previewResume = ResumeJson(
  header: ResumeHeader(name: 'Alex Chen'),
  summary: 'Product-minded engineer.',
);

/// Replaces [AgentChatNotifier.build] with a fixed transcript so tests skip the
/// real notifier's Firebase-backed hydration. The decision/apply methods under
/// test only touch `state.items`, so the uninitialised service fields are never
/// read.
class _SeededChatNotifier extends AgentChatNotifier {
  _SeededChatNotifier(this.seed);

  final ProposedEditsBlock seed;

  @override
  AgentChatState build() {
    const conversationId = 'test-conversation';

    return AgentChatState(
      conversationId: conversationId,
      items: [
        AgentTurn(id: 'turn-1', blocks: [seed], isStreaming: false),
      ],
    );
  }
}

ProposedEditsBlock _currentBlock(ProviderContainer c) => c
    .read(agentChatProvider)
    .items
    .whereType<AgentTurn>()
    .first
    .blocks
    .whereType<ProposedEditsBlock>()
    .first;

/// Pulls the live block out of the provider and renders the diff card, so a
/// notifier re-emit rebuilds the widget with the updated decisions.
class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentChatProvider);
    final block = state.items
        .whereType<AgentTurn>()
        .first
        .blocks
        .whereType<ProposedEditsBlock>()
        .first;
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: AgentBlockView(block: block)),
      ),
    );
  }
}

void main() {
  group('ProposedEdits notifier methods', () {
    ProviderContainer containerWith(ProposedEditsBlock seed) {
      final container = ProviderContainer(
        overrides: [
          agentChatProvider.overrideWith(() => _SeededChatNotifier(seed)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('setEditDecision records a per-edit choice', () {
      final seed = ProposedEditsBlock(id: 'b', edits: [_edit('a'), _edit('b')]);
      final c = containerWith(seed);

      c
          .read(agentChatProvider.notifier)
          .setEditDecision('b', 0, EditDecision.accepted);

      expect(_currentBlock(c).acceptedCount, 1);
      expect(_currentBlock(c).decisions[0], EditDecision.accepted);
    });

    test(
      'applyProposedEdits settles to applied when something is accepted',
      () {
        final seed = ProposedEditsBlock(
          id: 'b',
          edits: [_edit('a'), _edit('b')],
        );
        final c = containerWith(seed);
        final notifier = c.read(agentChatProvider.notifier);

        notifier.setEditDecision('b', 0, EditDecision.accepted);
        notifier.applyProposedEdits('b');

        expect(_currentBlock(c).state, ProposedEditsState.applied);
      },
    );

    test('applyProposedEdits is a no-op when nothing is accepted', () {
      final seed = ProposedEditsBlock(id: 'b', edits: [_edit('a')]);
      final c = containerWith(seed);

      c.read(agentChatProvider.notifier).applyProposedEdits('b');

      expect(_currentBlock(c).state, ProposedEditsState.reviewing);
    });

    test('blocked integrity prevents saving and surfaces an error', () async {
      final seed =
          ProposedEditsBlock(
              id: 'b',
              edits: [_edit('a')],
              decisions: [EditDecision.accepted],
              state: ProposedEditsState.applied,
            )
            ..previewBytes = Uint8List.fromList([1, 2, 3])
            ..previewResume = _previewResume
            ..integrity = _integrity(ResumeIntegrityStatus.blocked);
      final c = containerWith(seed);

      await c.read(agentChatProvider.notifier).savePreviewedResume('b');

      expect(_currentBlock(c).isSaved, isFalse);
      expect(
        _currentBlock(c).applyError,
        contains('Resume Integrity Check blocked saving'),
      );
    });

    test('settled cards ignore further decisions', () {
      final seed = ProposedEditsBlock(id: 'b', edits: [_edit('a')]);
      final c = containerWith(seed);
      final notifier = c.read(agentChatProvider.notifier);

      notifier.dismissProposedEdits('b');
      notifier.setEditDecision('b', 0, EditDecision.accepted);

      expect(_currentBlock(c).state, ProposedEditsState.dismissed);
      expect(_currentBlock(c).acceptedCount, 0);
    });
  });

  group('ProposedEdits diff card widget', () {
    testWidgets('shows accepted count and apply label from current decisions', (
      tester,
    ) async {
      final seed = ProposedEditsBlock(
        id: 'b',
        edits: [_edit('a'), _edit('b'), _edit('c')],
        decisions: [
          EditDecision.accepted,
          EditDecision.pending,
          EditDecision.pending,
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentChatProvider.overrideWith(() => _SeededChatNotifier(seed)),
          ],
          child: const _Harness(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1/3 accepted'), findsOneWidget);
      expect(find.text('Apply 1 edit'), findsOneWidget);
      expect(find.text('Apply edits'), findsNothing);
    });

    testWidgets(
      'Apply button reflects the accepted count and settles the card',
      (tester) async {
        final seed = ProposedEditsBlock(
          id: 'b',
          edits: [_edit('a'), _edit('b')],
          decisions: [EditDecision.accepted, EditDecision.pending],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              agentChatProvider.overrideWith(() => _SeededChatNotifier(seed)),
            ],
            child: const _Harness(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('1/2 accepted'), findsOneWidget);
        expect(find.text('Apply 1 edit'), findsOneWidget);

        await tester.tap(find.widgetWithText(InkWell, 'Apply 1 edit'));
        await tester.pumpAndSettle();

        expect(find.text('Preview ready'), findsOneWidget);
        expect(find.text('1 improvement woven in'), findsOneWidget);
        expect(find.text('See what changed'), findsOneWidget);
        expect(find.text('Dismiss all'), findsNothing);
      },
    );

    testWidgets('shows integrity badge when preview is ready', (tester) async {
      final seed =
          ProposedEditsBlock(
              id: 'b',
              edits: [_edit('a')],
              decisions: [EditDecision.accepted],
              state: ProposedEditsState.applied,
            )
            ..appliedCount = 1
            ..integrity = _integrity(ResumeIntegrityStatus.verified);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentChatProvider.overrideWith(() => _SeededChatNotifier(seed)),
          ],
          child: const _Harness(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Integrity verified — accepted edits landed and original facts were preserved.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Dismiss all settles to the dismissed outcome', (tester) async {
      final seed = ProposedEditsBlock(id: 'b', edits: [_edit('a')]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentChatProvider.overrideWith(() => _SeededChatNotifier(seed)),
          ],
          child: const _Harness(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(InkWell, 'Dismiss all'));
      await tester.pumpAndSettle();

      expect(find.text('Dismissed'), findsOneWidget);
      expect(find.text('Dismissed — no changes were made'), findsOneWidget);
    });
  });
}

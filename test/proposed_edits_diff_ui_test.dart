import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/agent_chat/models/agent_block.dart';
import 'package:syncra/features/agent_chat/models/chat_message.dart';
import 'package:syncra/features/agent_chat/presentation/widgets/agent_block_views.dart';
import 'package:syncra/features/agent_chat/state/agent_chat_notifier.dart';
import 'package:syncra/features/resumes/models/proposed_edit.dart';

ProposedEdit _edit(String id) => ProposedEdit(
      targetPath: 'experience.$id',
      originalText: 'old $id',
      proposedText: 'new $id',
      reason: 'because $id',
    );

/// Replaces [AgentChatNotifier.build] with a fixed transcript so tests skip the
/// real notifier's Firebase-backed hydration. The decision/apply methods under
/// test only touch `state.items`, so the uninitialised service fields are never
/// read.
class _SeededChatNotifier extends AgentChatNotifier {
  _SeededChatNotifier(this.seed);

  final ProposedEditsBlock seed;

  @override
  AgentChatState build() => AgentChatState(
        items: [
          AgentTurn(id: 'turn-1', blocks: [seed], isStreaming: false),
        ],
      );
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
        body: SingleChildScrollView(
          child: AgentBlockView(block: block),
        ),
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
      final seed =
          ProposedEditsBlock(id: 'b', edits: [_edit('a'), _edit('b')]);
      final c = containerWith(seed);

      c.read(agentChatProvider.notifier)
          .setEditDecision('b', 0, EditDecision.accepted);

      expect(_currentBlock(c).acceptedCount, 1);
      expect(_currentBlock(c).decisions[0], EditDecision.accepted);
    });

    test('applyProposedEdits settles to applied when something is accepted', () {
      final seed =
          ProposedEditsBlock(id: 'b', edits: [_edit('a'), _edit('b')]);
      final c = containerWith(seed);
      final notifier = c.read(agentChatProvider.notifier);

      notifier.setEditDecision('b', 0, EditDecision.accepted);
      notifier.applyProposedEdits('b');

      expect(_currentBlock(c).state, ProposedEditsState.applied);
    });

    test('applyProposedEdits is a no-op when nothing is accepted', () {
      final seed = ProposedEditsBlock(id: 'b', edits: [_edit('a')]);
      final c = containerWith(seed);

      c.read(agentChatProvider.notifier).applyProposedEdits('b');

      expect(_currentBlock(c).state, ProposedEditsState.reviewing);
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
    testWidgets('tapping Accept updates the status pill', (tester) async {
      final seed = ProposedEditsBlock(
        id: 'b',
        edits: [_edit('a'), _edit('b'), _edit('c')],
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

      expect(find.text('0/3 accepted'), findsOneWidget);

      await tester.tap(find.widgetWithText(InkWell, 'Accept').first);
      await tester.pumpAndSettle();

      expect(find.text('1/3 accepted'), findsOneWidget);
      expect(find.text('0/3 accepted'), findsNothing);
    });

    testWidgets('rejecting then accepting moves the count correctly',
        (tester) async {
      final seed = ProposedEditsBlock(
        id: 'b',
        edits: [_edit('a'), _edit('b')],
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

      await tester.tap(find.widgetWithText(InkWell, 'Reject').first);
      await tester.pumpAndSettle();
      expect(find.text('0/2 accepted'), findsOneWidget);

      await tester.tap(find.widgetWithText(InkWell, 'Accept').last);
      await tester.pumpAndSettle();
      expect(find.text('1/2 accepted'), findsOneWidget);
    });

    testWidgets('Apply button reflects the accepted count and settles the card',
        (tester) async {
      final seed = ProposedEditsBlock(
        id: 'b',
        edits: [_edit('a'), _edit('b')],
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

      // Nothing accepted yet: the generic, disabled label.
      expect(find.text('Apply edits'), findsOneWidget);

      await tester.tap(find.widgetWithText(InkWell, 'Accept').first);
      await tester.pumpAndSettle();
      expect(find.text('Apply 1 edit'), findsOneWidget);

      await tester.tap(find.widgetWithText(InkWell, 'Apply 1 edit'));
      await tester.pumpAndSettle();

      // Settled: footer collapses to the outcome line, controls gone.
      expect(find.text('Applied'), findsOneWidget); // status pill
      expect(find.text('Applied 1 edit to your resume'), findsOneWidget);
      expect(find.widgetWithText(InkWell, 'Accept'), findsNothing);
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

      expect(find.text('Dismissed'), findsOneWidget); // status pill
      expect(find.text('Dismissed — no changes were made'), findsOneWidget);
    });
  });
}

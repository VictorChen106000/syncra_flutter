import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/agent_chat/models/agent_block.dart';
import 'package:syncra/features/resumes/models/proposed_edit.dart';

ProposedEdit _edit(String id) => ProposedEdit(
      targetPath: 'experience.$id',
      originalText: 'old $id',
      proposedText: 'new $id',
      reason: 'because $id',
    );

void main() {
  group('ProposedEditsBlock decision state', () {
    test('defaults every edit to pending and the card to reviewing', () {
      final block = ProposedEditsBlock(
        id: 'b1',
        edits: [_edit('a'), _edit('b'), _edit('c')],
      );

      expect(block.decisions, hasLength(3));
      expect(block.decisions, everyElement(EditDecision.pending));
      expect(block.state, ProposedEditsState.reviewing);
      expect(block.acceptedCount, 0);
      expect(block.hasPending, isTrue);
      expect(block.acceptedEdits, isEmpty);
    });

    test('acceptedCount and acceptedEdits track accepted decisions in order',
        () {
      final edits = [_edit('a'), _edit('b'), _edit('c')];
      final block = ProposedEditsBlock(id: 'b2', edits: edits);

      block.decisions[0] = EditDecision.accepted;
      block.decisions[1] = EditDecision.rejected;
      block.decisions[2] = EditDecision.accepted;

      expect(block.acceptedCount, 2);
      // Index-aligned: accepted edits come back in their original order.
      expect(block.acceptedEdits, [edits[0], edits[2]]);
    });

    test('hasPending is false once every edit is decided', () {
      final block = ProposedEditsBlock(id: 'b3', edits: [_edit('a'), _edit('b')]);

      block.decisions[0] = EditDecision.accepted;
      block.decisions[1] = EditDecision.rejected;

      expect(block.hasPending, isFalse);
    });

    test('honours explicitly supplied decisions and state', () {
      final block = ProposedEditsBlock(
        id: 'b4',
        edits: [_edit('a'), _edit('b')],
        decisions: [EditDecision.accepted, EditDecision.pending],
        state: ProposedEditsState.applied,
      );

      expect(block.acceptedCount, 1);
      expect(block.state, ProposedEditsState.applied);
      expect(block.hasPending, isTrue);
    });

    test('handles an empty edit list', () {
      final block = ProposedEditsBlock(id: 'b5', edits: const []);

      expect(block.decisions, isEmpty);
      expect(block.acceptedCount, 0);
      expect(block.hasPending, isFalse);
      expect(block.acceptedEdits, isEmpty);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/agent_chat/tools/anthropic_tool_calls.dart';

/// Regression guard for the "Could not parse email draft JSON" failure: the
/// draft_email / tailor / onboarding parsers all route model replies through
/// [AnthropicParaphraseService.decodeModelJsonObject], which must tolerate the
/// two ways these replies break strict jsonDecode — surrounding prose / fences,
/// and (the real-world cause) raw newlines inside a multi-line string value.
void main() {
  group('decodeModelJsonObject', () {
    test('decodes clean single-line JSON', () {
      final out = AnthropicParaphraseService.decodeModelJsonObject(
        '{"subject": "Frontend role at Acme", "body": "Hi team, I am keen."}',
      );
      expect(out['subject'], 'Frontend role at Acme');
      expect(out['body'], 'Hi team, I am keen.');
    });

    test('recovers a body with literal newlines (the reported failure)', () {
      // What the model actually emits: a multi-line email body with raw line
      // breaks inside the JSON string — invalid JSON that jsonDecode rejects.
      const reply =
          '{"subject": "Software role at SkillStorm", "body": "Hi team,\n\n'
          'I am a recent grad excited about the entry-level role.\n\n'
          'Best,\nDaryn"}';

      final out = AnthropicParaphraseService.decodeModelJsonObject(reply);
      expect(out['subject'], 'Software role at SkillStorm');
      expect(out['body'], contains('recent grad'));
      expect(out['body'], contains('Best,\nDaryn'));
    });

    test('strips markdown fences and surrounding prose', () {
      const reply =
          'Sure! Here is the draft:\n'
          '```json\n'
          '{"subject": "Hello", "body": "Line one.\nLine two."}\n'
          '```';

      final out = AnthropicParaphraseService.decodeModelJsonObject(reply);
      expect(out['subject'], 'Hello');
      expect(out['body'], 'Line one.\nLine two.');
    });

    test('keeps already-escaped sequences intact', () {
      final out = AnthropicParaphraseService.decodeModelJsonObject(
        r'{"subject": "Re: role", "body": "Quote: \"hi\"\nNext line."}',
      );
      expect(out['body'], 'Quote: "hi"\nNext line.');
    });

    test('throws when there is no object at all', () {
      expect(
        () => AnthropicParaphraseService.decodeModelJsonObject('no json here'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

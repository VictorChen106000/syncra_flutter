import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/services/anthropic_client.dart';
import 'package:syncra/features/resumes/services/resume_parser_service.dart';

void main() {
  group('ResumeParserService', () {
    test(
      'throws a scanned-PDF parse exception for empty resume text',
      () async {
        final client = _FakeAnthropicClient([_validResumeJson]);
        final service = ResumeParserService(client: client);

        await expectLater(
          service.parse('   \n\t  '),
          throwsA(
            isA<ResumeParseException>().having(
              (error) => error.message,
              'message',
              contains('scanned image'),
            ),
          ),
        );

        expect(client.requests, isEmpty);
      },
    );
    test(
      'retries once when the first resume JSON response is malformed',
      () async {
        final client = _FakeAnthropicClient(['not json', _validResumeJson]);
        final service = ResumeParserService(client: client);

        final parsed = await service.parse('Jane Doe\nFlutter developer');
        final resume = parsed!;

        expect(resume.header.name, 'Jane Doe');
        expect(resume.skills, contains('Flutter'));
        expect(client.requests, hasLength(2));

        final retryMessage =
            (client.requests.last['messages'] as List).first as Map;
        expect(
          retryMessage['content'],
          contains('Your previous response was not valid ResumeJSON'),
        );
      },
    );

    test(
      'throws a parse exception when retry response is still malformed',
      () async {
        final client = _FakeAnthropicClient(['not json', '{"header":']);
        final service = ResumeParserService(client: client);

        await expectLater(
          service.parse('Jane Doe\nFlutter developer'),
          throwsA(isA<ResumeParseException>()),
        );

        expect(client.requests, hasLength(2));
      },
    );
  });
}

class _FakeAnthropicClient extends AnthropicClient {
  _FakeAnthropicClient(this._responses) : super(apiKey: 'test-key');

  final List<String> _responses;
  final List<Map<String, dynamic>> requests = [];

  @override
  bool get hasApiKey => true;

  @override
  Future<Map<String, dynamic>> createMessage(
    Map<String, dynamic> payload,
  ) async {
    requests.add(payload);
    final index = requests.length - 1;
    if (index >= _responses.length) {
      throw StateError('No fake Anthropic response for request $index.');
    }

    return {
      'content': [
        {'type': 'text', 'text': _responses[index]},
      ],
    };
  }
}

const _validResumeJson = '''
{
  "header": {
    "name": "Jane Doe"
  },
  "experience": [],
  "education": [],
  "projects": [],
  "certifications": [],
  "skill_groups": [
    {
      "category": "Skills",
      "items": ["Flutter"]
    }
  ]
}
''';

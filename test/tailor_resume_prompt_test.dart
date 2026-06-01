import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/agent_chat/tools/anthropic_tool_calls.dart';
import 'package:syncra/features/resumes/models/proposed_edit.dart';
import 'package:syncra/features/resumes/models/resume_json.dart';
import 'package:syncra/features/resumes/services/resume_diff_service.dart';
import 'package:syncra/features/agent_chat/services/anthropic_chat_service.dart';

/// Regression guard for the `tailor_resume` contract: the prompt must keep
/// instructing Claude to (a) propose targeted edits rather than full-section
/// rewrites, (b) copy `original_text` verbatim, and (c) never invent
/// experience. If someone loosens the prompt, these break loudly.
void main() {
  group('tailor_resume system prompt', () {
    final prompt = AnthropicParaphraseService.tailorSystemPrompt.toLowerCase();

    test('forbids whole-resume / full-section rewrites', () {
      expect(prompt, contains('not to rewrite the whole resume'));
      expect(
        prompt,
        contains('prefer individual bullet rewrites over full-section'),
      );
    });

    test('requires original_text copied verbatim', () {
      expect(prompt, contains('verbatim'));
      expect(prompt, contains('`original_text`'));
    });

    test('forbids inventing experience', () {
      expect(prompt, contains('never invent'));
      expect(prompt, contains('must not invent experience'));
    });

    test('caps the edit count so it stays a small PR-style diff', () {
      expect(prompt, contains('3 to 8 edits'));
    });
  });

  group('main agent system prompt', () {
  final prompt = AnthropicChatService.systemPrompt.toLowerCase();

  test('treats user messages as workflow goals', () {
    expect(prompt, contains('goal'));
    expect(prompt, contains('drive the workflow forward yourself'));
    expect(prompt, contains('proactively offer the next concrete step'));
    expect(prompt, contains('continue the workflow'));
  });

  test('pauses only at user gates', () {
    expect(prompt, contains('pause only'));
    expect(prompt, contains('user gate'));
    expect(prompt, contains('ask_user'));
  });

  test('drives the search → tailor → email sequence via ask_user offers', () {
    expect(prompt, contains('standard job-search sequence'));
    // After search, it must offer tailoring instead of stopping on a job list.
    expect(prompt, contains('never stop with just a result'));
    expect(prompt, contains('tailor your resume'));
    // After the tailored resume is saved, it must offer outreach.
    expect(prompt, contains('draft an outreach email'));
    expect(prompt, contains('only call `draft_email` after the user says yes'));
  });

  test('continues after saved tailored resume approval', () {
    expect(prompt, contains('approved and saved a tailored resume'));
    expect(prompt, contains('continue the original workflow'));
    expect(prompt, contains('without asking the user to repeat the task'));
  });

  test('keeps send_email behind explicit approval', () {
    expect(prompt, contains('never call `send_email`'));
    expect(prompt, contains('explicit user-confirmation token'));
    expect(prompt, contains('user tapped send'));
  });
});

  // The prompt asks for verbatim original_text; the diff engine is the
  // backstop that enforces it. A full-section rewrite whose original_text
  // does not match a real leaf must never land.
  group('tailor_resume diff backstop', () {
    const service = ResumeDiffService();
    const resume = ResumeJson(
      header: ResumeHeader(name: 'Grace Hopper'),
      summary: 'Built compilers.',
      experience: [
        ResumeExperience(
          company: 'Navy',
          role: 'Engineer',
          start: '1944',
          bullets: ['Wrote the first compiler.', 'Coined "debugging".'],
        ),
      ],
      skills: ['COBOL'],
    );

    test('rejects a full-section rewrite passed as one non-verbatim edit', () {
      // Claude tries to swap an entire bullet list as a single blob — the
      // original_text matches no individual leaf, so nothing is applied.
      final outcome = service.apply(resume, [
        const ProposedEdit(
          targetPath: 'experience[0].bullets[0]',
          originalText: 'Wrote the first compiler. Coined "debugging".',
          proposedText: 'Rewrote the entire career history.',
          reason: 'full-section rewrite attempt',
        ),
      ]);
      expect(outcome.applied, isEmpty);
      expect(outcome.skipped, hasLength(1));
      expect(outcome.resume.experience[0].bullets[0],
          'Wrote the first compiler.');
    });

    test('accepts a single verbatim-anchored bullet edit', () {
      final outcome = service.apply(resume, [
        const ProposedEdit(
          targetPath: 'experience[0].bullets[0]',
          originalText: 'Wrote the first compiler.',
          proposedText: 'Designed and built the first compiler (A-0).',
          reason: 'targeted bullet rewrite',
        ),
      ]);
      expect(outcome.applied, hasLength(1));
      expect(outcome.resume.experience[0].bullets[0],
          'Designed and built the first compiler (A-0).');
    });
  });
}

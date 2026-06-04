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
    final prompt = AnthropicParaphraseService.tailorSystemPrompt
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');

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
    final prompt = AnthropicChatService.systemPrompt.toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

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

    test('learns reusable facts after ask_user answers', () {
      expect(prompt, contains('career memory'));
      expect(prompt, contains('after `ask_user` returns an answer'));
      expect(prompt, contains('stable career fact'));
      expect(
        prompt,
        contains('call `remember_fact` before continuing the workflow'),
      );
      expect(prompt, contains('skill'));
      expect(prompt, contains('missing_info'));
      expect(
        prompt,
        contains('do not call `remember_fact` for one-off task choices'),
      );
    });

    test('surfaces when career memory affects output', () {
      expect(prompt, contains('learned_facts'));
      expect(prompt, contains('used career memory'));
      expect(prompt, contains('if learned facts materially affect matching'));
      expect(prompt, contains('mention at most 1-2 relevant facts'));
    });

    test('checks job trust before outreach or application actions', () {
      expect(prompt, contains('job trust guard'));
      expect(prompt, contains('check_job_risk'));
      expect(prompt, contains('before `draft_email`'));
      expect(prompt, contains('save_to_pipeline'));
      expect(prompt, contains('save_to_tracker'));
      expect(prompt, contains('high risk'));
      expect(prompt, contains('never mark a job as safe'));
    });

    test('drives the search → tailor → email sequence via ask_user offers', () {
      expect(prompt, contains('standard job-search sequence'));
      // After search, it must offer tailoring instead of stopping on a job list.
      expect(prompt, contains('never stop with just a result'));
      expect(prompt, contains('tailor for the top role'));
      // After the tailored resume is saved, it must offer outreach.
      expect(prompt, contains('draft recruiter outreach'));
      expect(
        prompt,
        contains('only call `draft_email` after the user says yes'),
      );
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

    test('guards discovery-only job searches from overreach', () {
      expect(prompt, contains('progressive autonomy'));
      expect(prompt, contains('discovery-only requests'));
      expect(prompt, contains('do not silently expand'));
      expect(prompt, contains('do exactly the workflow the user requested'));
      expect(prompt, contains('do not call `read_resume`'));
      expect(prompt, contains('match_jobs'));
      expect(prompt, contains('save_to_pipeline'));
      expect(prompt, contains('tailor_resume'));
      expect(prompt, contains('draft_email'));
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
      expect(
        outcome.resume.experience[0].bullets[0],
        'Wrote the first compiler.',
      );
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
      expect(
        outcome.resume.experience[0].bullets[0],
        'Designed and built the first compiler (A-0).',
      );
    });
  });
}

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

    test('blocks unsupported claims and duplicate skill artifacts', () {
      expect(prompt, contains('do not add unsupported claims'));
      expect(prompt, contains('tools, skills, years of experience'));
      expect(prompt, contains('do not insert it as a skill or achievement'));
      expect(prompt, contains('skill edits must stay deduplicated'));
      expect(prompt, contains('do not add it again under another category'));
      expect(prompt, contains('bracketed or comma-joined repeated skill list'));
      expect(prompt, contains('duplicate copy of its items'));
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
      expect(prompt, contains('continue until you finish'));
    });

    test('delegates pacing to the active autonomy mode directive', () {
      // The static prompt must point at the per-turn autonomy directive
      // (Assist / Auto-draft / Autopilot) and let it own pacing entirely —
      // it must NOT hard-code a chaining/gate cadence of its own.
      expect(prompt, contains('active autonomy mode'));
      expect(prompt, contains('assist / auto-draft / autopilot'));
      expect(prompt, contains('behave as auto-draft'));
      expect(prompt, contains('set entirely by your active autonomy mode'));
      expect(prompt, contains('do not hard-code a pace'));
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

    test('blocks unsupported claims and duplicate skill artifacts', () {
      expect(prompt, contains('preserve supported resume facts only'));
      expect(prompt, contains('do not add unsupported employers'));
      expect(prompt, contains('tools, skills, metrics, years of experience'));
      expect(prompt, contains('keep skill changes deduplicated'));
      expect(prompt, contains('bracketed repeated skill list'));
      expect(prompt, contains('call `tailor_resume` again'));
      expect(prompt, contains('do not use `apply_resume_edits` for repairs'));
    });

    test('drives the search → tailor → email sequence, pacing by mode', () {
      expect(prompt, contains('standard job-search sequence'));
      expect(prompt, contains('tailor for the top role'));
      // Drafting outreach is the step after a saved resume...
      expect(prompt, contains('draft recruiter outreach'));
      // ...but whether to draft immediately or ask first is left to the mode.
      expect(prompt, contains('is set by your active autonomy mode'));
    });

    test('continues after saved tailored resume approval', () {
      expect(prompt, contains('approved and saved a tailored resume'));
      expect(prompt, contains('continue the original workflow'));
      expect(prompt, contains('without asking the user to repeat the task'));
    });

    test('keeps send_email behind explicit approval', () {
      expect(prompt, contains('never call `send_email`'));
      expect(prompt, contains('explicit confirmation token'));
      expect(prompt, contains('user tapped send'));
    });

    test('governs job-search scope by autonomy mode', () {
      expect(prompt, contains('progressive autonomy'));
      expect(
        prompt,
        contains('governed by your active autonomy mode, not by the wording'),
      );
      // Assist mode keeps a bare "find jobs" request discovery-only.
      expect(
        prompt,
        contains('in assist mode only, treat a bare discovery request'),
      );
      expect(prompt, contains('do not call `read_resume`'));
      // Auto-draft / Autopilot expand the same request into the full pipeline.
      expect(prompt, contains('the same request is a full apply goal'));
      expect(prompt, contains('match_jobs'));
      expect(prompt, contains('save_to_pipeline'));
      expect(prompt, contains('tailor_resume'));
      expect(prompt, contains('draft_email'));
    });

    test('tailors partial matches without a forced question', () {
      expect(prompt, contains('several match'));
      expect(
        prompt,
        contains('do not stop to ask whether they have the missing skill'),
      );
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

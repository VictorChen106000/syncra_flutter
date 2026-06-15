import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/resumes/models/proposed_edit.dart';
import 'package:syncra/features/resumes/models/resume_json.dart';
import 'package:syncra/features/resumes/services/resume_diff_service.dart';

ResumeJson _sampleResume() => const ResumeJson(
  header: ResumeHeader(name: 'Ada Lovelace'),
  summary: 'Engineer who ships.',
  experience: [
    ResumeExperience(
      company: 'Analytical Co',
      role: 'Engineer',
      start: '2023',
      bullets: ['Built the first algorithm.', 'Wrote extensive notes.'],
    ),
  ],
  skills: ['Math', 'Logic', 'Writing'],
  projects: [
    ResumeProject(name: 'Engine', bullets: ['Designed the analytical engine.']),
  ],
);

ProposedEdit _edit({
  required String path,
  required String original,
  required String proposed,
}) => ProposedEdit(
  targetPath: path,
  originalText: original,
  proposedText: proposed,
  reason: 'because it helps',
);

void main() {
  const service = ResumeDiffService();

  group('ResumeDiffService — target_path grammar', () {
    test('top-level summary', () {
      final result = service.applyEdits(_sampleResume(), [
        _edit(
          path: 'summary',
          original: 'Engineer who ships.',
          proposed: 'Engineer who ships AI products.',
        ),
      ]);
      expect(result.summary, 'Engineer who ships AI products.');
    });

    test('experience[i].bullets[j]', () {
      final result = service.applyEdits(_sampleResume(), [
        _edit(
          path: 'experience[0].bullets[1]',
          original: 'Wrote extensive notes.',
          proposed: 'Authored the first published program.',
        ),
      ]);
      expect(
        result.experience[0].bullets[1],
        'Authored the first published program.',
      );
      // Sibling bullet untouched.
      expect(result.experience[0].bullets[0], 'Built the first algorithm.');
    });

    test('skills[i]', () {
      final result = service.applyEdits(_sampleResume(), [
        _edit(
          path: 'skills[2]',
          original: 'Writing',
          proposed: 'Technical Writing',
        ),
      ]);
      expect(result.skills, ['Math', 'Logic', 'Technical Writing']);
    });

    test('projects[i].bullets[j]', () {
      final result = service.applyEdits(_sampleResume(), [
        _edit(
          path: 'projects[0].bullets[0]',
          original: 'Designed the analytical engine.',
          proposed: 'Designed the first general-purpose computer.',
        ),
      ]);
      expect(
        result.projects[0].bullets[0],
        'Designed the first general-purpose computer.',
      );
    });

    test('strips a leading profile. prefix', () {
      final result = service.applyEdits(_sampleResume(), [
        _edit(
          path: 'profile.summary',
          original: 'Engineer who ships.',
          proposed: 'Pioneering engineer.',
        ),
      ]);
      expect(result.summary, 'Pioneering engineer.');
    });
  });

  group('ResumeDiffService — safety', () {
    test('purity: original is never mutated', () {
      final original = _sampleResume();
      service.applyEdits(original, [
        _edit(path: 'skills[0]', original: 'Math', proposed: 'Mathematics'),
      ]);
      expect(original.skills[0], 'Math');
    });

    test('skips when original_text does not match verbatim', () {
      final outcome = service.apply(_sampleResume(), [
        _edit(
          path: 'summary',
          original: 'A stale value that no longer matches.',
          proposed: 'Should not be applied.',
        ),
      ]);
      expect(outcome.applied, isEmpty);
      expect(outcome.skipped, hasLength(1));
      expect(outcome.resume.summary, 'Engineer who ships.');
    });

    test('skips an out-of-range index', () {
      final outcome = service.apply(_sampleResume(), [
        _edit(path: 'skills[9]', original: 'Math', proposed: 'Nope'),
      ]);
      expect(outcome.applied, isEmpty);
      expect(outcome.resume.skills, ['Math', 'Logic', 'Writing']);
    });

    test('skips an unresolvable path', () {
      final outcome = service.apply(_sampleResume(), [
        _edit(path: 'nonsense[0].field', original: 'x', proposed: 'y'),
      ]);
      expect(outcome.applied, isEmpty);
    });

    test('whitespace-only differences still match (trimmed compare)', () {
      final result = service.applyEdits(_sampleResume(), [
        _edit(path: 'skills[0]', original: '  Math  ', proposed: 'Mathematics'),
      ]);
      expect(result.skills[0], 'Mathematics');
    });

    test('matches across smart quotes and collapsed whitespace', () {
      const resume = ResumeJson(
        header: ResumeHeader(name: 'Ada Lovelace'),
        summary: "Built the world's   first algorithm - by hand.",
      );
      // LLM-copied original: straight apostrophe, single spaces, em-dash.
      final result = service.applyEdits(resume, [
        _edit(
          path: 'summary',
          original: "Built the world's first algorithm — by hand.",
          proposed: 'Pioneered the first published algorithm.',
        ),
      ]);
      expect(result.summary, 'Pioneered the first published algorithm.');
    });

    test('applies the matching subset and reports the split', () {
      final outcome = service.apply(_sampleResume(), [
        _edit(path: 'skills[0]', original: 'Math', proposed: 'Mathematics'),
        _edit(path: 'skills[1]', original: 'WRONG', proposed: 'Nope'),
      ]);
      expect(outcome.applied, hasLength(1));
      expect(outcome.skipped, hasLength(1));
      expect(outcome.resume.skills, ['Mathematics', 'Logic', 'Writing']);
    });
  });

  group('ResumeDiffService — add op (insertions)', () {
    ProposedEdit add({required String path, required String proposed}) =>
        ProposedEdit(
          targetPath: path,
          originalText: '',
          proposedText: proposed,
          reason: 'the user confirmed this',
          op: ProposedEditOp.add,
        );

    test('appends a new skill to the skills list', () {
      final result = service.applyEdits(_sampleResume(), [
        add(path: 'skills', proposed: 'Python'),
      ]);
      expect(result.skills, ['Math', 'Logic', 'Writing', 'Python']);
    });

    test('appends a new bullet to an experience entry', () {
      final result = service.applyEdits(_sampleResume(), [
        add(path: 'experience[0].bullets', proposed: 'Shipped to production.'),
      ]);
      expect(result.experience[0].bullets, [
        'Built the first algorithm.',
        'Wrote extensive notes.',
        'Shipped to production.',
      ]);
    });

    test('reports the add as applied', () {
      final outcome = service.apply(_sampleResume(), [
        add(path: 'skills', proposed: 'Rust'),
      ]);
      expect(outcome.applied, hasLength(1));
      expect(outcome.skipped, isEmpty);
    });

    test('does not clobber a non-empty scalar', () {
      final outcome = service.apply(_sampleResume(), [
        add(path: 'summary', proposed: 'Should not overwrite.'),
      ]);
      expect(outcome.applied, isEmpty);
      expect(outcome.skipped, hasLength(1));
      expect(outcome.resume.summary, 'Engineer who ships.');
    });

    test('sets a summary the resume never had', () {
      const blank = ResumeJson(header: ResumeHeader(name: 'Ada Lovelace'));
      final outcome = service.apply(blank, [
        add(path: 'profile.summary', proposed: 'Engineer who ships AI.'),
      ]);
      expect(outcome.applied, hasLength(1));
      expect(outcome.resume.summary, 'Engineer who ships AI.');
    });

    test('fills an empty header field', () {
      const blank = ResumeJson(header: ResumeHeader(name: 'Ada Lovelace'));
      final outcome = service.apply(blank, [
        add(path: 'header.email', proposed: 'ada@analytical.co'),
      ]);
      expect(outcome.applied, hasLength(1));
      expect(outcome.resume.header.email, 'ada@analytical.co');
    });

    test('rejects an add onto an object list (no phantom apply)', () {
      final outcome = service.apply(_sampleResume(), [
        add(path: 'experience', proposed: 'A loose string, not an entry.'),
      ]);
      expect(outcome.applied, isEmpty);
      expect(outcome.skipped, hasLength(1));
      expect(outcome.resume.experience, hasLength(1));
    });

    test('skips an unresolvable list path', () {
      final outcome = service.apply(_sampleResume(), [
        add(path: 'experience[9].bullets', proposed: 'No such role.'),
      ]);
      expect(outcome.applied, isEmpty);
    });

    test('skips a duplicate skill (case-insensitive)', () {
      final outcome = service.apply(_sampleResume(), [
        add(path: 'skills', proposed: '  math  '),
      ]);
      expect(outcome.applied, isEmpty);
      expect(outcome.skipped, hasLength(1));
      expect(outcome.resume.skills, ['Math', 'Logic', 'Writing']);
    });

    test('an add edit is valid without original_text', () {
      const edit = ProposedEdit(
        targetPath: 'skills',
        originalText: '',
        proposedText: 'Go',
        reason: 'user confirmed',
        op: ProposedEditOp.add,
      );
      expect(edit.isValid, isTrue);
    });

    test('op round-trips through fromJson / toJson', () {
      final parsed = ProposedEdit.fromJson(const {
        'target_path': 'skills',
        'proposed_text': 'Kotlin',
        'reason': 'user confirmed',
        'op': 'add',
      });
      expect(parsed.op, ProposedEditOp.add);
      expect(parsed.isAdd, isTrue);
      expect(parsed.toJson()['op'], 'add');

      // Absent op defaults to replace.
      final fallback = ProposedEdit.fromJson(const {
        'target_path': 'summary',
        'original_text': 'x',
        'proposed_text': 'y',
        'reason': 'r',
      });
      expect(fallback.op, ProposedEditOp.replace);
    });
  });
}

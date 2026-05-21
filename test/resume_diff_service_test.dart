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
          bullets: [
            'Built the first algorithm.',
            'Wrote extensive notes.',
          ],
        ),
      ],
      skills: ['Math', 'Logic', 'Writing'],
      projects: [
        ResumeProject(
          name: 'Engine',
          bullets: ['Designed the analytical engine.'],
        ),
      ],
    );

ProposedEdit _edit({
  required String path,
  required String original,
  required String proposed,
}) =>
    ProposedEdit(
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
        _edit(path: 'skills[2]', original: 'Writing', proposed: 'Technical Writing'),
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
        _edit(
          path: 'skills[0]',
          original: '  Math  ',
          proposed: 'Mathematics',
        ),
      ]);
      expect(result.skills[0], 'Mathematics');
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
}

import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/resumes/models/proposed_edit.dart';
import 'package:syncra/features/resumes/models/resume_integrity_result.dart';
import 'package:syncra/features/resumes/models/resume_json.dart';
import 'package:syncra/features/resumes/services/resume_integrity_service.dart';

void main() {
  const service = ResumeIntegrityService();

  group('ResumeIntegrityService', () {
    test('verified when accepted edit lands cleanly', () {
      final edit = _edit(
        original: 'Built dashboard UI.',
        proposed: 'Built Flutter dashboard UI.',
      );

      final result = service.verify(
        original: _resume(),
        tailored: _resume(bullet: 'Built Flutter dashboard UI.'),
        acceptedEdits: [edit],
        appliedCount: 1,
        skippedCount: 0,
      );

      expect(result.status, ResumeIntegrityStatus.verified);
      expect(result.canSave, isTrue);
    });

    test('needsReview when an accepted edit was skipped', () {
      final result = service.verify(
        original: _resume(),
        tailored: _resume(bullet: 'Built Flutter dashboard UI.'),
        acceptedEdits: [
          _edit(
            original: 'Built dashboard UI.',
            proposed: 'Built Flutter dashboard UI.',
          ),
        ],
        appliedCount: 1,
        skippedCount: 1,
      );

      expect(result.status, ResumeIntegrityStatus.needsReview);
      expect(result.canSave, isTrue);
    });

    test('blocked when accepted edits are non-empty but none land', () {
      final result = service.verify(
        original: _resume(),
        tailored: _resume(),
        acceptedEdits: [
          _edit(original: 'Missing original.', proposed: 'Should not land.'),
        ],
        appliedCount: 0,
        skippedCount: 1,
      );

      expect(result.status, ResumeIntegrityStatus.blocked);
      expect(result.isBlocked, isTrue);
    });

    test('blocked when protected identity or contact facts change', () {
      final result = service.verify(
        original: _resume(),
        tailored: _resume(
          name: 'Jordan Smith',
          email: 'jordan@example.com',
          phone: '555-999-1212',
        ),
        acceptedEdits: const [],
        appliedCount: 0,
        skippedCount: 0,
      );

      expect(result.status, ResumeIntegrityStatus.blocked);
      expect(
        result.signals.map((signal) => signal.label),
        containsAll([
          'candidate name changed',
          'email changed',
          'phone changed',
        ]),
      );
    });

    test('needsReview when a new unsupported numeric metric appears', () {
      final result = service.verify(
        original: _resume(),
        tailored: _resume(
          bullet: 'Built dashboard UI and improved speed by 40%.',
        ),
        acceptedEdits: const [],
        appliedCount: 0,
        skippedCount: 0,
      );

      expect(result.status, ResumeIntegrityStatus.needsReview);
      expect(result.signals.single.label, 'Unsupported numeric claim');
    });

    test('blocked when a new structured employer appears unsupported', () {
      final result = service.verify(
        original: _resume(),
        tailored: _resume(company: 'Northstar Labs'),
        acceptedEdits: const [],
        appliedCount: 0,
        skippedCount: 0,
      );

      expect(result.status, ResumeIntegrityStatus.blocked);
      expect(
        result.signals.map((signal) => signal.label),
        contains('Unsupported company'),
      );
    });

    test(
      'verified when a new phrase is supported by accepted proposed text',
      () {
        final edit = _edit(
          path: 'summary',
          original: 'Product-minded engineer.',
          proposed: 'Product-minded Flutter engineer.',
        );

        final result = service.verify(
          original: _resume(summary: 'Product-minded engineer.'),
          tailored: _resume(summary: 'Product-minded Flutter engineer.'),
          acceptedEdits: [edit],
          appliedCount: 1,
          skippedCount: 0,
        );

        expect(result.status, ResumeIntegrityStatus.verified);
      },
    );

    test('missing optional fields do not crash', () {
      expect(
        () => service.verify(
          original: const ResumeJson(header: ResumeHeader(name: 'Alex Chen')),
          tailored: const ResumeJson(
            header: ResumeHeader(name: 'Alex Chen'),
            skills: ['Dart'],
          ),
          acceptedEdits: const [],
          appliedCount: 0,
          skippedCount: 0,
        ),
        returnsNormally,
      );
    });
  });
}

ResumeJson _resume({
  String name = 'Alex Chen',
  String email = 'alex@example.com',
  String phone = '555-123-4567',
  String summary = 'Product-minded engineer.',
  String company = 'Orbit',
  String role = 'Frontend Engineer',
  String start = '2024',
  String bullet = 'Built dashboard UI.',
}) {
  return ResumeJson(
    header: ResumeHeader(
      name: name,
      email: email,
      phone: phone,
      location: 'Taipei',
      linkedin: 'linkedin.com/in/alex',
    ),
    summary: summary,
    experience: [
      ResumeExperience(
        company: company,
        role: role,
        start: start,
        bullets: [bullet],
      ),
    ],
    education: const [
      ResumeEducation(school: 'National Taiwan University', degree: 'BS CS'),
    ],
    skillGroups: const [
      ResumeSkillGroup(category: 'Frontend', items: ['Dart', 'Flutter']),
    ],
  );
}

ProposedEdit _edit({
  String path = 'experience[0].bullets[0]',
  required String original,
  required String proposed,
}) {
  return ProposedEdit(
    targetPath: path,
    originalText: original,
    proposedText: proposed,
    reason: 'Better aligns with the role.',
  );
}

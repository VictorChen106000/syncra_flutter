import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/resumes/models/resume_json.dart';
import 'package:syncra/features/resumes/services/resume_quality_service.dart';

void main() {
  const service = ResumeQualityService();

  group('ResumeQualityService', () {
    test('keeps unique skills unchanged', () {
      final cleaned = service.cleanTailoredResume(
        _resume(skills: const ['Dart', 'Flutter', 'Firebase']),
      );

      expect(cleaned.skills, ['Dart', 'Flutter', 'Firebase']);
    });

    test('removes case-insensitive duplicate flat skills', () {
      final cleaned = service.cleanTailoredResume(
        _resume(skills: const ['React', 'react', 'TypeScript']),
      );

      expect(cleaned.skills, ['React', 'TypeScript']);
    });

    test('removes bracketed repeated skill-list artifacts', () {
      final cleaned = service.cleanTailoredResume(
        _resume(
          groups: const [
            ResumeSkillGroup(
              category: 'Frontend',
              items: [
                'React',
                'TypeScript',
                'Tailwind CSS',
                '[React, TypeScript, Tailwind CSS]',
              ],
            ),
          ],
        ),
      );

      expect(cleaned.skillGroups.single.items, [
        'React',
        'TypeScript',
        'Tailwind CSS',
      ]);
    });

    test('preserves first display casing', () {
      final cleaned = service.cleanTailoredResume(
        _resume(skills: const ['JavaScript', 'javascript', 'JAVASCRIPT']),
      );

      expect(cleaned.skills, ['JavaScript']);
    });

    test('does not alter non-skill sections', () {
      final original = _resume(
        skills: const ['Dart', 'dart'],
        summary: 'Product-minded engineer.',
        bullet: 'Built dashboard UI.',
      );

      final cleaned = service.cleanTailoredResume(original);

      expect(cleaned.summary, original.summary);
      expect(cleaned.experience.single.company, 'Orbit');
      expect(cleaned.experience.single.bullets.single, 'Built dashboard UI.');
      expect(cleaned.skills, ['Dart']);
    });
  });
}

ResumeJson _resume({
  List<String> skills = const [],
  List<ResumeSkillGroup> groups = const [],
  String summary = 'Engineer.',
  String bullet = 'Built products.',
}) {
  return ResumeJson(
    header: const ResumeHeader(name: 'Alex Chen'),
    summary: summary,
    experience: [
      ResumeExperience(
        company: 'Orbit',
        role: 'Frontend Engineer',
        start: '2024',
        bullets: [bullet],
      ),
    ],
    skills: skills,
    skillGroups: groups,
  );
}

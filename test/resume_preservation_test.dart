import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/resumes/models/proposed_edit.dart';
import 'package:syncra/features/resumes/models/resume_json.dart';
import 'package:syncra/features/resumes/services/resume_diff_service.dart';

/// Guards the fix for "my base resume goes missing after tailoring": every
/// section the resume carries — including Achievements & Certifications,
/// grouped skills, and education sub-bullets — must survive the
/// toJson → fromJson round-trip the parser/cache/diff pipeline relies on, and
/// must be reachable by the diff engine's `target_path` grammar.
ResumeJson _fullResume() => const ResumeJson(
      header: ResumeHeader(
        name: 'Daryn James Welling',
        email: 'djwofficial8@gmail.com',
        github: 'github.com/djwofficial',
        twitter: 'x.com/DarynWellingg',
      ),
      education: [
        ResumeEducation(
          school: 'National Tsing Hua University',
          degree: 'BS Electrical Engineering and Computer Science',
          start: 'Sep 2024',
          end: 'Jun 2028',
          bullets: [
            'Admitted to the FinTech and Blockchain Program',
            'Coursework: Cryptography & Network Security',
          ],
        ),
      ],
      projects: [
        ResumeProject(
          name: 'Cross-Platform Tower Defense Game',
          date: 'Spring 2025',
          bullets: ['Built a tower defense game in C++ using Allegro.'],
        ),
      ],
      certifications: [
        ResumeCertification(
          name: 'SUI Smart Contract Completion Certificate',
          issuer: 'NTHU Blockchain Club x Sui Foundation',
          date: 'Dec 2025',
          bullets: ['Developed basic smart contracts using MOVE language'],
        ),
        ResumeCertification(
          name: 'Thousand Overseas Chinese Student Scholarship',
          date: 'Nov 2024',
          bullets: ['Awarded 50,000 NTD merit for academic excellence.'],
        ),
      ],
      skillGroups: [
        ResumeSkillGroup(
          category: 'Languages',
          items: ['C/C++', 'Python', 'Dart'],
        ),
        ResumeSkillGroup(
          category: 'Tools & Frameworks',
          items: ['Flutter', 'Firebase', 'Figma'],
        ),
      ],
    );

void main() {
  group('ResumeJson round-trip preserves every section', () {
    test('certifications survive toJson → fromJson', () {
      final back = ResumeJson.fromJson(_fullResume().toJson());
      expect(back.certifications, hasLength(2));
      expect(back.certifications[0].name,
          'SUI Smart Contract Completion Certificate');
      expect(back.certifications[0].issuer,
          'NTHU Blockchain Club x Sui Foundation');
      expect(back.certifications[0].bullets.single,
          'Developed basic smart contracts using MOVE language');
      expect(back.certifications[1].date, 'Nov 2024');
    });

    test('skill groups survive and flat skills are derived from them', () {
      final back = ResumeJson.fromJson(_fullResume().toJson());
      expect(back.skillGroups, hasLength(2));
      expect(back.skillGroups[0].category, 'Languages');
      expect(back.skillGroups[1].items, ['Flutter', 'Firebase', 'Figma']);
      // Flat list stays a faithful flattening so cosmetic callers keep working.
      expect(back.skills,
          ['C/C++', 'Python', 'Dart', 'Flutter', 'Firebase', 'Figma']);
    });

    test('education sub-bullets and project date survive', () {
      final back = ResumeJson.fromJson(_fullResume().toJson());
      expect(back.education.single.bullets, hasLength(2));
      expect(back.projects.single.date, 'Spring 2025');
    });

    test('extra header links (github / x) survive', () {
      final back = ResumeJson.fromJson(_fullResume().toJson());
      expect(back.header.github, 'github.com/djwofficial');
      expect(back.header.twitter, 'x.com/DarynWellingg');
    });

    test('legacy flat-skills resume still round-trips', () {
      final back = ResumeJson.fromJson(const {
        'header': {'name': 'Ada'},
        'skills': ['Math', 'Logic'],
      });
      expect(back.skills, ['Math', 'Logic']);
      expect(back.skillGroups, isEmpty);
    });
  });

  group('Diff engine reaches the new section paths', () {
    const service = ResumeDiffService();

    test('replaces a grouped skill item verbatim', () {
      final out = service.apply(_fullResume(), [
        const ProposedEdit(
          targetPath: 'skill_groups[0].items[2]',
          originalText: 'Dart',
          proposedText: 'Dart (Flutter)',
          reason: 'matches the target stack',
        ),
      ]);
      expect(out.applied, hasLength(1));
      expect(out.resume.skillGroups[0].items[2], 'Dart (Flutter)');
    });

    test('rewrites a certification bullet', () {
      final out = service.apply(_fullResume(), [
        const ProposedEdit(
          targetPath: 'certifications[0].bullets[0]',
          originalText: 'Developed basic smart contracts using MOVE language',
          proposedText: 'Built and deployed smart contracts in MOVE.',
          reason: 'stronger action verb for the role',
        ),
      ]);
      expect(out.applied, hasLength(1));
      expect(out.resume.certifications[0].bullets[0],
          'Built and deployed smart contracts in MOVE.');
    });

    test('a tailor edit never empties the rest of the resume', () {
      final out = service.apply(_fullResume(), [
        const ProposedEdit(
          targetPath: 'education[0].bullets[0]',
          originalText: 'Admitted to the FinTech and Blockchain Program',
          proposedText: 'Selected for the FinTech and Blockchain Program.',
          reason: 'tighter phrasing',
        ),
      ]);
      // The one edit lands and everything else is still present.
      expect(out.resume.certifications, hasLength(2));
      expect(out.resume.skillGroups, hasLength(2));
      expect(out.resume.projects, hasLength(1));
      expect(out.resume.education.single.bullets[1],
          'Coursework: Cryptography & Network Security');
    });
  });
}

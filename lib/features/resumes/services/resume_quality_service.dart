import '../models/resume_json.dart';

class ResumeQualityService {
  const ResumeQualityService();

  ResumeJson cleanTailoredResume(ResumeJson resume) {
    return _dedupeSkills(resume);
  }

  ResumeJson _dedupeSkills(ResumeJson resume) {
    final individualSkills = _individualSkillKeys(resume);
    final seen = <String>{};

    List<String> cleanItems(Iterable<String> items) {
      final cleaned = <String>[];
      for (final item in items) {
        final value = item.trim();
        if (value.isEmpty) continue;
        if (_isRepeatedListArtifact(value, individualSkills)) continue;

        final key = _skillKey(value);
        if (key.isEmpty || seen.contains(key)) continue;
        seen.add(key);
        cleaned.add(value);
      }
      return cleaned;
    }

    if (resume.skillGroups.isNotEmpty) {
      final groups = [
        for (final group in resume.skillGroups)
          ResumeSkillGroup(
            category: group.category,
            items: cleanItems(group.items),
          ),
      ];

      return ResumeJson(
        header: resume.header,
        summary: resume.summary,
        experience: resume.experience,
        education: resume.education,
        skillGroups: groups,
        skills: [for (final group in groups) ...group.items],
        projects: resume.projects,
        certifications: resume.certifications,
      );
    }

    return ResumeJson(
      header: resume.header,
      summary: resume.summary,
      experience: resume.experience,
      education: resume.education,
      skills: cleanItems(resume.skills),
      projects: resume.projects,
      certifications: resume.certifications,
    );
  }

  Set<String> _individualSkillKeys(ResumeJson resume) {
    final keys = <String>{};
    final allItems = resume.skillGroups.isNotEmpty
        ? [for (final group in resume.skillGroups) ...group.items]
        : resume.skills;

    for (final item in allItems) {
      final value = item.trim();
      if (value.isEmpty || _listItems(value).length >= 2) continue;
      final key = _skillKey(value);
      if (key.isNotEmpty) keys.add(key);
    }
    return keys;
  }

  bool _isRepeatedListArtifact(String value, Set<String> individualSkills) {
    final listItems = _listItems(value);
    if (listItems.length < 2) return false;
    if (!value.trim().startsWith('[') && listItems.length < 4) return false;

    final supportedItems = listItems
        .map(_skillKey)
        .where((key) => key.isNotEmpty)
        .where(individualSkills.contains)
        .length;

    return supportedItems >= 2 && supportedItems == listItems.length;
  }

  List<String> _listItems(String value) {
    final trimmed = value.trim();
    final bracketed = trimmed.startsWith('[') && trimmed.endsWith(']');
    if (!bracketed && !trimmed.contains(';')) return const [];

    final inner = bracketed
        ? trimmed.substring(1, trimmed.length - 1)
        : trimmed;
    return inner
        .split(RegExp(r'[,;]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String _skillKey(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[\[\]{}()]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9+#]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

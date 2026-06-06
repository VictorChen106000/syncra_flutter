import '../models/proposed_edit.dart';
import '../models/resume_integrity_result.dart';
import '../models/resume_json.dart';

class ResumeIntegrityService {
  const ResumeIntegrityService();

  ResumeIntegrityResult verify({
    required ResumeJson original,
    required ResumeJson tailored,
    required List<ProposedEdit> acceptedEdits,
    required int appliedCount,
    required int skippedCount,
  }) {
    final signals = <ResumeIntegritySignal>[];
    final originalText = _flattenResume(original);
    final tailoredText = _flattenResume(tailored);
    final supportText = _normalizeSearch(
      '$originalText ${_flattenAcceptedEdits(acceptedEdits)}',
    );

    void add(
      ResumeIntegritySignalSeverity severity,
      String label,
      String detail,
    ) {
      signals.add(
        ResumeIntegritySignal(severity: severity, label: label, detail: detail),
      );
    }

    if (!_hasResumeContent(tailored)) {
      add(
        ResumeIntegritySignalSeverity.blocking,
        'Tailored resume is empty',
        'The tailored resume has no populated resume sections.',
      );
    }

    _checkSectionLoss(original, tailored, add);
    _checkContentDrop(originalText, tailoredText, add);
    _checkProtectedFields(original, tailored, add);

    if (acceptedEdits.isNotEmpty && appliedCount == 0) {
      add(
        ResumeIntegritySignalSeverity.blocking,
        'Accepted edits did not land',
        'The user accepted edits, but none matched the source resume.',
      );
    }

    if (skippedCount > 0) {
      add(
        ResumeIntegritySignalSeverity.warning,
        'Some accepted edits were skipped',
        '$skippedCount accepted edit${skippedCount == 1 ? '' : 's'} did not match the source resume.',
      );
    }

    _checkStructuredClaims(tailored, supportText, add);
    _checkNumericClaims(tailoredText, supportText, add);

    final status =
        signals.any(
          (signal) => signal.severity == ResumeIntegritySignalSeverity.blocking,
        )
        ? ResumeIntegrityStatus.blocked
        : signals.any(
            (signal) =>
                signal.severity == ResumeIntegritySignalSeverity.warning,
          )
        ? ResumeIntegrityStatus.needsReview
        : ResumeIntegrityStatus.verified;

    final resultSignals = status == ResumeIntegrityStatus.verified
        ? [
            const ResumeIntegritySignal(
              severity: ResumeIntegritySignalSeverity.info,
              label: 'Accepted edits landed',
              detail:
                  'No unsupported protected facts, claims, or section loss were detected.',
            ),
          ]
        : signals;

    return ResumeIntegrityResult(
      status: status,
      label: ResumeIntegrityResult.defaultLabel(status),
      summary: ResumeIntegrityResult.defaultSummary(status),
      signals: List.unmodifiable(resultSignals),
    );
  }

  static void _checkSectionLoss(
    ResumeJson original,
    ResumeJson tailored,
    void Function(ResumeIntegritySignalSeverity, String, String) add,
  ) {
    final originalSections = _populatedSections(original);
    final tailoredSections = _populatedSections(tailored);
    final missing = <String>[
      for (final entry in originalSections.entries)
        if (entry.value && !(tailoredSections[entry.key] ?? false)) entry.key,
    ];
    if (missing.isEmpty) return;

    final coreMissing =
        missing.contains('experience') || missing.contains('education');
    if (coreMissing || missing.length >= 2) {
      add(
        ResumeIntegritySignalSeverity.blocking,
        'Resume sections were dropped',
        'The tailored resume is missing ${missing.join(', ')} from the original.',
      );
      return;
    }

    add(
      ResumeIntegritySignalSeverity.warning,
      'A resume section may be missing',
      'The tailored resume no longer shows ${missing.single}.',
    );
  }

  static void _checkContentDrop(
    String originalText,
    String tailoredText,
    void Function(ResumeIntegritySignalSeverity, String, String) add,
  ) {
    final originalLength = _normalizeSearch(originalText).length;
    final tailoredLength = _normalizeSearch(tailoredText).length;
    if (originalLength < 120) return;
    if (tailoredLength >= originalLength * 0.55) return;

    add(
      ResumeIntegritySignalSeverity.blocking,
      'Too much resume content changed',
      'The tailored resume is much shorter than the original, which may indicate accidental content loss.',
    );
  }

  static void _checkProtectedFields(
    ResumeJson original,
    ResumeJson tailored,
    void Function(ResumeIntegritySignalSeverity, String, String) add,
  ) {
    final a = original.header;
    final b = tailored.header;

    void compare(
      String label,
      String? originalValue,
      String? tailoredValue, {
      _ProtectedKind kind = _ProtectedKind.text,
    }) {
      final before = _clean(originalValue);
      if (before == null) return;
      final after = _clean(tailoredValue);
      final normalizedBefore = _normalizeProtected(before, kind);
      final normalizedAfter = _normalizeProtected(after ?? '', kind);
      if (normalizedBefore == normalizedAfter) return;

      add(
        ResumeIntegritySignalSeverity.blocking,
        '$label changed',
        'The tailored resume changed $label from "${_short(before)}" to "${_short(after ?? 'blank')}".',
      );
    }

    compare('candidate name', a.name, b.name);
    compare('email', a.email, b.email);
    compare('phone', a.phone, b.phone, kind: _ProtectedKind.phone);
    compare('location', a.location, b.location);
    compare('LinkedIn', a.linkedin, b.linkedin, kind: _ProtectedKind.link);
    compare('website', a.website, b.website, kind: _ProtectedKind.link);
    compare('GitHub', a.github, b.github, kind: _ProtectedKind.link);
    compare('X/Twitter', a.twitter, b.twitter, kind: _ProtectedKind.link);
  }

  static void _checkStructuredClaims(
    ResumeJson tailored,
    String supportText,
    void Function(ResumeIntegritySignalSeverity, String, String) add,
  ) {
    void checkClaims({
      required String label,
      required String detailLabel,
      required Iterable<String?> claims,
      required ResumeIntegritySignalSeverity severity,
    }) {
      final seen = <String>{};
      for (final raw in claims) {
        final claim = _clean(raw);
        if (claim == null) continue;
        final normalized = _normalizeSearch(claim);
        if (normalized.isEmpty || !seen.add(normalized)) continue;
        if (_isSupported(claim, supportText)) continue;

        add(
          severity,
          label,
          '$detailLabel "${_short(claim)}" appears in the tailored resume but was not found in the original resume or accepted edit text.',
        );
      }
    }

    checkClaims(
      label: 'Unsupported company',
      detailLabel: 'Company',
      claims: tailored.experience.map((entry) => entry.company),
      severity: ResumeIntegritySignalSeverity.blocking,
    );
    checkClaims(
      label: 'Unsupported role/title',
      detailLabel: 'Role/title',
      claims: tailored.experience.map((entry) => entry.role),
      severity: ResumeIntegritySignalSeverity.blocking,
    );
    checkClaims(
      label: 'Unsupported school',
      detailLabel: 'School',
      claims: tailored.education.map((entry) => entry.school),
      severity: ResumeIntegritySignalSeverity.blocking,
    );
    checkClaims(
      label: 'Unsupported date',
      detailLabel: 'Date',
      claims: [
        for (final entry in tailored.experience) ...[entry.start, entry.end],
        for (final entry in tailored.education) ...[entry.start, entry.end],
        for (final project in tailored.projects) project.date,
        for (final cert in tailored.certifications) cert.date,
      ],
      severity: ResumeIntegritySignalSeverity.blocking,
    );
    checkClaims(
      label: 'Unsupported degree',
      detailLabel: 'Degree',
      claims: tailored.education.map((entry) => entry.degree),
      severity: ResumeIntegritySignalSeverity.warning,
    );
    checkClaims(
      label: 'Unsupported certification',
      detailLabel: 'Certification',
      claims: [
        for (final cert in tailored.certifications) ...[cert.name, cert.issuer],
      ],
      severity: ResumeIntegritySignalSeverity.warning,
    );
    checkClaims(
      label: 'Unsupported project',
      detailLabel: 'Project',
      claims: tailored.projects.map((project) => project.name),
      severity: ResumeIntegritySignalSeverity.warning,
    );
  }

  static void _checkNumericClaims(
    String tailoredText,
    String supportText,
    void Function(ResumeIntegritySignalSeverity, String, String) add,
  ) {
    final seen = <String>{};
    for (final claim in _numericClaims(tailoredText)) {
      final normalized = _normalizeSearch(claim);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      if (_isSupported(claim, supportText)) continue;

      add(
        ResumeIntegritySignalSeverity.warning,
        'Unsupported numeric claim',
        'The metric "${_short(claim)}" appears in the tailored resume but was not found in the original resume or accepted edit text.',
      );
    }
  }

  static Iterable<String> _numericClaims(String text) sync* {
    final patterns = [
      RegExp(r'\b\d+(?:\.\d+)?\s*%', caseSensitive: false),
      RegExp(r'\b\d+(?:\.\d+)?\s*percent\b', caseSensitive: false),
      RegExp(
        r'(?:\$|usd\s*)\s*\d[\d,]*(?:\.\d+)?\s*(?:k|m|b)?\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b\d+(?:\.\d+)?\+?\s*(?:years?|yrs?)(?:\s+of\s+experience)?\b',
        caseSensitive: false,
      ),
      RegExp(r'\bteam\s+of\s+\d+\b', caseSensitive: false),
      RegExp(
        r'\b(?:led|managed|supervised)\s+\d+\s+(?:people|engineers|members|teammates|developers|staff)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b\d{2,}(?:,\d{3})*\s+(?:users|customers|clients|requests|tickets|applications|projects|students|employees|transactions|records|sales|leads)\b',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        final value = match.group(0)?.trim();
        if (value != null && value.isNotEmpty) yield value;
      }
    }
  }

  static bool _isSupported(String claim, String supportText) {
    final normalized = _normalizeSearch(claim);
    return normalized.isEmpty || supportText.contains(normalized);
  }

  static String _flattenAcceptedEdits(List<ProposedEdit> edits) {
    return edits
        .map((edit) => '${edit.originalText} ${edit.proposedText}')
        .join(' ');
  }

  static String _flattenResume(ResumeJson resume) {
    final values = <String>[];

    void visit(Object? value) {
      if (value == null) return;
      if (value is String) {
        final clean = value.trim();
        if (clean.isNotEmpty) values.add(clean);
        return;
      }
      if (value is Map) {
        for (final child in value.values) {
          visit(child);
        }
        return;
      }
      if (value is Iterable) {
        for (final child in value) {
          visit(child);
        }
      }
    }

    visit(resume.toJson());
    return values.join(' ');
  }

  static Map<String, bool> _populatedSections(ResumeJson resume) => {
    'summary': _clean(resume.summary) != null,
    'experience': resume.experience.any(
      (entry) =>
          _clean(entry.company) != null ||
          _clean(entry.role) != null ||
          entry.bullets.any((bullet) => _clean(bullet) != null),
    ),
    'education': resume.education.any(
      (entry) =>
          _clean(entry.school) != null ||
          _clean(entry.degree) != null ||
          _clean(entry.details) != null ||
          entry.bullets.any((bullet) => _clean(bullet) != null),
    ),
    'projects': resume.projects.any(
      (project) =>
          _clean(project.name) != null ||
          _clean(project.description) != null ||
          project.bullets.any((bullet) => _clean(bullet) != null),
    ),
    'certifications': resume.certifications.any(
      (cert) =>
          _clean(cert.name) != null ||
          _clean(cert.issuer) != null ||
          cert.bullets.any((bullet) => _clean(bullet) != null),
    ),
    'skills':
        resume.skills.any((skill) => _clean(skill) != null) ||
        resume.skillGroups.any(
          (group) =>
              _clean(group.category) != null ||
              group.items.any((skill) => _clean(skill) != null),
        ),
  };

  static bool _hasResumeContent(ResumeJson resume) {
    return _populatedSections(resume).values.any((value) => value);
  }

  static String _normalizeSearch(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[‘’‛′]'), "'")
        .replaceAll(RegExp(r'[“”″]'), '"')
        .replaceAll(RegExp(r'[–—]'), ' ')
        .replaceAll('…', ' ')
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^a-z0-9@.+#%$]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _normalizeProtected(String input, _ProtectedKind kind) {
    final clean = input.trim().toLowerCase();
    return switch (kind) {
      _ProtectedKind.phone => clean.replaceAll(RegExp(r'[^0-9+]'), ''),
      _ProtectedKind.link =>
        clean
            .replaceFirst(RegExp(r'^https?://'), '')
            .replaceFirst(RegExp(r'^www\.'), '')
            .replaceAll(RegExp(r'/+$'), ''),
      _ProtectedKind.text => _normalizeSearch(clean),
    };
  }

  static String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  static String _short(String value) {
    final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= 80) return clean;
    return '${clean.substring(0, 77)}...';
  }
}

enum _ProtectedKind { text, phone, link }

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/resume_json.dart';

/// Renders a [ResumeJson] into a designed two-column PDF: a dark ink sidebar
/// (contact, skills, education) beside a clean main column (name, summary,
/// experience, projects). Uses the Syncra brand (ink + lime accent) so the
/// tailored output looks polished in-app, not just plain black-on-white.
///
/// The agent still only paraphrases content — this template owns the look.
/// Tuned for visual polish in the demo (not ATS parsing). Single fixed
/// layout, one page. Uses ASCII-only separators since the built-in
/// Helvetica has no em/en-dash glyphs (they'd render as tofu boxes).
class ResumePdfTemplate {
  const ResumePdfTemplate();

  // Brand palette (mirrors AppColors).
  static const PdfColor _ink = PdfColor.fromInt(0xFF000100);
  static const PdfColor _lime = PdfColor.fromInt(0xFFA0FE08);

  static const double _sidebarWidth = 190;

  Future<Uint8List> render(ResumeJson resume) async {
    final doc = pw.Document(title: resume.header.name);
    final format = PdfPageFormat.letter;

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: _sidebarWidth,
              height: format.height,
              color: _ink,
              padding: const pw.EdgeInsets.fromLTRB(22, 30, 20, 30),
              child: _sidebar(resume),
            ),
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(26, 34, 38, 30),
                child: _main(resume),
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // Sidebar (dark column)
  // ---------------------------------------------------------------------------

  pw.Widget _sidebar(ResumeJson resume) {
    final h = resume.header;
    final contacts = <String>[
      if ((h.email ?? '').isNotEmpty) h.email!,
      if ((h.phone ?? '').isNotEmpty) h.phone!,
      if ((h.location ?? '').isNotEmpty) h.location!,
      if ((h.linkedin ?? '').isNotEmpty) h.linkedin!,
      if ((h.website ?? '').isNotEmpty) h.website!,
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (contacts.isNotEmpty) ...[
          _sidebarTitle('CONTACT'),
          pw.SizedBox(height: 6),
          for (final c in contacts) ...[
            pw.Text(c, style: _sidebarBody),
            pw.SizedBox(height: 4),
          ],
          pw.SizedBox(height: 14),
        ],
        if (resume.skills.isNotEmpty) ...[
          _sidebarTitle('SKILLS'),
          pw.SizedBox(height: 6),
          for (final s in resume.skills) ...[
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 3.5, right: 6),
                  width: 3,
                  height: 3,
                  decoration: const pw.BoxDecoration(
                    color: _lime,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.Expanded(child: pw.Text(s, style: _sidebarBody)),
              ],
            ),
            pw.SizedBox(height: 4),
          ],
          pw.SizedBox(height: 14),
        ],
        if (resume.education.isNotEmpty) ...[
          _sidebarTitle('EDUCATION'),
          pw.SizedBox(height: 6),
          for (final e in resume.education) ...[
            _sidebarEducation(e),
            pw.SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  pw.Widget _sidebarEducation(ResumeEducation e) {
    final dates = [e.start, e.end]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' - ');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          e.school,
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
        if (e.degree.isNotEmpty) ...[
          pw.SizedBox(height: 1),
          pw.Text(e.degree, style: _sidebarBody),
        ],
        if (dates.isNotEmpty) ...[
          pw.SizedBox(height: 1),
          pw.Text(dates, style: _sidebarMuted),
        ],
        if ((e.details ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 1),
          pw.Text(e.details!, style: _sidebarMuted),
        ],
      ],
    );
  }

  pw.Widget _sidebarTitle(String label) {
    return pw.Text(
      label,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 1.4,
        color: _lime,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Main (light column)
  // ---------------------------------------------------------------------------

  pw.Widget _main(ResumeJson resume) {
    final subtitle =
        resume.experience.isNotEmpty ? resume.experience.first.role : null;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          resume.header.name.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.5,
            color: _ink,
          ),
        ),
        if ((subtitle ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            subtitle!,
            style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
          ),
        ],
        pw.SizedBox(height: 18),
        if ((resume.summary ?? '').trim().isNotEmpty) ...[
          _mainSection(
            'SUMMARY',
            pw.Text(
              resume.summary!.trim(),
              style: _body,
              textAlign: pw.TextAlign.justify,
            ),
          ),
          pw.SizedBox(height: 16),
        ],
        if (resume.experience.isNotEmpty) ...[
          _mainSection(
            'EXPERIENCE',
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final e in resume.experience) ...[
                  _experienceEntry(e),
                  pw.SizedBox(height: 11),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 5),
        ],
        if (resume.projects.isNotEmpty)
          _mainSection(
            'PROJECTS',
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final p in resume.projects) ...[
                  _projectEntry(p),
                  pw.SizedBox(height: 10),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// A main-column section: lime tick + label + rule, then [child].
  pw.Widget _mainSection(String label, pw.Widget child) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(width: 4, height: 12, color: _lime),
            pw.SizedBox(width: 7),
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 11.5,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.4,
                color: _ink,
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Divider(
                thickness: 0.5,
                color: PdfColors.grey400,
                height: 1,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        child,
      ],
    );
  }

  pw.Widget _experienceEntry(ResumeExperience e) {
    final end = (e.end ?? '').isEmpty ? 'Present' : e.end!;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: e.company,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    pw.TextSpan(
                      text: '  |  ${e.role}',
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.Text(
              '${e.start} - $end',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
        if ((e.location ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            e.location!,
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ],
        if (e.bullets.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          for (final b in e.bullets) _bullet(b),
        ],
      ],
    );
  }

  pw.Widget _projectEntry(ResumeProject p) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          p.name,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        if ((p.description ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(p.description!, style: _body),
        ],
        if (p.bullets.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          for (final b in p.bullets) _bullet(b),
        ],
        if ((p.link ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            p.link!,
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.blue700,
              decoration: pw.TextDecoration.underline,
            ),
          ),
        ],
      ],
    );
  }

  pw.Widget _bullet(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 2.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 3.5, right: 6),
            width: 3,
            height: 3,
            decoration: const pw.BoxDecoration(
              color: _lime,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.Expanded(child: pw.Text(text, style: _body)),
        ],
      ),
    );
  }

  // Text styles ---------------------------------------------------------------

  static const _body = pw.TextStyle(fontSize: 9.5, lineSpacing: 2);

  static final _sidebarBody = pw.TextStyle(
    fontSize: 9,
    color: PdfColors.grey300,
    lineSpacing: 1.5,
  );

  static final _sidebarMuted = pw.TextStyle(
    fontSize: 8.5,
    color: PdfColors.grey400,
  );
}

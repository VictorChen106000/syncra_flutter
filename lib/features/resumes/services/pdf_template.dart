import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/resume_json.dart';

/// Renders a [ResumeJson] into a PDF using the single fixed template
/// described in api-contract.md §7. Classic single-column, ATS-safe,
/// black-on-white. The agent paraphrases the content; layout never
/// changes.
class ResumePdfTemplate {
  const ResumePdfTemplate();

  Future<Uint8List> render(ResumeJson resume) async {
    final doc = pw.Document(title: resume.header.name);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 48),
        build: (context) => [
          _header(resume.header),
          if ((resume.summary ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _sectionTitle('SUMMARY'),
            pw.SizedBox(height: 6),
            pw.Text(
              resume.summary!.trim(),
              style: _body,
              textAlign: pw.TextAlign.justify,
            ),
          ],
          if (resume.experience.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _sectionTitle('EXPERIENCE'),
            pw.SizedBox(height: 6),
            for (final e in resume.experience) ...[
              _experienceEntry(e),
              pw.SizedBox(height: 10),
            ],
          ],
          if (resume.education.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            _sectionTitle('EDUCATION'),
            pw.SizedBox(height: 6),
            for (final e in resume.education) ...[
              _educationEntry(e),
              pw.SizedBox(height: 8),
            ],
          ],
          if (resume.skills.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            _sectionTitle('SKILLS'),
            pw.SizedBox(height: 6),
            pw.Text(resume.skills.join(' · '), style: _body),
          ],
          if (resume.projects.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _sectionTitle('PROJECTS'),
            pw.SizedBox(height: 6),
            for (final p in resume.projects) ...[
              _projectEntry(p),
              pw.SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // Section builders
  // ---------------------------------------------------------------------------

  pw.Widget _header(ResumeHeader h) {
    final contactBits = <String>[
      if ((h.email ?? '').isNotEmpty) h.email!,
      if ((h.phone ?? '').isNotEmpty) h.phone!,
      if ((h.location ?? '').isNotEmpty) h.location!,
      if ((h.linkedin ?? '').isNotEmpty) h.linkedin!,
      if ((h.website ?? '').isNotEmpty) h.website!,
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          h.name.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.5,
          ),
          textAlign: pw.TextAlign.center,
        ),
        if (contactBits.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            contactBits.join('  ·  '),
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ],
    );
  }

  pw.Widget _sectionTitle(String label) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Divider(thickness: 0.5, color: PdfColors.grey700, height: 1),
      ],
    );
  }

  pw.Widget _experienceEntry(ResumeExperience e) {
    final end = (e.end ?? '').isEmpty ? 'Present' : e.end!;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
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
                      ),
                    ),
                    pw.TextSpan(
                      text: '  —  ${e.role}',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            pw.Text(
              '${e.start} – $end',
              style: pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
            ),
          ],
        ),
        if ((e.location ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            e.location!,
            style: pw.TextStyle(
              fontSize: 9.5,
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

  pw.Widget _educationEntry(ResumeEducation e) {
    final dates = [e.start, e.end].whereType<String>().where((s) => s.isNotEmpty).join(' – ');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: e.school,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.TextSpan(
                      text: '  —  ${e.degree}',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            if (dates.isNotEmpty)
              pw.Text(
                dates,
                style: pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
              ),
          ],
        ),
        if ((e.details ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            e.details!,
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
          ),
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
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
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
              fontSize: 9.5,
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
      padding: const pw.EdgeInsets.only(left: 10, top: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('• ', style: _body),
          pw.Expanded(child: pw.Text(text, style: _body)),
        ],
      ),
    );
  }

  static const _body = pw.TextStyle(fontSize: 10, lineSpacing: 2);
}

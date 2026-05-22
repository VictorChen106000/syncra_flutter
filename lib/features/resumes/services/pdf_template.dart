import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/resume_json.dart';

/// Renders a [ResumeJson] into a clean, single-column "academic" PDF: a big
/// name with right-aligned contact details at the top, then small-caps section
/// headers (each underlined with a full-width rule), bold entry titles with
/// right-aligned italic dates, and bulleted achievements underneath.
///
/// The look mirrors a classic LaTeX/`article`-style resume — pure black serif
/// (Times) on white, no color. The agent only paraphrases content; this
/// template owns the layout. ASCII-only separators ('-', '|') are used because
/// the built-in serif fonts have no em/en-dash glyphs (they'd render as tofu).
class ResumePdfTemplate {
  const ResumePdfTemplate();

  Future<Uint8List> render(ResumeJson resume) async {
    final doc = pw.Document(
      title: resume.header.name,
      theme: pw.ThemeData.withFont(
        base: pw.Font.times(),
        bold: pw.Font.timesBold(),
        italic: pw.Font.timesItalic(),
        boldItalic: pw.Font.timesBoldItalic(),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(44, 40, 44, 40),
        build: (context) => [
          _header(resume),
          ..._sections(resume),
        ],
      ),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // Header: name (left) + right-aligned contact block.
  // ---------------------------------------------------------------------------

  pw.Widget _header(ResumeJson resume) {
    final h = resume.header;
    final contacts = <_Contact>[
      if ((h.email ?? '').isNotEmpty) _Contact('Email:', h.email!),
      if ((h.phone ?? '').isNotEmpty) _Contact('Mobile:', h.phone!),
      if ((h.location ?? '').isNotEmpty) _Contact('Location:', h.location!),
      if ((h.linkedin ?? '').isNotEmpty) _Contact('LinkedIn:', h.linkedin!),
      if ((h.website ?? '').isNotEmpty) _Contact('Website:', h.website!),
    ];

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              h.name,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              for (final c in contacts) ...[
                pw.RichText(
                  textAlign: pw.TextAlign.right,
                  text: pw.TextSpan(
                    children: [
                      pw.TextSpan(
                        text: '${c.label} ',
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.TextSpan(
                        text: c.value,
                        style: const pw.TextStyle(fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 2),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Body sections — only those with content are rendered.
  // ---------------------------------------------------------------------------

  List<pw.Widget> _sections(ResumeJson resume) {
    final out = <pw.Widget>[];

    if ((resume.summary ?? '').trim().isNotEmpty) {
      out.add(_section('Summary', [
        pw.Text(
          resume.summary!.trim(),
          style: _body,
          textAlign: pw.TextAlign.justify,
        ),
      ]));
    }

    if (resume.experience.isNotEmpty) {
      out.add(_section('Experience', [
        for (final e in resume.experience) _experienceEntry(e),
      ]));
    }

    if (resume.education.isNotEmpty) {
      out.add(_section('Education', [
        for (final e in resume.education) _educationEntry(e),
      ]));
    }

    if (resume.projects.isNotEmpty) {
      out.add(_section('Projects', [
        for (final p in resume.projects) _projectEntry(p),
      ]));
    }

    if (resume.skills.isNotEmpty) {
      out.add(_section('Skills', [
        pw.Text(resume.skills.join(', '), style: _body),
      ]));
    }

    return out;
  }

  /// A section: small-caps title, full-width rule, then [children] stacked.
  pw.Widget _section(String title, List<pw.Widget> children) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 12.5,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          pw.Divider(thickness: 0.8, color: PdfColors.black, height: 6),
          pw.SizedBox(height: 4),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) pw.SizedBox(height: 9),
            children[i],
          ],
        ],
      ),
    );
  }

  // --- Entries ---------------------------------------------------------------

  pw.Widget _experienceEntry(ResumeExperience e) {
    final end = (e.end ?? '').isEmpty ? 'Present' : e.end!;
    final dates = e.start.isEmpty ? '' : '${e.start} - $end';
    final subtitle = [e.role, if ((e.location ?? '').isNotEmpty) e.location!]
        .where((s) => s.isNotEmpty)
        .join(', ');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titleDateRow(e.company, dates),
        if (subtitle.isNotEmpty) ...[
          pw.SizedBox(height: 1),
          pw.Text(subtitle, style: _subtitle),
        ],
        ..._bullets(e.bullets),
      ],
    );
  }

  pw.Widget _educationEntry(ResumeEducation e) {
    final dates = [e.start, e.end]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' - ');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titleDateRow(e.school, dates),
        if (e.degree.isNotEmpty) ...[
          pw.SizedBox(height: 1),
          pw.Text(e.degree, style: _subtitle),
        ],
        if ((e.details ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 1),
          pw.Text(e.details!, style: _body),
        ],
      ],
    );
  }

  pw.Widget _projectEntry(ResumeProject p) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titleDateRow(p.name, ''),
        if ((p.description ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 1),
          pw.Text(p.description!, style: _subtitle),
        ],
        ..._bullets(p.bullets),
        if ((p.link ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            p.link!,
            style: const pw.TextStyle(
              fontSize: 9,
              decoration: pw.TextDecoration.underline,
            ),
          ),
        ],
      ],
    );
  }

  /// Bold title on the left, right-aligned italic date on the right.
  pw.Widget _titleDateRow(String title, String date) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Text(
            title,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ),
        if (date.isNotEmpty)
          pw.Text(
            date,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey800,
            ),
          ),
      ],
    );
  }

  List<pw.Widget> _bullets(List<String> bullets) {
    if (bullets.isEmpty) return const [];
    return [
      pw.SizedBox(height: 3),
      for (final b in bullets) _bullet(b),
    ];
  }

  pw.Widget _bullet(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            margin: const pw.EdgeInsets.only(left: 3, top: 3.5, right: 7),
            width: 2.5,
            height: 2.5,
            decoration: const pw.BoxDecoration(
              color: PdfColors.black,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.Expanded(child: pw.Text(text, style: _body)),
        ],
      ),
    );
  }

  // --- Text styles -----------------------------------------------------------

  static const _body = pw.TextStyle(fontSize: 9.5, lineSpacing: 1.6);

  static final _subtitle = pw.TextStyle(
    fontSize: 9.5,
    fontStyle: pw.FontStyle.italic,
  );
}

/// A labeled contact line in the header (e.g. "Email:" + value).
class _Contact {
  const _Contact(this.label, this.value);
  final String label;
  final String value;
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../models/resume_file.dart';
import '../state/resume_controller.dart';

class ResumePreviewPage extends StatelessWidget {
  const ResumePreviewPage({super.key, this.resume});

  final ResumeFile? resume;

  void _confirmDelete(BuildContext context, ResumeFile r) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete resume?'),
        content: Text('${r.name} will be removed from your uploads.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              context.read<ResumeController>().deleteResume(r.id);
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text('${r.name} deleted'),
                  ),
                );
              context.go(RouteNames.resumes);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latestResume = resume == null
        ? null
        : context.watch<ResumeController>().resumeById(resume!.id) ?? resume;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.scaffold.withValues(alpha: 0.95),
                      AppColors.scaffold.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    AppBackButton(
                      onPressed: () => context.go(RouteNames.resumes),
                    ),
                    const Spacer(),
                    if (latestResume != null)
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          onPressed: () =>
                              _confirmDelete(context, latestResume),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 80, 20, 100),
              child: latestResume == null
                  ? _EmptyPreview()
                  : _ResumePreviewBody(resume: latestResume),
            ),
            if (latestResume != null)
              Positioned(
                left: 24,
                right: 24,
                bottom: 24,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 280),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.ink.withValues(alpha: 0.80),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.description_rounded,
                          color: AppColors.accent,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            latestResume.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Renders the actual PDF when bytes/path are available; falls back to a
/// metadata placeholder for DOC/DOCX or seeded mock files.
class _ResumePreviewBody extends StatelessWidget {
  const _ResumePreviewBody({required this.resume});

  final ResumeFile resume;

  @override
  Widget build(BuildContext context) {
    if (resume.isPdf && resume.isAvailableLocally) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: SizedBox.expand(
            child: resume.bytes != null
                ? SfPdfViewer.memory(
                    resume.bytes!,
                    key: ValueKey('${resume.id}-${resume.bytes!.length}'),
                    onDocumentLoaded: (details) {
                      debugPrint(
                        'PDF loaded: ${details.document.pages.count} pages',
                      );
                    },
                    onDocumentLoadFailed: (details) {
                      debugPrint(
                        'PDF load failed: ${details.error} ${details.description}',
                      );
                    },
                  )
                : SfPdfViewer.file(
                    File(resume.path!),
                    key: ValueKey('${resume.id}-${resume.path}'),
                  ),
          ),
        ),
      );
    }
    return _MetadataPaperPreview(resume: resume);
  }
}

class _MetadataPaperPreview extends StatelessWidget {
  const _MetadataPaperPreview({required this.resume});

  final ResumeFile resume;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              resume.name.replaceAll(RegExp(r'\.(pdf|docx?)$'), ''),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Document preview · open the file to view its contents',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            const _PreviewSection(
              title: 'FILE INFO',
              body:
                  'Live PDF preview is only available for files uploaded from this device. For DOC/DOCX or seeded examples, open them in your system viewer.',
            ),
            _PreviewSection(
              title: 'FORMAT',
              body: resume.type,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
              color: AppColors.ink.withValues(alpha: 0.70),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.description_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No resume selected',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Go back to your resume list and choose a file to preview.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../models/resume_file.dart';
import '../state/resume_notifier.dart';

class ResumePreviewPage extends ConsumerWidget {
  const ResumePreviewPage({super.key, this.resume});

  final ResumeFile? resume;

  void _confirmDelete(BuildContext context, WidgetRef ref, ResumeFile r) {
    final brand = context.brand;
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
            style: FilledButton.styleFrom(backgroundColor: brand.danger),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              ref.read(resumeProvider.notifier).deleteResume(r.id);
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(content: Text('${r.name} deleted')));
              context.go(RouteNames.resumes);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final allResumes = ref.watch(resumeProvider).allResumes;
    final latestResume = resume == null
        ? null
        : allResumes.firstWhere(
            (r) => r.id == resume!.id,
            orElse: () => resume!,
          );

    return Scaffold(
      backgroundColor: brand.bg,
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
                      brand.bg.withValues(alpha: 0.95),
                      brand.bg.withValues(alpha: 0),
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
                        decoration: BoxDecoration(
                          color: brand.surface,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: 'Delete resume',
                          onPressed: () =>
                              _confirmDelete(context, ref, latestResume),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: brand.textMuted,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: brand.ink.withValues(alpha: 0.80),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: brand.inkInverse.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.description_rounded,
                          color: brand.accent,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            latestResume.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: brand.inkInverse,
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

class _ResumePreviewBody extends ConsumerWidget {
  const _ResumePreviewBody({required this.resume});

  final ResumeFile resume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    if (!resume.isPdf || !resume.hasStorageBlob) {
      return _MetadataPaperPreview(resume: resume);
    }

    final bytesFuture = ref.read(resumeProvider.notifier).bytesFor(resume);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: brand.shadow,
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: SizedBox.expand(
          child: FutureBuilder<Uint8List?>(
            future: bytesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final bytes = snapshot.data;
              if (bytes == null) {
                return _MetadataPaperPreview(resume: resume);
              }
              return SfPdfViewer.memory(
                bytes,
                key: ValueKey('${resume.id}-${bytes.length}'),
                // Fit the page to the card width with clean chrome so the
                // resume reads clearly without manual zooming.
                canShowScrollHead: false,
                canShowScrollStatus: false,
                canShowPaginationDialog: false,
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
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MetadataPaperPreview extends StatelessWidget {
  const _MetadataPaperPreview({required this.resume});

  final ResumeFile resume;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: brand.shadow,
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
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: brand.ink,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Document preview · open the file to view its contents',
              style: TextStyle(
                color: brand.textMuted,
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
            _PreviewSection(title: 'FORMAT', body: resume.type),
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
    final brand = context.brand;
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
              color: brand.ink.withValues(alpha: 0.70),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              color: brand.ink,
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
    final brand = context.brand;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: brand.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: brand.ink,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.description_rounded,
                color: brand.inkInverse,
                size: 24,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No resume selected',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: brand.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Go back to your resume list and choose a file to preview.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: brand.textMuted,
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

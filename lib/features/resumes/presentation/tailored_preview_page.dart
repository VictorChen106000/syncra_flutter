import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../core/theme/brand_theme.dart';
import '../../agent_chat/state/agent_chat_notifier.dart';
import '../models/resume_json.dart';

/// Counts the populated top-level sections of a tailored resume. Drives the
/// "all N sections kept" reassurance — the tailor is non-destructive, so this
/// should match the source resume's section count.
int _sectionCount(ResumeJson r) {
  var n = 0;
  if ((r.summary ?? '').trim().isNotEmpty) n++;
  if (r.education.isNotEmpty) n++;
  if (r.experience.isNotEmpty) n++;
  if (r.projects.isNotEmpty) n++;
  if (r.certifications.isNotEmpty) n++;
  if (r.skillGroups.isNotEmpty || r.skills.isNotEmpty) n++;
  return n;
}

/// Full-screen preview of a freshly tailored resume PDF that has been rendered
/// but not yet saved. Mirrors the profile resume-preview look (white paper card
/// + [SfPdfViewer]), and gates the save behind the user's approval: "Save to my
/// resumes" persists it; "Keep editing" returns to the chat to ask for changes.
///
/// Reads its [ProposedEditsBlock] reactively by [blockId] so the UI flips to a
/// "Saved" state in place once the save completes.
class TailoredPreviewPage extends ConsumerStatefulWidget {
  const TailoredPreviewPage({super.key, required this.blockId});

  final String blockId;

  @override
  ConsumerState<TailoredPreviewPage> createState() =>
      _TailoredPreviewPageState();
}

class _TailoredPreviewPageState extends ConsumerState<TailoredPreviewPage> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(agentChatProvider.notifier)
        .savePreviewedResume(widget.blockId);
    if (!mounted) return;
    setState(() => _saving = false);

    final block = ref.read(agentChatProvider.notifier)
        .proposedEditsBlock(widget.blockId);
    final messenger = ScaffoldMessenger.of(context);
    if (block != null && block.isSaved) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Saved to your resumes')),
        );
      Navigator.of(context).maybePop();
    } else if (block?.applyError != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(block!.applyError!)));
    }
  }

  void _keepEditing() {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).maybePop();
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Tell me what to change and I\'ll re-tailor it.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    // Watch chat state so a save elsewhere reflects here too.
    ref.watch(agentChatProvider);
    final block =
        ref.read(agentChatProvider.notifier).proposedEditsBlock(widget.blockId);
    final bytes = block?.previewBytes;
    final isSaved = block?.isSaved ?? false;
    final previewResume = block?.previewResume;

    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: brand.bg,
      // The resume fills the whole phone; the header and actions float on top
      // of it over soft gradient scrims, so the page reads big and the chrome
      // never boxes the document in.
      body: Stack(
        children: [
          // Full-bleed document.
          Positioned.fill(
            child: bytes == null
                ? Center(
                    child: Text(
                      'Preview unavailable',
                      style: TextStyle(color: brand.textMuted),
                    ),
                  )
                : SfPdfViewer.memory(
                    bytes,
                    key: ValueKey('preview-${widget.blockId}-${bytes.length}'),
                    // Fit the page to the screen width with clean chrome so the
                    // resume reads clearly without manual zooming.
                    canShowScrollHead: false,
                    canShowScrollStatus: false,
                    canShowPaginationDialog: false,
                  ),
          ),

          // Floating top chrome: back + a compact title/status pill.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _ScrimGradient(
              color: brand.bg,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              padding: EdgeInsets.fromLTRB(16, topInset + 10, 16, 28),
              child: Row(
                children: [
                  _FloatingCircleButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: _FloatingTitlePill(
                      title: 'Tailored resume',
                      status: isSaved
                          ? 'Saved to your resumes'
                          : 'Preview · not saved yet',
                      statusColor: isSaved ? brand.success : brand.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Floating bottom chrome: preservation note + action pills.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ScrimGradient(
              color: brand.bg,
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              padding: EdgeInsets.fromLTRB(20, 36, 20, 16 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (previewResume != null && !isSaved) ...[
                    _PreservationNote(
                      sectionCount: _sectionCount(previewResume),
                      appliedCount: block?.appliedCount ?? 0,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _FloatingActions(
                    isSaved: isSaved,
                    saving: _saving,
                    onSave: _save,
                    onKeepEditing: _keepEditing,
                    onDone: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical fade from [color] (at [begin]) to transparent (at [end]) used as a
/// soft backing for floating chrome so it separates from the document edge
/// without becoming an opaque bar.
class _ScrimGradient extends StatelessWidget {
  const _ScrimGradient({
    required this.color,
    required this.begin,
    required this.end,
    required this.padding,
    required this.child,
  });

  final Color color;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: begin,
          end: end,
          colors: [
            color,
            color.withValues(alpha: 0.85),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: child,
    );
  }
}

/// Round, floating icon button with a soft shadow — reads cleanly over the
/// white document.
class _FloatingCircleButton extends StatelessWidget {
  const _FloatingCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.surface,
      shape: const CircleBorder(),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: brand.border),
            boxShadow: [
              BoxShadow(
                color: brand.shadow,
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: brand.ink, size: 20),
        ),
      ),
    );
  }
}

/// Compact floating pill holding the page title and live save status.
class _FloatingTitlePill extends StatelessWidget {
  const _FloatingTitlePill({
    required this.title,
    required this.status,
    required this.statusColor,
  });

  final String title;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: brand.border),
        boxShadow: [
          BoxShadow(
            color: brand.shadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: brand.ink,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingActions extends StatelessWidget {
  const _FloatingActions({
    required this.isSaved,
    required this.saving,
    required this.onSave,
    required this.onKeepEditing,
    required this.onDone,
  });

  final bool isSaved;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onKeepEditing;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    if (isSaved) {
      return _PillButton(
        label: 'Done',
        filled: true,
        onTap: onDone,
      );
    }
    return Row(
      children: [
        Expanded(
          child: _PillButton(
            label: 'Keep editing',
            filled: false,
            onTap: saving ? null : onKeepEditing,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PillButton(
            label: 'Save to my resumes',
            filled: true,
            loading: saving,
            onTap: saving ? null : onSave,
          ),
        ),
      ],
    );
  }
}

/// Floating, fully-rounded action pill with its own drop shadow.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.filled,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final bool filled;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final bg = filled ? brand.ink : brand.surface;
    final fg = filled ? brand.inkInverse : brand.ink;
    return Opacity(
      opacity: onTap == null && !loading ? 0.5 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(
              color: brand.shadow,
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(99),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: filled ? brand.ink : brand.border),
              ),
              alignment: Alignment.center,
              child: loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(fg),
                      ),
                    )
                  : Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: -0.1,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle reassurance that the tailor kept the whole resume: "All N sections
/// kept · M edits applied". Surfaced just above the save bar so the user can
/// see, before saving, that nothing was dropped.
class _PreservationNote extends StatelessWidget {
  const _PreservationNote({
    required this.sectionCount,
    required this.appliedCount,
  });

  final int sectionCount;
  final int appliedCount;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final sections =
        '$sectionCount section${sectionCount == 1 ? '' : 's'} kept';
    final label = appliedCount > 0
        ? 'All $sections · $appliedCount edit${appliedCount == 1 ? '' : 's'} applied'
        : 'All $sections';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: brand.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 14, color: brand.success),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: brand.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

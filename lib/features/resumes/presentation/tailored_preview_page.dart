import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../core/theme/brand_theme.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../agent_chat/state/agent_chat_notifier.dart';

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

    return Scaffold(
      backgroundColor: brand.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  AppBackButton(onPressed: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tailored resume',
                          style: TextStyle(
                            color: brand.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          isSaved
                              ? 'Saved to your resumes'
                              : 'Preview · not saved yet',
                          style: TextStyle(
                            color: isSaved ? brand.success : brand.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: brand.shadow,
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
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
                          ),
                  ),
                ),
              ),
            ),
            _ActionBar(
              isSaved: isSaved,
              saving: _saving,
              onSave: _save,
              onKeepEditing: _keepEditing,
              onDone: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
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
    final brand = context.brand;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: brand.surface,
        border: Border(top: BorderSide(color: brand.border)),
      ),
      child: isSaved
          ? _BarButton(
              label: 'Done',
              filled: true,
              onTap: onDone,
            )
          : Row(
              children: [
                Expanded(
                  child: _BarButton(
                    label: 'Keep editing',
                    filled: false,
                    onTap: saving ? null : onKeepEditing,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BarButton(
                    label: 'Save to my resumes',
                    filled: true,
                    loading: saving,
                    onTap: saving ? null : onSave,
                  ),
                ),
              ],
            ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
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
    final bg = filled ? brand.ink : Colors.transparent;
    final fg = filled ? brand.inkInverse : brand.ink;
    return Opacity(
      opacity: onTap == null && !loading ? 0.5 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
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
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../../../data/models/tracked_application.dart';
import '../../../../shared/widgets/app_back_button.dart';
import '../../state/applications_notifier.dart';

class ApplicationDetailSheet extends ConsumerStatefulWidget {
  const ApplicationDetailSheet._({required this.application});

  final TrackedApplication application;

  static Future<void> show(BuildContext context, TrackedApplication app) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ApplicationDetailSheet._(application: app),
    );
  }

  @override
  ConsumerState<ApplicationDetailSheet> createState() =>
      _ApplicationDetailSheetState();
}

class _ApplicationDetailSheetState
    extends ConsumerState<ApplicationDetailSheet> {
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submitNote(ApplicationsNotifier notifier) {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty) return;
    notifier.addNote(widget.application.id, text);
    _noteCtrl.clear();
    FocusScope.of(context).unfocus();
  }

  Future<void> _editNote(
    ApplicationsNotifier notifier,
    TrackedApplicationNote note,
  ) async {
    final controller = TextEditingController(text: note.body);

    try {
      final next = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Edit note'),
            content: TextField(
              controller: controller,
              autofocus: true,
              minLines: 1,
              maxLines: 5,
              decoration: const InputDecoration(hintText: 'Note'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      if (next == null) return;
      await notifier.updateNote(widget.application.id, note.id, next);
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final state = ref.watch(applicationsProvider);
    final notifier = ref.read(applicationsProvider.notifier);
    final app = state.items.firstWhere(
      (a) => a.id == widget.application.id,
      orElse: () => widget.application,
    );
    final viewport = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: viewport.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: brand.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: 24 + viewport.padding.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: brand.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const AppBackButton(),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.job.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: brand.ink,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${app.job.company} · ${app.job.location}',
                          style: TextStyle(
                            fontSize: 13,
                            color: brand.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _PhaseChip(phase: app.phase),
                ],
              ),
              const SizedBox(height: 22),
              const _SectionHeader(label: 'TIMELINE'),
              const SizedBox(height: 10),
              _Timeline(app: app),
              const SizedBox(height: 22),
              const _SectionHeader(label: 'STATUS'),
              const SizedBox(height: 10),
              _StatusControls(
                app: app,
                onMarkSent: () => notifier.markSent(app.id),
                onToggleReply: (v) => notifier.setGotReply(app.id, v),
              ),
              const SizedBox(height: 22),
              const _SectionHeader(label: 'NOTES'),
              const SizedBox(height: 10),
              _NoteComposer(
                controller: _noteCtrl,
                onSubmit: () => _submitNote(notifier),
              ),
              if (app.notes.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'No notes yet. Add reminders or interview prep here.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: brand.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else ...[
                const SizedBox(height: 10),
                for (final note in app.notes)
                  _NoteRow(
                    note: note,
                    onEdit: () => _editNote(notifier, note),
                    onDelete: () => notifier.deleteNote(app.id, note.id),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.phase});

  final ApplicationPhase phase;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final (bg, fg) = switch (phase) {
      ApplicationPhase.draft => (brand.surfaceMuted, brand.ink),
      ApplicationPhase.sent => (brand.ink, brand.accent),
      ApplicationPhase.replied => (brand.accent, brand.onAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: phase == ApplicationPhase.draft
              ? brand.border
              : Colors.transparent,
        ),
      ),
      child: Text(
        phase.label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: fg,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
        color: brand.ink.withValues(alpha: 0.7),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.app});

  final TrackedApplication app;

  String _fmt(DateTime when) => DateFormat('MMM d · h:mm a').format(when);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final events = <(String, String)>[
      ('Drafted', _fmt(app.draftedAt)),
      if (app.sentAt != null) ('Sent', _fmt(app.sentAt!)),
      if (app.gotReply) ('Reply received', 'You marked this manually'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, time) in events)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: brand.accentBright,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: brand.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    time,
                    style: TextStyle(
                      fontSize: 12,
                      color: brand.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatusControls extends StatelessWidget {
  const _StatusControls({
    required this.app,
    required this.onMarkSent,
    required this.onToggleReply,
  });

  final TrackedApplication app;
  final VoidCallback onMarkSent;
  final ValueChanged<bool> onToggleReply;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      children: [
        if (app.sentAt == null)
          _ActionRow(
            label: 'Mark as sent',
            description: 'Flips sent_at to now. Use after you submit manually.',
            trailing: Material(
              color: brand.ink,
              borderRadius: BorderRadius.circular(99),
              child: InkWell(
                onTap: onMarkSent,
                borderRadius: BorderRadius.circular(99),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Text(
                    'Mark sent',
                    style: TextStyle(
                      color: brand.inkInverse,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        _ActionRow(
          label: 'Got a reply',
          description: 'No inbox access — flip this when you hear back.',
          trailing: Switch.adaptive(
            value: app.gotReply,
            onChanged: onToggleReply,
            activeThumbColor: brand.onAccent,
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.description,
    required this.trailing,
  });

  final String label;
  final String description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: brand.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: brand.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class _NoteComposer extends StatelessWidget {
  const _NoteComposer({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: 'Add a note',
                hintStyle: TextStyle(
                  color: brand.textSoft,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              style: TextStyle(
                fontSize: 13,
                color: brand.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Add note',
            onPressed: onSubmit,
            icon: Icon(Icons.send_rounded, size: 18, color: brand.ink),
          ),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    required this.onEdit,
    required this.onDelete,
  });

  final TrackedApplicationNote note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final fmt = DateFormat('MMM d · h:mm a').format(note.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: brand.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  note.body,
                  style: TextStyle(
                    fontSize: 13,
                    color: brand.ink,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit note',
                onPressed: onEdit,
                icon: Icon(
                  Icons.edit_rounded,
                  size: 16,
                  color: brand.textMuted,
                ),
              ),
              IconButton(
                tooltip: 'Delete note',
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                  color: brand.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            fmt,
            style: TextStyle(
              fontSize: 11,
              color: brand.textSoft,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

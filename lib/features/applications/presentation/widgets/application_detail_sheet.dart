import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/models/tracked_application.dart';
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

class _ApplicationDetailSheetState extends ConsumerState<ApplicationDetailSheet> {
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

  @override
  Widget build(BuildContext context) {
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
        decoration: const BoxDecoration(
          color: AppColors.scaffold,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                app.job.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${app.job.company} · ${app.job.location}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              const _SectionHeader(label: 'TIMELINE'),
              const SizedBox(height: 10),
              _Timeline(app: app),
              const SizedBox(height: 20),
              const _SectionHeader(label: 'STATUS'),
              const SizedBox(height: 10),
              _StatusControls(
                app: app,
                onMarkSent: () => notifier.markSent(app.id),
                onToggleReply: (v) => notifier.setGotReply(app.id, v),
              ),
              const SizedBox(height: 20),
              const _SectionHeader(label: 'NOTES'),
              const SizedBox(height: 10),
              _NoteComposer(
                controller: _noteCtrl,
                onSubmit: () => _submitNote(notifier),
              ),
              if (app.notes.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'No notes yet. Add reminders or interview prep here.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else ...[
                const SizedBox(height: 10),
                for (final note in app.notes) _NoteRow(note: note),
              ],
            ],
          ),
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
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
        color: AppColors.ink.withValues(alpha: 0.7),
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
                  decoration: const BoxDecoration(
                    color: AppColors.accentBright,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    time,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
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
    return Column(
      children: [
        if (app.sentAt == null)
          _ActionRow(
            label: 'Mark as sent',
            description: 'Flips sent_at to now. Use after you submit manually.',
            trailing: Material(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(99),
              child: InkWell(
                onTap: onMarkSent,
                borderRadius: BorderRadius.circular(99),
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    'Mark sent',
                    style: TextStyle(
                      color: Colors.white,
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
            activeThumbColor: AppColors.ink,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
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
              decoration: const InputDecoration(
                hintText: 'Add a note',
                hintStyle: TextStyle(
                  color: AppColors.textSoft,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Add note',
            onPressed: onSubmit,
            icon: const Icon(Icons.send_rounded,
                size: 18, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note});

  final TrackedApplicationNote note;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d · h:mm a').format(note.createdAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.body,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.ink,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fmt,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSoft,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

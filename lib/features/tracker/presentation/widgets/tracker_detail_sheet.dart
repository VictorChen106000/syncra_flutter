import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/mock/mock_tracked_applications.dart';
import '../../../../data/models/job.dart';
import '../../state/tracker_controller.dart';

class TrackerDetailSheet extends StatefulWidget {
  const TrackerDetailSheet._({required this.application});

  final TrackedApplication application;

  static Future<void> show(BuildContext context, TrackedApplication app) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TrackerDetailSheet._(application: app),
    );
  }

  @override
  State<TrackerDetailSheet> createState() => _TrackerDetailSheetState();
}

class _TrackerDetailSheetState extends State<TrackerDetailSheet> {
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submitNote(TrackerController controller) {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty) return;
    controller.addNote(widget.application.job.id, text);
    _noteCtrl.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TrackerController>(
      builder: (context, controller, _) {
        // Use the latest snapshot from the controller so the sheet reflects
        // status/note updates without dismissing.
        final app = controller.items.firstWhere(
          (a) => a.job.id == widget.application.job.id,
          orElse: () => widget.application,
        );
        final viewport = MediaQuery.of(context);
        return Padding(
          padding: EdgeInsets.only(bottom: viewport.viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.scaffold,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(28)),
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
                  _SectionHeader(label: 'STATUS'),
                  const SizedBox(height: 10),
                  _StatusPicker(
                    current: app.status,
                    onChanged: (s) => controller.updateStatus(app.job.id, s),
                  ),
                  const SizedBox(height: 20),
                  _SectionHeader(label: 'NOTES'),
                  const SizedBox(height: 10),
                  _NoteComposer(
                    controller: _noteCtrl,
                    onSubmit: () => _submitNote(controller),
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
                    for (final note in app.notes)
                      _NoteRow(note: note),
                  ],
                ],
              ),
            ),
          ),
        );
      },
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

class _StatusPicker extends StatelessWidget {
  const _StatusPicker({required this.current, required this.onChanged});

  final JobStatus current;
  final ValueChanged<JobStatus> onChanged;

  static const _statuses = [
    JobStatus.submitted,
    JobStatus.viewed,
    JobStatus.replied,
    JobStatus.interview,
    JobStatus.offer,
    JobStatus.rejected,
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final status in _statuses)
          _StatusChip(
            label: status.label,
            active: current == status,
            danger: status == JobStatus.rejected,
            onTap: () => onChanged(status),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.active,
    required this.danger,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? (danger ? AppColors.danger : AppColors.ink)
        : AppColors.surface;
    final fg = active
        ? Colors.white
        : (danger ? AppColors.danger : AppColors.ink);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: active
                  ? Colors.transparent
                  : (danger ? AppColors.danger : AppColors.border),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ),
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

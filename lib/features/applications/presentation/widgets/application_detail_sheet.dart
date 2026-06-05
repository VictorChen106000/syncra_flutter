import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../../../data/models/tracked_application.dart';
import '../../../auth/models/user_profile.dart';
import '../../../auth/state/user_profile_notifier.dart';
import '../../services/application_bundle_summary.dart';
import '../../services/auto_apply_eligibility.dart';
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

int _sentTodayCount(List<TrackedApplication> apps) {
  final now = DateTime.now();

  return apps.where((app) {
    final sentAt = app.sentAt;
    if (sentAt == null) return false;

    return sentAt.year == now.year &&
        sentAt.month == now.month &&
        sentAt.day == now.day;
  }).length;
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

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final state = ref.watch(applicationsProvider);
    final notifier = ref.read(applicationsProvider.notifier);
    final app = state.items.firstWhere(
      (a) => a.id == widget.application.id,
      orElse: () => widget.application,
    );
    final profile = ref.watch(userProfileProvider);
    final autoApplySettings =
        profile?.autoApplySettings ?? const AutoApplySettings();
    final autoApplySentToday = _sentTodayCount(state.items);
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
              const SizedBox(height: 16),
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
              const SizedBox(height: 20),
              const _SectionHeader(label: 'TIMELINE'),
              const SizedBox(height: 10),
              _Timeline(app: app),
              const SizedBox(height: 20),
              const _SectionHeader(label: 'APPLICATION BUNDLE'),
              const SizedBox(height: 10),
              _BundlePanel(app: app),
              const SizedBox(height: 20),
              const _SectionHeader(label: 'BOUNDED AUTO-APPLY'),
              const SizedBox(height: 10),
              _AutoApplyPanel(
                app: app,
                settings: autoApplySettings,
                sentToday: autoApplySentToday,
              ),
              const SizedBox(height: 20),
              const _SectionHeader(label: 'TRUST GUARD'),
              const SizedBox(height: 10),
              _TrustGuardPanel(app: app),
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

class _BundlePanel extends StatelessWidget {
  const _BundlePanel({required this.app});

  final TrackedApplication app;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final bundle = evaluateApplicationBundle(app);
    final statusColor = bundle.hasBlocker
        ? brand.warning
        : bundle.completeCount == bundle.totalCount
        ? brand.success
        : brand.textMuted;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: brand.surfaceMuted.withValues(alpha: brand.isDark ? 0.72 : 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: brand.border.withValues(alpha: 0.72)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 17, color: brand.ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bundle readiness',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: brand.ink,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              Text(
                '${bundle.completeCount}/${bundle.totalCount} · ${bundle.statusLabel}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: statusColor,
                  letterSpacing: -0.05,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in bundle.items) _BundleItemRow(item: item),
        ],
      ),
    );
  }
}

class _BundleItemRow extends StatelessWidget {
  const _BundleItemRow({required this.item});

  final ApplicationBundleItem item;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = item.isBlocking
        ? brand.warning
        : item.isComplete
        ? brand.success
        : brand.textMuted;
    final icon = item.isBlocking
        ? Icons.error_outline_rounded
        : item.isComplete
        ? Icons.check_circle_rounded
        : Icons.radio_button_unchecked_rounded;

    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: brand.ink,
                    letterSpacing: -0.05,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.detail,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: brand.textMuted,
                    height: 1.3,
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

class _AutoApplyPanel extends StatelessWidget {
  const _AutoApplyPanel({
    required this.app,
    required this.settings,
    required this.sentToday,
  });

  final TrackedApplication app;
  final AutoApplySettings settings;
  final int sentToday;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final result = evaluateAutoApplyEligibility(
      app: app,
      settings: settings,
      sentToday: sentToday,
    );

    final color = result.isEligible
        ? brand.success
        : settings.enabled
        ? brand.warning
        : brand.textMuted;
    final icon = result.isEligible
        ? Icons.task_alt_rounded
        : settings.enabled
        ? Icons.rule_rounded
        : Icons.pause_circle_outline_rounded;
    final title = result.isEligible
        ? 'Eligible under your rules'
        : settings.enabled
        ? 'Blocked by your rules'
        : 'Auto-apply is off';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: brand.isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: brand.ink,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              Text(
                '$sentToday/${settings.maxDailyApplications} today',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: -0.05,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            result.statusLabel,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: brand.textMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _AutoApplyRuleChip(
                label: 'Min ${settings.minQualityScore}%',
                active: result.qualityScore >= settings.minQualityScore,
              ),
              _AutoApplyRuleChip(
                label: 'Quality ${result.qualityScore}%',
                active: result.qualityScore >= settings.minQualityScore,
              ),
              _AutoApplyRuleChip(
                label: settings.requireLowTrust
                    ? 'Low-risk only'
                    : 'Bundle decides',
                active:
                    !settings.requireLowTrust || app.trustRiskLevel == 'low',
              ),
            ],
          ),
          if (result.reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final reason in result.reasons.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 5, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reason,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: brand.textMuted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AutoApplyRuleChip extends StatelessWidget {
  const _AutoApplyRuleChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = active ? brand.success : brand.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: brand.isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: -0.05,
        ),
      ),
    );
  }
}

class _TrustGuardPanel extends StatelessWidget {
  const _TrustGuardPanel({required this.app});

  final TrackedApplication app;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = _trustRiskColor(app.trustRiskLevel, brand);
    final icon = _trustRiskIcon(app.trustRiskLevel);
    final label = app.trustRiskLabel.trim().isEmpty
        ? 'Not checked'
        : app.trustRiskLabel.trim();
    final safeNextStep = _trustSafeNextStep(app);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: brand.isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.34)),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Trust Guard · $label',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: brand.ink,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Quick red-flag screen only. This does not certify the job as legitimate.',
            style: TextStyle(
              fontSize: 12,
              color: brand.textMuted,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (app.trustSignals.isEmpty)
            _TrustEmptySignal(color: color, level: app.trustRiskLevel)
          else
            for (final signal in app.trustSignals) ...[
              _TrustSignalRow(signal: signal),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: brand.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: brand.border.withValues(alpha: 0.7)),
            ),
            child: Text(
              safeNextStep,
              style: TextStyle(
                fontSize: 12.2,
                color: brand.ink,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustEmptySignal extends StatelessWidget {
  const _TrustEmptySignal({required this.color, required this.level});

  final Color color;
  final String level;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final text = level == 'unchecked'
        ? 'No Trust Guard result was saved for this application yet.'
        : 'No obvious red flags were found in the saved posting text.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: brand.isDark ? 0.15 : 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 16, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.2,
                color: brand.ink,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustSignalRow extends StatelessWidget {
  const _TrustSignalRow({required this.signal});

  final Map<String, String> signal;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final severity = signal['severity'] ?? 'medium';
    final color = _signalSeverityColor(severity, brand);
    final label = signal['label'] ?? 'Trust signal';
    final detail = signal['detail'] ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: brand.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: brand.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_signalSeverityLabel(severity)} · $label',
                  style: TextStyle(
                    fontSize: 12.4,
                    fontWeight: FontWeight.w900,
                    color: brand.ink,
                    height: 1.25,
                  ),
                ),
                if (detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: brand.textMuted,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _trustRiskColor(String level, BrandTheme brand) => switch (level) {
  'high' => brand.danger,
  'medium' => brand.warning,
  'low' => brand.success,
  _ => brand.textSoft,
};

IconData _trustRiskIcon(String level) => switch (level) {
  'high' => Icons.warning_amber_rounded,
  'medium' => Icons.verified_user_outlined,
  'low' => Icons.shield_outlined,
  _ => Icons.shield_outlined,
};

String _trustSafeNextStep(TrackedApplication app) {
  final saved = app.trustSafeNextStep.trim();
  if (saved.isNotEmpty) return saved;

  return switch (app.trustRiskLevel) {
    'high' =>
      'Do not send personal documents or payment. Verify the company and posting first.',
    'medium' =>
      'Verify the company site, recruiter identity, and application link before outreach.',
    'low' =>
      'No obvious red flags found. Still verify the official posting before applying.',
    _ =>
      'Run a Trust Guard check before sending personal documents or applying.',
  };
}

Color _signalSeverityColor(String severity, BrandTheme brand) =>
    switch (severity) {
      'high' => brand.danger,
      'medium' => brand.warning,
      _ => brand.textSoft,
    };

String _signalSeverityLabel(String severity) => switch (severity) {
  'high' => 'High',
  'medium' => 'Medium',
  _ => 'Note',
};

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
  const _NoteRow({required this.note});

  final TrackedApplicationNote note;

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
          Text(
            note.body,
            style: TextStyle(
              fontSize: 13,
              color: brand.ink,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
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

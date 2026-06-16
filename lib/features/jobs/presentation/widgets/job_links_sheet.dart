import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/brand_theme.dart';
import '../../../../core/utils/url_opener.dart';
import '../../../../data/models/job.dart';
import '../../../../data/models/tracked_application.dart';
import '../../../agent_chat/state/agent_chat_notifier.dart';
import '../../../applications/presentation/widgets/application_detail_sheet.dart';
import '../../../email/models/recipient_resolution.dart';
import '../../../email/services/recipient_resolver.dart';
import '../../../resumes/models/resume_file.dart';
import '../../../resumes/state/resume_notifier.dart';
import 'job_action_sheet.dart';

/// The application-link-first action modal. Tapping a handled/history job card's
/// link/resume/email icons opens this one-column sheet with four rows:
///
///   1. Application/source links extracted from JSearch (the headline result).
///   2. Email outreach — recipient/demo state + the shared draft-email flow.
///   3. Tailored resume — open the saved resume when one is linked.
///   4. A chatbot prompt bar that opens this job's chat thread with context.
///
/// Email is intentionally *secondary* to the link row: the visible win is now an
/// "Open application" path, not just a draft. [application] is optional — when
/// present it powers the resume row and a shortcut to the record's notes.
class JobLinksSheet {
  const JobLinksSheet._();

  static Future<void> show(
    BuildContext context,
    Job job, {
    TrackedApplication? application,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Above the shell's floating bottom nav, matching ApplicationDetailSheet.
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JobLinksSheetBody(job: job, application: application),
    );
  }
}

class _JobLinksSheetBody extends ConsumerWidget {
  const _JobLinksSheetBody({required this.job, this.application});

  final Job job;
  final TrackedApplication? application;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
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
          bottom: 20 + viewport.padding.bottom,
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
                job.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: brand.ink,
                  letterSpacing: -0.3,
                ),
              ),
              if (_companyLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _companyLine,
                  style: TextStyle(
                    fontSize: 13,
                    color: brand.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              _ApplicationLinksRow(job: job),
              const SizedBox(height: 22),
              _EmailRow(job: job),
              const SizedBox(height: 22),
              _ResumeRow(job: job, application: application),
              const SizedBox(height: 22),
              _ChatPromptBar(job: job),
              if (application != null) ...[
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      ApplicationDetailSheet.show(context, application!);
                    },
                    icon: Icon(
                      Icons.sticky_note_2_outlined,
                      size: 16,
                      color: brand.textMuted,
                    ),
                    label: Text(
                      'Notes & status',
                      style: TextStyle(
                        color: brand.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _companyLine {
    final location = job.location.trim();
    if (location.isEmpty) return job.company;
    return '${job.company} · $location';
  }
}

// ---------------------------------------------------------------------------
// Row 1 — Application / source links (the primary result).
// ---------------------------------------------------------------------------

class _ApplicationLinksRow extends StatelessWidget {
  const _ApplicationLinksRow({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    // Build the link list in priority order, skipping empties / non-http links
    // and deduping so "View source" only shows when sourceUrl is genuinely a
    // third URL distinct from the apply and Google links.
    final seen = <String>{};
    final buttons = <Widget>[];

    void add(String url, String label, IconData icon, {bool primary = false}) {
      final clean = url.trim();
      if (clean.isEmpty || !UrlOpener.canOpen(clean)) return;
      if (!seen.add(clean.toLowerCase())) return;
      buttons.add(
        _LinkButton(
          label: label,
          icon: icon,
          primary: primary,
          onTap: () => _open(context, clean),
        ),
      );
    }

    add(
      job.applyLink,
      'Open application',
      Icons.open_in_new_rounded,
      primary: true,
    );
    add(job.googleJobLink, 'View Google listing', Icons.travel_explore_rounded);
    add(job.sourceUrl, 'View source', Icons.link_rounded);
    add(job.employerWebsite, 'Company website', Icons.language_rounded);

    return _SheetSection(
      label: 'APPLICATION',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (buttons.isEmpty)
            Text(
              'No application link available for this role.',
              style: TextStyle(
                fontSize: 13,
                color: brand.textMuted,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              buttons[i],
            ],
          if (job.publisher.trim().isNotEmpty ||
              job.providerSource.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _provenance,
              style: TextStyle(
                fontSize: 11.5,
                color: brand.textSoft,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _provenance {
    final parts = <String>[];
    if (job.publisher.trim().isNotEmpty) {
      parts.add('Publisher: ${job.publisher.trim()}');
    }
    if (job.providerSource.trim().toLowerCase() == 'jsearch') {
      parts.add('Source: JSearch');
    }
    return parts.join('  ·  ');
  }
}

// ---------------------------------------------------------------------------
// Row 2 — Email outreach (secondary).
// ---------------------------------------------------------------------------

class _EmailRow extends ConsumerWidget {
  const _EmailRow({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    return _SheetSection(
      label: 'EMAIL · OPTIONAL',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<RecipientResolution>(
            future: resolveRecipientAsync(
              job.company,
              website: job.employerWebsite,
              applyLink: job.applyLink,
            ),
            builder: (context, snap) {
              final resolution = snap.data;
              final text = switch (resolution) {
                null => 'Resolving recipient…',
                _ when resolution.email.trim().isEmpty =>
                  'No verified recipient yet. Email is optional.',
                _ => _recipientLine(resolution),
              };
              return Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: brand.textMuted,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          _LinkButton(
            label: 'Draft email',
            icon: Icons.drafts_outlined,
            primary: false,
            onTap: () {
              Navigator.of(context).pop();
              draftJobEmail(context, ref, job);
            },
          ),
        ],
      ),
    );
  }

  String _recipientLine(RecipientResolution resolution) {
    final email = resolution.email.trim();
    return resolution.source == RecipientSource.demoOverride
        ? 'Demo recipient · $email'
        : 'Recipient · $email';
  }
}

// ---------------------------------------------------------------------------
// Row 3 — Tailored resume.
// ---------------------------------------------------------------------------

class _ResumeRow extends ConsumerWidget {
  const _ResumeRow({required this.job, this.application});

  final Job job;
  final TrackedApplication? application;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final resumeId = application?.resumeId;
    final ResumeFile? resume = resumeId == null
        ? null
        : ref
              .watch(resumeProvider)
              .allResumes
              .where((r) => r.id == resumeId)
              .firstOrNull;

    return _SheetSection(
      label: 'RESUME',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            resume != null
                ? 'Tailored resume ready for this role.'
                : 'No tailored resume saved yet.',
            style: TextStyle(
              fontSize: 13,
              color: brand.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          if (resume != null)
            _LinkButton(
              label: 'Open resume',
              icon: Icons.description_outlined,
              primary: false,
              onTap: () {
                Navigator.of(context).pop();
                context.go(RouteNames.resumePreview, extra: resume);
              },
            )
          else
            _LinkButton(
              label: 'Tailor resume in chat',
              icon: Icons.auto_fix_high_rounded,
              primary: false,
              onTap: () => _openThread(context, ref, job),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row 4 — Chatbot prompt bar.
// ---------------------------------------------------------------------------

class _ChatPromptBar extends ConsumerWidget {
  const _ChatPromptBar({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    return _SheetSection(
      label: 'ASK SYNCRA',
      child: Material(
        color: brand.ink,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _openThread(context, ref, job),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ask Syncra about this application…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: brand.inkInverse.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: brand.accent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 19,
                    color: brand.onAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens (or continues) this job's chat thread with a prefilled contextual
/// prompt seeded into the composer — nothing sends until the user taps Send.
void _openThread(BuildContext context, WidgetRef ref, Job job) {
  ref.read(composerDraftProvider.notifier).state = _contextPrompt(job);
  ref.read(agentChatProvider.notifier).openJobThread(job);
  Navigator.of(context).pop();
  context.go('${RouteNames.agentChat}?focus=1');
}

String _contextPrompt(Job job) {
  final link = job.applyLink.trim().isNotEmpty
      ? job.applyLink.trim()
      : job.sourceUrl.trim();
  final lines = <String>[
    'Continue helping me with this application:',
    'Role: ${job.title}',
    'Company: ${job.company}',
    if (job.location.trim().isNotEmpty) 'Location: ${job.location.trim()}',
    if (link.isNotEmpty) 'Application link: $link',
    if (job.publisher.trim().isNotEmpty) 'Publisher: ${job.publisher.trim()}',
    'Please help me decide the next step, improve my resume, or prepare outreach.',
  ];
  return lines.join('\n');
}

/// Opens [url] in the browser, surfacing a snackbar when it can't be opened.
Future<void> _open(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await UrlOpener.open(url);
  if (!ok) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't open that link.")),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits.
// ---------------------------------------------------------------------------

class _SheetSection extends StatelessWidget {
  const _SheetSection({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            color: brand.ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

/// A full-width action pill. [primary] fills it with the lime accent (used once,
/// for "Open application"); the rest are quiet outlined controls.
class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final bg = primary ? brand.accent : brand.surface;
    final fg = primary ? brand.onAccent : brand.ink;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: primary ? brand.accent : brand.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

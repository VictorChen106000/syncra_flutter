import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/brand_theme.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../agent_chat/models/agent_block.dart';
import '../../agent_chat/state/agent_chat_notifier.dart';
import '../models/proposed_edit.dart';
import '../models/resume_integrity_result.dart';
import '../models/resume_json.dart';

// Resume "paper" is always dark-ink-on-white — a resume reads the same in light
// or dark mode — so these are fixed, not brand tokens.
const Color _ink = Color(0xFF1B1B1B);
const Color _muted = Color(0xFF5E5E5E);
const Color _rule = Color(0xFFE0E0E0);
const Color _changeInk = Color(0xFF12612F);
const Color _changeWash = Color(0x2219A55A); // ~13% green highlighter
const Color _changeBorder = Color(0xFF1AA35A);
const Color _oldInk = Color(0xFF9A9A9A);

/// Full-screen review of a freshly tailored resume, shown as the **live**
/// document (not a flat PDF) so the lines the tailor changed can glow green
/// right where they live. Tapping a highlight reveals the original line it
/// replaced and the reason for the change.
///
/// Reads its [ProposedEditsBlock] reactively by [blockId]; the bottom bar saves
/// the rendered PDF to the library ([AgentChatNotifier.savePreviewedResume]) or
/// returns to the chat to keep editing.
class TailoredChangesPage extends ConsumerStatefulWidget {
  const TailoredChangesPage({super.key, required this.blockId});

  final String blockId;

  @override
  ConsumerState<TailoredChangesPage> createState() =>
      _TailoredChangesPageState();
}

class _TailoredChangesPageState extends ConsumerState<TailoredChangesPage> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(agentChatProvider.notifier)
        .savePreviewedResume(widget.blockId);
    if (!mounted) return;
    setState(() => _saving = false);

    final block = ref
        .read(agentChatProvider.notifier)
        .proposedEditsBlock(widget.blockId);
    final messenger = ScaffoldMessenger.of(context);
    if (block != null && block.isSaved) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Saved to your resumes')));
      Navigator.of(context).maybePop();
    } else if (block?.applyError != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(block!.applyError!)));
    }
  }

  void _keepEditing() {
    final started = ref
        .read(agentChatProvider.notifier)
        .requestTailoredResumeRevision(widget.blockId);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).maybePop();
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            started
                ? 'Syncra is preparing a tailored revision.'
                : 'Syncra is already working. Try again in a moment.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    // Watch chat state so a save elsewhere reflects here too.
    ref.watch(agentChatProvider);
    final block = ref
        .read(agentChatProvider.notifier)
        .proposedEditsBlock(widget.blockId);
    final resume = block?.previewResume;
    final isSaved = block?.isSaved ?? false;
    final integrity = block?.integrity;
    final autoRepairing = block?.integrityAutoRepairing ?? false;
    final canSave = (integrity?.canSave ?? true) && !autoRepairing;
    final canKeepEditing = !autoRepairing;
    final keepEditingLabel =
        integrity != null && integrity.status != ResumeIntegrityStatus.verified
        ? 'Fix with Syncra'
        : 'Keep editing';

    // The set of changed leaves, keyed by the canonicalized proposed text. A
    // skipped edit's text never lands in [previewResume], so it simply won't
    // match — no false highlight.
    final changes = <String, ProposedEdit>{
      if (block != null)
        for (final e in block.edits)
          if (e.proposedText.trim().isNotEmpty) _canon(e.proposedText): e,
    };
    final improvements = (block?.appliedCount ?? 0) > 0
        ? block!.appliedCount
        : changes.length;

    return Scaffold(
      backgroundColor: brand.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(isSaved: isSaved, improvements: improvements),
            if (block != null && integrity != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _IntegrityBanner(block: block),
              ),
            ],
            Expanded(
              child: resume == null
                  ? _Rendering(brand: brand)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      child: _ResumePaper(resume: resume, changes: changes),
                    ),
            ),
            _ActionBar(
              isSaved: isSaved,
              saving: _saving,
              canSave: canSave,
              canKeepEditing: canKeepEditing,
              keepEditingLabel: keepEditingLabel,
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

class _Header extends StatelessWidget {
  const _Header({required this.isSaved, required this.improvements});

  final bool isSaved;
  final int improvements;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final sub = isSaved
        ? 'Saved to your resumes'
        : improvements == 0
        ? 'No changes were needed'
        : '$improvements improvement${improvements == 1 ? '' : 's'} · '
              'tap a highlight to see the original';
    return Padding(
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
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
    );
  }
}

class _Rendering extends StatelessWidget {
  const _Rendering({required this.brand});
  final BrandTheme brand;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 14),
          Text(
            'Rendering your resume…',
            style: TextStyle(
              color: brand.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntegrityBanner extends StatelessWidget {
  const _IntegrityBanner({required this.block});

  final ProposedEditsBlock block;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final result = block.integrity!;
    final repaired = block.integrityRepairAttempted;
    final (icon, color, text) = block.supersededByBlockId != null
        ? (
            Icons.auto_awesome_rounded,
            brand.success,
            'A safer revision is ready in chat.',
          )
        : block.integrityAutoRepairing
        ? (
            Icons.autorenew_rounded,
            brand.warning,
            'Integrity check found issues — Syncra is repairing this automatically.',
          )
        : switch (result.status) {
            ResumeIntegrityStatus.verified => (
              Icons.verified_rounded,
              brand.success,
              'Integrity verified — accepted edits landed and original facts were preserved.',
            ),
            ResumeIntegrityStatus.needsReview => (
              Icons.warning_amber_rounded,
              brand.warning,
              repaired
                  ? 'Needs review — Syncra tried one safer pass. Review carefully before saving.'
                  : 'Needs review — Syncra found possible unsupported claims. Review before saving.',
            ),
            ResumeIntegrityStatus.blocked => (
              Icons.block_rounded,
              brand.danger,
              repaired
                  ? 'Blocked — Syncra could not safely repair this. Saving is disabled.'
                  : 'Blocked — Syncra found a serious integrity issue. Saving is disabled.',
            ),
          };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: brand.ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The live resume document
// ---------------------------------------------------------------------------

/// Renders [resume] as a white "paper" card, mirroring the PDF template's
/// section order (Summary → Education → Experience → Projects → Achievements →
/// Skills). Any leaf whose text is in [changes] glows and becomes tappable.
class _ResumePaper extends StatelessWidget {
  const _ResumePaper({required this.resume, required this.changes});

  final ResumeJson resume;
  final Map<String, ProposedEdit> changes;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final h = resume.header;
    final contacts = [
      h.email,
      h.phone,
      h.location,
      h.linkedin,
      h.website,
      h.github,
      h.twitter,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join('   ·   ');

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: brand.shadow,
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              h.name.isEmpty ? 'Your Resume' : h.name,
              style: _serif(size: 23, w: FontWeight.w700, h: 1.1),
            ),
            if (contacts.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(contacts, style: _serif(size: 11, color: _muted, h: 1.4)),
            ],
            ..._sections(),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections() {
    final out = <Widget>[];

    if ((resume.summary ?? '').trim().isNotEmpty) {
      out.add(
        _section('Summary', [
          _leaf(resume.summary!.trim(), _serif(size: 12.5, h: 1.5), changes),
        ]),
      );
    }

    if (resume.education.isNotEmpty) {
      out.add(
        _section('Education', [
          for (final e in resume.education) _educationEntry(e),
        ]),
      );
    }

    if (resume.experience.isNotEmpty) {
      out.add(
        _section('Experience', [
          for (final e in resume.experience) _experienceEntry(e),
        ]),
      );
    }

    if (resume.projects.isNotEmpty) {
      out.add(
        _section('Projects', [
          for (final p in resume.projects) _projectEntry(p),
        ]),
      );
    }

    if (resume.certifications.isNotEmpty) {
      out.add(
        _section('Achievements & Certifications', [
          for (final c in resume.certifications) _certificationEntry(c),
        ]),
      );
    }

    final skills = _skillsBlock();
    if (skills != null) out.add(_section('Skills', [skills]));

    return out;
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          title.toUpperCase(),
          style: _serif(size: 12, w: FontWeight.w600, ls: 1.4),
        ),
        const SizedBox(height: 5),
        Container(height: 1, color: _rule),
        const SizedBox(height: 9),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 13),
          children[i],
        ],
      ],
    );
  }

  Widget _experienceEntry(ResumeExperience e) {
    final end = (e.end ?? '').isEmpty ? 'Present' : e.end!;
    final dates = e.start.isEmpty ? '' : '${e.start} – $end';
    final subtitle = [
      e.role,
      if ((e.location ?? '').isNotEmpty) e.location!,
    ].where((s) => s.isNotEmpty).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titleDateRow(e.company, dates),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: _serif(size: 11.5, color: _muted, style: FontStyle.italic),
          ),
        ],
        ..._bullets(e.bullets),
      ],
    );
  }

  Widget _educationEntry(ResumeEducation e) {
    final dates = [
      e.start,
      e.end,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' – ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titleDateRow(e.school, dates),
        if (e.degree.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            e.degree,
            style: _serif(size: 11.5, color: _muted, style: FontStyle.italic),
          ),
        ],
        if ((e.details ?? '').isNotEmpty) ...[
          const SizedBox(height: 3),
          _leaf(e.details!.trim(), _serif(size: 12, h: 1.45), changes),
        ],
        ..._bullets(e.bullets),
      ],
    );
  }

  Widget _projectEntry(ResumeProject p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titleDateRow(p.name, p.date ?? ''),
        if ((p.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 3),
          _leaf(
            p.description!.trim(),
            _serif(size: 12, color: _muted, style: FontStyle.italic, h: 1.4),
            changes,
          ),
        ],
        ..._bullets(p.bullets),
        if ((p.link ?? '').isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            p.link!,
            style: _serif(
              size: 11,
              color: _muted,
            ).copyWith(decoration: TextDecoration.underline),
          ),
        ],
      ],
    );
  }

  Widget _certificationEntry(ResumeCertification c) {
    final issuer = (c.issuer ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: _serif(size: 13, w: FontWeight.w700),
                  children: [
                    TextSpan(text: c.name),
                    if (issuer.isNotEmpty)
                      TextSpan(
                        text: ' – $issuer',
                        style: _serif(size: 12.5, w: FontWeight.w400),
                      ),
                  ],
                ),
              ),
            ),
            if ((c.date ?? '').isNotEmpty)
              Text(
                c.date!,
                style: _serif(
                  size: 10.5,
                  color: _muted,
                  style: FontStyle.italic,
                ),
              ),
          ],
        ),
        ..._bullets(c.bullets),
      ],
    );
  }

  Widget _titleDateRow(String title, String date) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(title, style: _serif(size: 13, w: FontWeight.w700)),
        ),
        if (date.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            date,
            style: _serif(size: 10.5, color: _muted, style: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  List<Widget> _bullets(List<String> bullets) {
    if (bullets.isEmpty) return const [];
    return [const SizedBox(height: 4), for (final b in bullets) _bulletRow(b)];
  }

  Widget _bulletRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 7, right: 9),
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: _ink,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(child: _leaf(text, _serif(size: 12.5, h: 1.45), changes)),
        ],
      ),
    );
  }

  /// Skills as one "Category: a, b, c" line per group. Changed/added items get
  /// an inline green highlighter via a [TextSpan] background — no per-item tap,
  /// since an added keyword is self-evident.
  Widget? _skillsBlock() {
    final groups = resume.skillGroups.where((g) => g.items.isNotEmpty).toList();
    final base = _serif(size: 12, h: 1.5);

    List<InlineSpan> itemsSpan(List<String> items) {
      final spans = <InlineSpan>[];
      for (var i = 0; i < items.length; i++) {
        final changed = changes.containsKey(_canon(items[i]));
        spans.add(
          TextSpan(
            text: items[i],
            style: changed
                ? base.copyWith(
                    color: _changeInk,
                    background: Paint()..color = _changeWash,
                  )
                : null,
          ),
        );
        if (i < items.length - 1) spans.add(const TextSpan(text: ', '));
      }
      return spans;
    }

    if (groups.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < groups.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
              child: RichText(
                text: TextSpan(
                  style: base,
                  children: [
                    if (groups[i].category.trim().isNotEmpty)
                      TextSpan(
                        text: '${groups[i].category.trim()}: ',
                        style: base.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ...itemsSpan(groups[i].items),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    if (resume.skills.isNotEmpty) {
      return RichText(
        text: TextSpan(style: base, children: itemsSpan(resume.skills)),
      );
    }
    return null;
  }
}

/// Returns a plain [Text] for an unchanged leaf, or a tappable [_ChangedText]
/// when [value] matches one of the tailor's proposed edits.
Widget _leaf(String value, TextStyle style, Map<String, ProposedEdit> changes) {
  final edit = changes[_canon(value)];
  if (edit == null) return Text(value, style: style);
  return _ChangedText(value: value, style: style, edit: edit);
}

/// A changed line: the new text on a green highlighter wash. Tapping it expands
/// a panel showing the original line it replaced (or an "added" note) plus the
/// reason the tailor gave for the change.
class _ChangedText extends StatefulWidget {
  const _ChangedText({
    required this.value,
    required this.style,
    required this.edit,
  });

  final String value;
  final TextStyle style;
  final ProposedEdit edit;

  @override
  State<_ChangedText> createState() => _ChangedTextState();
}

class _ChangedTextState extends State<_ChangedText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.edit;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: _changeWash,
              borderRadius: BorderRadius.circular(7),
              border: const Border(
                left: BorderSide(color: _changeBorder, width: 3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(widget.value, style: widget.style)),
                const SizedBox(width: 6),
                Icon(
                  _open
                      ? Icons.expand_less_rounded
                      : Icons.auto_awesome_rounded,
                  size: 14,
                  color: _changeBorder,
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _RevealPanel(edit: e),
            crossFadeState: _open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
          ),
        ],
      ),
    );
  }
}

class _RevealPanel extends StatelessWidget {
  const _RevealPanel({required this.edit});

  final ProposedEdit edit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 9, top: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (edit.isAdd)
            Row(
              children: [
                const Icon(
                  Icons.add_circle_outline_rounded,
                  size: 13,
                  color: _changeBorder,
                ),
                const SizedBox(width: 6),
                Text(
                  'Added for this role',
                  style: _serif(
                    size: 11.5,
                    color: _changeInk,
                    w: FontWeight.w600,
                  ),
                ),
              ],
            )
          else ...[
            Text(
              'WAS',
              style: _serif(
                size: 9.5,
                color: _oldInk,
                w: FontWeight.w700,
                ls: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              edit.originalText,
              style: _serif(size: 12, color: _oldInk, h: 1.4).copyWith(
                decoration: TextDecoration.lineThrough,
                decorationColor: _oldInk,
              ),
            ),
          ],
          if (edit.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            RichText(
              text: TextSpan(
                style: _serif(size: 11.5, color: _muted, h: 1.4),
                children: [
                  TextSpan(
                    text: 'Why  ',
                    style: _serif(
                      size: 9.5,
                      color: _muted,
                      w: FontWeight.w700,
                      ls: 1.0,
                    ),
                  ),
                  TextSpan(text: edit.reason.trim()),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.isSaved,
    required this.saving,
    required this.canSave,
    required this.canKeepEditing,
    required this.keepEditingLabel,
    required this.onSave,
    required this.onKeepEditing,
    required this.onDone,
  });

  final bool isSaved;
  final bool saving;
  final bool canSave;
  final bool canKeepEditing;
  final String keepEditingLabel;
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
          ? _BarButton(label: 'Done', filled: true, onTap: onDone)
          : Row(
              children: [
                Expanded(
                  child: _BarButton(
                    label: keepEditingLabel,
                    filled: false,
                    onTap: saving || !canKeepEditing ? null : onKeepEditing,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BarButton(
                    label: canSave ? 'Save to my resumes' : 'Save blocked',
                    filled: true,
                    loading: saving,
                    onTap: saving || !canSave ? null : onSave,
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
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
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

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/// Document serif used throughout the paper, so the live view reads like a real
/// resume rather than app chrome.
TextStyle _serif({
  double size = 12.5,
  FontWeight w = FontWeight.w400,
  Color color = _ink,
  FontStyle? style,
  double? ls,
  double h = 1.0,
}) => GoogleFonts.sourceSerif4(
  fontSize: size,
  fontWeight: w,
  color: color,
  fontStyle: style,
  letterSpacing: ls,
  height: h,
);

/// Mirrors [ResumeDiffService]'s canonicalization so a changed leaf in the
/// rendered resume matches the tailor's `proposed_text` despite cosmetic
/// differences (smart quotes/dashes, collapsed whitespace).
String _canon(String s) => s
    .replaceAll(RegExp(r'[‘’‛′]'), "'")
    .replaceAll(RegExp(r'[“”″]'), '"')
    .replaceAll(RegExp(r'[–—]'), '-')
    .replaceAll('…', '...')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

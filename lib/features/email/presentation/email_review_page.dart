import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/brand_theme.dart';
import '../models/recipient_resolution.dart';
import '../services/email_send_service.dart';
import '../services/gmail_service.dart';

/// Whether the review sheet sends the email outright or saves it as a Gmail
/// draft the user finishes from Gmail.
enum EmailReviewMode {
  /// Send immediately via `messages.send` (behind the confirmation token).
  send,

  /// Create a draft via `drafts.create`; nothing is delivered.
  draft,
}

/// What [EmailReviewPage.show] resolves to.
///
/// `null` from `show()` means the user dismissed the sheet without acting.
/// A non-null result means an action completed: [sent] is true when an email
/// was sent, [draftCreated] is true when a draft was saved.
class EmailReviewResult {
  const EmailReviewResult({
    this.sent = false,
    this.draftCreated = false,
    this.messageId,
    this.draftId,
    this.error,
  });

  final bool sent;
  final bool draftCreated;
  final String? messageId;
  final String? draftId;
  final String? error;
}

/// The send gate. A modal review sheet is the **only** path that can actually
/// fire `send_email` — it mints the one-shot confirmation token that
/// [EmailSendService] demands, so nothing leaves the device without the user
/// reading the draft and tapping Send (api-contract §1, §2.8).
///
/// Wiring handoff (R2 / Track A): when a `draft_email` tool result lands in
/// the chat, the draft block's "Review & send" action should call
/// [EmailReviewPage.show] with that draft's `recipient` / `subject` / `body`,
/// plus the tracker `applicationId` if one exists. This file does not reach
/// into the chat controller itself — that handoff is intentionally left to
/// the chat-block owner.
class EmailReviewPage extends StatefulWidget {
  const EmailReviewPage._({
    required this.initialRecipient,
    required this.initialSubject,
    required this.initialBody,
    required this.mode,
    this.applicationId,
    this.attachments = const [],
    this.contactDomain,
    this.company,
    this.recipientResolution,
  });

  /// Pre-filled "To" address. Editable — the company address is only ever a
  /// best-effort guess (see `recipient_resolver.dart`), so the user confirms
  /// or corrects it here before anything happens.
  final String initialRecipient;
  final String initialSubject;
  final String initialBody;

  /// Send the email outright, or save it as a Gmail draft.
  final EmailReviewMode mode;

  /// Tracker application to stamp `sent_at` / `sent_email_id` on success.
  final String? applicationId;

  /// Files to attach — typically the tailored resume PDF.
  final List<EmailAttachment> attachments;

  /// Company domain this outreach is keyed by (e.g. `acme.com`). When set, the
  /// confirmed "To" address is saved under it so the real recipient is reused
  /// next time (see `CompanyContactsRepository`). Falls back to the recipient's
  /// own domain when null.
  final String? contactDomain;

  /// Display company name, stored alongside a learned contact for context.
  final String? company;

  /// Recipient metadata shown in the review UI. Older callers may omit this;
  /// the sheet then treats the pre-filled recipient as a low-confidence guess.
  final RecipientResolution? recipientResolution;

  /// Opens the review sheet. Resolves to the [EmailReviewResult], or `null`
  /// if the user dismissed it without acting. Defaults to draft mode — the
  /// safe path that never delivers without a second tap inside Gmail.
  static Future<EmailReviewResult?> show(
    BuildContext context, {
    required String recipient,
    required String subject,
    required String body,
    EmailReviewMode mode = EmailReviewMode.draft,
    String? applicationId,
    List<EmailAttachment> attachments = const [],
    String? contactDomain,
    String? company,
    RecipientResolution? recipientResolution,
  }) {
    return showModalBottomSheet<EmailReviewResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmailReviewPage._(
        initialRecipient: recipient,
        initialSubject: subject,
        initialBody: body,
        mode: mode,
        applicationId: applicationId,
        attachments: attachments,
        contactDomain: contactDomain,
        company: company,
        recipientResolution: recipientResolution,
      ),
    );
  }

  @override
  State<EmailReviewPage> createState() => _EmailReviewPageState();
}

class _EmailReviewPageState extends State<EmailReviewPage> {
  late final TextEditingController _recipientCtrl = TextEditingController(
    text: widget.initialRecipient,
  );
  late final TextEditingController _subjectCtrl = TextEditingController(
    text: widget.initialSubject,
  );
  late final TextEditingController _bodyCtrl = TextEditingController(
    text: widget.initialBody,
  );

  bool _busy = false;
  bool _lowConfidenceAccepted = false;
  String? _error;

  /// The delivery choice the user can flip between in the sheet. Seeded from
  /// [EmailReviewPage.mode] (the caller's default) but no longer fixed — the
  /// "Save as draft / Send now" toggle drives it after review.
  late EmailReviewMode _mode = widget.mode;

  /// Set once a draft has been created so the button can't be tapped twice
  /// into a second duplicate draft.
  String? _draftId;
  bool get _isDraftMode => _mode == EmailReviewMode.draft;

  RecipientResolution get _effectiveResolution {
    final typed = _recipientCtrl.text.trim();
    final initial = widget.initialRecipient.trim();
    final domain = widget.contactDomain?.trim().toLowerCase();

    if (typed.isEmpty) {
      return RecipientResolution.none(domain: domain ?? '');
    }

    if (typed != initial) {
      return RecipientResolution.confirmed(
        email: typed,
        domain: _domainFromEmail(typed) ?? domain ?? '',
        source: RecipientSource.confirmedCache,
        reason: 'Recipient entered or replaced by the user.',
        canAutoSend: false,
      );
    }

    return widget.recipientResolution ??
        RecipientResolution.fromLegacyRecipient(typed, domain: domain);
  }

  bool get _recipientMissing => _recipientCtrl.text.trim().isEmpty;

  bool get _isLowConfidenceGuessedRecipient {
    final resolution = _effectiveResolution;
    return resolution.confidence == RecipientConfidence.low &&
        resolution.source == RecipientSource.guessedPattern;
  }

  bool _requiresLowConfidenceSendConfirmationFor(EmailReviewMode mode) {
    return mode == EmailReviewMode.send && _isLowConfidenceGuessedRecipient;
  }

  bool _canSubmitFor(EmailReviewMode mode) {
    return !_busy &&
        !_recipientMissing &&
        (!_requiresLowConfidenceSendConfirmationFor(mode) ||
            _lowConfidenceAccepted);
  }

  String get _reviewTitle {
    if (_draftId != null) {
      return 'Draft saved';
    }
    return _isDraftMode ? 'Review draft' : 'Review email';
  }

  String get _reviewDescription {
    if (_draftId != null) {
      return 'Saved to your Gmail Drafts. Open Gmail to review and send it yourself — nothing was delivered.';
    }

    if (!_isDraftMode) {
      return 'Nothing is sent until you tap Send — the agent never sends on its own.';
    }

    if (kIsWeb) {
      return 'This saves a draft to your Gmail Drafts. Google may ask for Gmail compose permission. Nothing is sent.';
    }

    return 'This saves a draft to your Gmail. Nothing is sent — you finish and send it from Gmail.';
  }

  bool get _recipientWasEdited =>
      _recipientCtrl.text.trim() != widget.initialRecipient.trim();

  bool get _shouldLearnRecipient {
    final resolution = _effectiveResolution;
    return _recipientWasEdited ||
        _lowConfidenceAccepted ||
        resolution.confidence == RecipientConfidence.confirmed ||
        resolution.confidence == RecipientConfidence.high;
  }

  @override
  void initState() {
    super.initState();
    _recipientCtrl.addListener(_handleRecipientChanged);
  }

  void _handleRecipientChanged() {
    if (!mounted) return;
    setState(() {
      _lowConfidenceAccepted = false;
      if (_error == 'Add a recipient address.') _error = null;
    });
  }

  @override
  void dispose() {
    _recipientCtrl.removeListener(_handleRecipientChanged);
    _recipientCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(EmailReviewMode mode) async {
    final recipient = _recipientCtrl.text.trim();
    final subject = _subjectCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (recipient.isEmpty) {
      setState(() => _error = 'Add a recipient address.');
      return;
    }
    if (_requiresLowConfidenceSendConfirmationFor(mode) &&
        !_lowConfidenceAccepted) {
      setState(
        () => _error =
            'Confirm this guessed recipient or replace it before sending.',
      );
      return;
    }
    if (subject.isEmpty || body.isEmpty) {
      setState(() => _error = 'Subject and message cannot be empty.');
      return;
    }

    setState(() {
      _mode = mode;
      _busy = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();

    try {
      if (mode == EmailReviewMode.draft) {
        await _createDraft(recipient: recipient, subject: subject, body: body);
      } else {
        await _sendEmail(recipient: recipient, subject: subject, body: body);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _createDraft({
    required String recipient,
    required String subject,
    required String body,
  }) async {
    final resolution = _effectiveResolution;
    final draftId = await EmailSendService.instance.createDraft(
      to: recipient,
      subject: subject,
      body: body,
      attachments: widget.attachments,
      contactDomain: resolution.domain.isNotEmpty
          ? resolution.domain
          : widget.contactDomain,
      company: widget.company,
      uid: FirebaseAuth.instance.currentUser?.uid,
      learnRecipient: _shouldLearnRecipient,
    );

    if (!mounted) return;

    // Show a settled "Draft created" state rather than popping instantly, so
    // the user gets confirmation and can't re-tap into a duplicate draft.
    setState(() {
      _busy = false;
      _draftId = draftId;
    });
  }

  Future<void> _sendEmail({
    required String recipient,
    required String subject,
    required String body,
  }) async {
    final resolution = _effectiveResolution;
    final service = EmailSendService.instance;
    // Minting the token here is what makes this the *only* legitimate send
    // path — the agent has no way to produce one.
    final token = service.mintConfirmationToken();
    final result = await service.sendConfirmed(
      confirmationToken: token,
      to: recipient,
      subject: subject,
      body: body,
      uid: FirebaseAuth.instance.currentUser?.uid,
      applicationId: widget.applicationId,
      attachments: widget.attachments,
      contactDomain: resolution.domain.isNotEmpty
          ? resolution.domain
          : widget.contactDomain,
      company: widget.company,
    );
    if (!mounted) return;
    Navigator.of(
      context,
    ).pop(EmailReviewResult(sent: true, messageId: result.messageId));
  }

  /// Turns a raw exception into one line a user can act on.
  String _friendlyError(Object e) {
    if (e is GmailException) return e.message;
    if (e is EmailNotConfirmedException) {
      return 'Confirmation expired. Tap Send again.';
    }
    if (_isDraftMode) {
      return "Couldn't save the draft. Check your connection and try again.";
    }
    return "Couldn't send the email. Check your connection and try again.";
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final viewport = MediaQuery.of(context);
    final resolution = _effectiveResolution;
    final warning = _recipientWarning(resolution);
    final showLowConfidenceCheckbox =
        _isLowConfidenceGuessedRecipient && _draftId == null;

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
                _reviewTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: brand.ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _reviewDescription,
                style: TextStyle(
                  fontSize: 12.5,
                  color: brand.textMuted,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const _FieldLabel('TO'),
                  const SizedBox(width: 8),
                  Flexible(child: _RecipientBadge(resolution: resolution)),
                ],
              ),
              const SizedBox(height: 8),
              _EditableField(
                controller: _recipientCtrl,
                hint: 'recipient@company.com',
                enabled: !_busy && _draftId == null,
                keyboardType: TextInputType.emailAddress,
              ),
              if (warning != null) ...[
                const SizedBox(height: 8),
                _RecipientWarning(message: warning),
              ],
              if (showLowConfidenceCheckbox) ...[
                const SizedBox(height: 8),
                _RecipientConfirmationCheckbox(
                  value: _lowConfidenceAccepted,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _lowConfidenceAccepted = value ?? false;
                          _error = null;
                        }),
                ),
              ],
              const SizedBox(height: 14),
              const _FieldLabel('SUBJECT'),
              const SizedBox(height: 8),
              _EditableField(
                controller: _subjectCtrl,
                hint: 'Subject line',
                enabled: !_busy && _draftId == null,
              ),
              const SizedBox(height: 14),
              const _FieldLabel('MESSAGE'),
              const SizedBox(height: 8),
              _EditableField(
                controller: _bodyCtrl,
                hint: 'Email body',
                enabled: !_busy && _draftId == null,
                minLines: 6,
                maxLines: 12,
              ),
              if (widget.attachments.isNotEmpty) ...[
                const SizedBox(height: 14),
                const _FieldLabel('ATTACHMENTS'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final att in widget.attachments)
                      _AttachmentChip(attachment: att),
                  ],
                ),
              ],
              if (_draftId == null) ...[
                const SizedBox(height: 18),
                const _FieldLabel('DELIVERY'),
                const SizedBox(height: 8),
                _ModeToggle(
                  enabled: !_busy,
                  canSaveDraft: _canSubmitFor(EmailReviewMode.draft),
                  canSendNow: _canSubmitFor(EmailReviewMode.send),
                  onSaveDraft: () => _submit(EmailReviewMode.draft),
                  onSendNow: () => _submit(EmailReviewMode.send),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                _ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 20),
              if (_draftId != null)
                _PrimaryButton(
                  label: 'Done',
                  icon: Icons.check_rounded,
                  busy: false,
                  onTap: () => Navigator.of(context).pop(
                    EmailReviewResult(draftCreated: true, draftId: _draftId),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? _recipientWarning(RecipientResolution resolution) {
    if (resolution.confidence == RecipientConfidence.none ||
        resolution.source == RecipientSource.none ||
        resolution.source == RecipientSource.applyLinkOnly) {
      return 'No public inbox was found. Add or replace the recipient before sending.';
    }
    if (resolution.confidence == RecipientConfidence.low &&
        resolution.source == RecipientSource.guessedPattern) {
      return 'Syncra could not verify this inbox. Please confirm or replace it before sending.';
    }
    if (resolution.confidence == RecipientConfidence.medium) {
      return resolution.reason.trim().isEmpty
          ? 'Review this recipient before sending.'
          : resolution.reason;
    }
    return null;
  }
}

String? _domainFromEmail(String email) {
  final at = email.lastIndexOf('@');
  if (at < 0 || at == email.length - 1) return null;
  final domain = email.substring(at + 1).trim().toLowerCase();
  return domain.isEmpty ? null : domain;
}

class _RecipientBadge extends StatelessWidget {
  const _RecipientBadge({required this.resolution});

  final RecipientResolution resolution;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = switch (resolution.confidence) {
      RecipientConfidence.confirmed ||
      RecipientConfidence.high => brand.success,
      RecipientConfidence.medium => brand.warning,
      RecipientConfidence.low => brand.warning,
      RecipientConfidence.none => brand.textSoft,
    };
    final icon = switch (resolution.source) {
      RecipientSource.confirmedCache ||
      RecipientSource.demoOverride => Icons.verified_rounded,
      RecipientSource.officialCompanyWebsite ||
      RecipientSource.publicCareersPage => Icons.public_rounded,
      RecipientSource.guessedPattern => Icons.help_outline_rounded,
      RecipientSource.applyLinkOnly ||
      RecipientSource.none => Icons.mail_outline_rounded,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: brand.isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              resolution.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientWarning extends StatelessWidget {
  const _RecipientWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: brand.warning.withValues(alpha: brand.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brand.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: brand.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: brand.ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientConfirmationCheckbox extends StatelessWidget {
  const _RecipientConfirmationCheckbox({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'I confirmed this guessed inbox is the right recipient.',
                style: TextStyle(
                  color: brand.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
        color: brand.ink.withValues(alpha: 0.7),
      ),
    );
  }
}

/// Segmented "Save as draft / Send now" control. Lets the user pick the
/// delivery action after reviewing, instead of the caller fixing it. Disabled
/// while a send/draft is in flight.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.enabled,
    required this.canSaveDraft,
    required this.canSendNow,
    required this.onSaveDraft,
    required this.onSendNow,
  });

  final bool enabled;
  final bool canSaveDraft;
  final bool canSendNow;
  final VoidCallback onSaveDraft;
  final VoidCallback onSendNow;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PrimaryButton(
            label: 'Save as draft',
            icon: Icons.drafts_rounded,
            busy: false,
            onTap: enabled && canSaveDraft ? onSaveDraft : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PrimaryButton(
            label: 'Send now',
            icon: Icons.send_rounded,
            busy: false,
            onTap: enabled && canSendNow ? onSendNow : null,
          ),
        ),
      ],
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final fg = selected ? brand.inkInverse : brand.ink;
    return Material(
      color: selected ? brand.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableField extends StatelessWidget {
  const _EditableField({
    required this.controller,
    required this.hint,
    required this.enabled,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.border),
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType:
            keyboardType ??
            (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
        style: TextStyle(
          fontSize: 13.5,
          color: brand.ink,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: brand.textSoft,
            fontWeight: FontWeight.w500,
          ),
          border: InputBorder.none,
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment});

  final EmailAttachment attachment;

  String get _size {
    final kb = attachment.bytes.length / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brand.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file_rounded, size: 15, color: brand.textMuted),
          const SizedBox(width: 6),
          Text(
            attachment.filename,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: brand.ink,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _size,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: brand.textSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: brand.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brand.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: brand.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: brand.danger,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final enabled = onTap != null;
    final fg = enabled ? brand.inkInverse : brand.textSoft;
    return Material(
      color: enabled ? brand.ink : brand.surfaceMuted,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(brand.inkInverse),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

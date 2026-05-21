import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/brand_theme.dart';
import '../services/email_send_service.dart';
import '../services/gmail_service.dart';

/// What [EmailReviewPage.show] resolves to.
///
/// `null` from `show()` means the user dismissed the sheet without sending.
/// A non-null result means a send was attempted: [sent] tells you whether it
/// succeeded.
class EmailReviewResult {
  const EmailReviewResult({required this.sent, this.messageId, this.error});

  final bool sent;
  final String? messageId;
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
    required this.recipient,
    required this.initialSubject,
    required this.initialBody,
    this.applicationId,
    this.attachments = const [],
  });

  final String recipient;
  final String initialSubject;
  final String initialBody;

  /// Tracker application to stamp `sent_at` / `sent_email_id` on success.
  final String? applicationId;

  /// Files to attach — typically the tailored resume PDF.
  final List<EmailAttachment> attachments;

  /// Opens the review sheet. Resolves to the [EmailReviewResult], or `null`
  /// if the user dismissed it without sending.
  static Future<EmailReviewResult?> show(
    BuildContext context, {
    required String recipient,
    required String subject,
    required String body,
    String? applicationId,
    List<EmailAttachment> attachments = const [],
  }) {
    return showModalBottomSheet<EmailReviewResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmailReviewPage._(
        recipient: recipient,
        initialSubject: subject,
        initialBody: body,
        applicationId: applicationId,
        attachments: attachments,
      ),
    );
  }

  @override
  State<EmailReviewPage> createState() => _EmailReviewPageState();
}

class _EmailReviewPageState extends State<EmailReviewPage> {
  late final TextEditingController _subjectCtrl =
      TextEditingController(text: widget.initialSubject);
  late final TextEditingController _bodyCtrl =
      TextEditingController(text: widget.initialBody);

  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final subject = _subjectCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (subject.isEmpty || body.isEmpty) {
      setState(() => _error = 'Subject and message cannot be empty.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();

    final service = EmailSendService.instance;
    // Minting the token here is what makes this the *only* legitimate send
    // path — the agent has no way to produce one.
    final token = service.mintConfirmationToken();

    try {
      final result = await service.sendConfirmed(
        confirmationToken: token,
        to: widget.recipient,
        subject: subject,
        body: body,
        uid: FirebaseAuth.instance.currentUser?.uid,
        applicationId: widget.applicationId,
        attachments: widget.attachments,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        EmailReviewResult(sent: true, messageId: result.messageId),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _friendlyError(e);
      });
    }
  }

  /// Turns a raw exception into one line a user can act on.
  String _friendlyError(Object e) {
    if (e is GmailException) return e.message;
    if (e is EmailNotConfirmedException) {
      return 'Confirmation expired. Tap Send again.';
    }
    return "Couldn't send the email. Check your connection and try again.";
  }

  @override
  Widget build(BuildContext context) {
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
                'Review email',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: brand.ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Nothing is sent until you tap Send — the agent never sends '
                'on its own.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: brand.textMuted,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              _RecipientRow(recipient: widget.recipient),
              const SizedBox(height: 14),
              const _FieldLabel('SUBJECT'),
              const SizedBox(height: 8),
              _EditableField(
                controller: _subjectCtrl,
                hint: 'Subject line',
                enabled: !_sending,
              ),
              const SizedBox(height: 14),
              const _FieldLabel('MESSAGE'),
              const SizedBox(height: 8),
              _EditableField(
                controller: _bodyCtrl,
                hint: 'Email body',
                enabled: !_sending,
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
              if (_error != null) ...[
                const SizedBox(height: 14),
                _ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _CancelButton(
                      onTap: _sending
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _SendButton(
                      sending: _sending,
                      onTap: _sending ? null : _send,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({required this.recipient});

  final String recipient;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.border),
      ),
      child: Row(
        children: [
          Icon(Icons.person_outline_rounded, size: 18, color: brand.textMuted),
          const SizedBox(width: 10),
          Text(
            'To',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: brand.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              recipient.isEmpty ? 'No recipient' : recipient,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: brand.ink,
              ),
            ),
          ),
        ],
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

class _EditableField extends StatelessWidget {
  const _EditableField({
    required this.controller,
    required this.hint,
    required this.enabled,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final int minLines;
  final int maxLines;

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
            maxLines > 1 ? TextInputType.multiline : TextInputType.text,
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

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.surface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: brand.border),
          ),
          child: Text(
            'Cancel',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: brand.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.sending, required this.onTap});

  final bool sending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.ink,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: sending
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(brand.inkInverse),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.send_rounded,
                        size: 16, color: brand.inkInverse),
                    const SizedBox(width: 8),
                    Text(
                      'Send email',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: brand.inkInverse,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

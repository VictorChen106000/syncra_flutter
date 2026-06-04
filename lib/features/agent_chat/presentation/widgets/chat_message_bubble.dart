import 'package:flutter/material.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../../../core/utils/file_formatter.dart';
import '../../models/chat_message.dart';

/// Right-aligned user turn: any attached resume(s) render as a small square
/// document tile above the message, and the message itself sits in a lime
/// bubble with black text. Both hug the right edge so the user's side of the
/// conversation reads as one column.
class UserMessageView extends StatelessWidget {
  const UserMessageView({super.key, required this.message});

  final UserMessage message;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (message.attachments.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final attachment in message.attachments)
                    _ResumeSquare(name: attachment.name),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (message.text.trim().isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.80,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: brand.accent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: SelectableText(
                  message.text,
                  style: TextStyle(
                    color: brand.onAccent,
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A compact square that stands in for an attached resume — a faux document
/// page with a PDF tag and the file name. Recognisable as "the resume I sent"
/// without rendering the real PDF inline.
class _ResumeSquare extends StatelessWidget {
  const _ResumeSquare({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.border),
        boxShadow: [
          BoxShadow(
            color: brand.shadow.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Faux résumé page — a few placeholder lines + a PDF tag.
          Container(
            height: 96,
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: brand.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: brand.border, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PageLine(brand, widthFactor: 0.55, height: 5, strong: true),
                const SizedBox(height: 8),
                _PageLine(brand, widthFactor: 1.0),
                const SizedBox(height: 5),
                _PageLine(brand, widthFactor: 0.88),
                const SizedBox(height: 5),
                _PageLine(brand, widthFactor: 0.94),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 12,
                      color: brand.danger,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'PDF',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: brand.textSoft,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
            child: Text(
              FileFormatter.cleanName(name),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: brand.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.25,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One placeholder "text line" inside the faux résumé page.
class _PageLine extends StatelessWidget {
  const _PageLine(
    this.brand, {
    required this.widthFactor,
    this.height = 4,
    this.strong = false,
  });

  final BrandTheme brand;
  final double widthFactor;
  final double height;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: strong ? brand.outline : brand.border,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

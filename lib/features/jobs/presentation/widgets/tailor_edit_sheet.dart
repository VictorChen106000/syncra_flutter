import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class TailorEditResult {
  const TailorEditResult({required this.body, required this.keywords});

  final String body;
  final List<String> keywords;
}

class TailorEditSheet {
  const TailorEditSheet._();

  static Future<TailorEditResult?> show(
    BuildContext context, {
    required String initialBody,
    required List<String> initialKeywords,
  }) {
    return showModalBottomSheet<TailorEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _TailorEditSheetBody(
        initialBody: initialBody,
        initialKeywords: initialKeywords,
      ),
    );
  }
}

class _TailorEditSheetBody extends StatefulWidget {
  const _TailorEditSheetBody({
    required this.initialBody,
    required this.initialKeywords,
  });

  final String initialBody;
  final List<String> initialKeywords;

  @override
  State<_TailorEditSheetBody> createState() => _TailorEditSheetBodyState();
}

class _TailorEditSheetBodyState extends State<_TailorEditSheetBody> {
  late final TextEditingController _bodyCtrl =
      TextEditingController(text: widget.initialBody);
  late final TextEditingController _keywordCtrl = TextEditingController();
  late final List<String> _keywords = List.of(widget.initialKeywords);

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _keywordCtrl.dispose();
    super.dispose();
  }

  void _addKeyword() {
    final value = _keywordCtrl.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _keywords.add(value);
      _keywordCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: inset.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.scaffold,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: 20 + inset.padding.bottom,
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
              const Text(
                'Edit AI rewrite',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tweak the wording or keywords before accepting.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              _Label('Rewritten paragraph'),
              const SizedBox(height: 6),
              TextField(
                controller: _bodyCtrl,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surface,
                  hintText: 'Edit the AI rewrite',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.ink),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              _Label('Keywords'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kw in _keywords)
                    InputChip(
                      label: Text(kw),
                      onDeleted: () => setState(() => _keywords.remove(kw)),
                      backgroundColor: AppColors.surface,
                      side: const BorderSide(color: AppColors.border),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _keywordCtrl,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addKeyword(),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.surface,
                        hintText: 'Add a keyword',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.ink),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _addKeyword,
                    icon: const Icon(Icons.add_circle_rounded,
                        color: AppColors.ink),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(
                    TailorEditResult(
                      body: _bodyCtrl.text.trim(),
                      keywords: List.of(_keywords),
                    ),
                  ),
                  child: const Text(
                    'Save edits',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
        color: AppColors.ink.withValues(alpha: 0.7),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_theme.dart';

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
  late final TextEditingController _bodyCtrl = TextEditingController(
    text: widget.initialBody,
  );
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
    final brand = context.brand;
    final inset = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: inset.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: brand.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                    color: brand.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Edit AI rewrite',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: brand.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tweak the wording or keywords before accepting.',
                style: TextStyle(
                  fontSize: 13,
                  color: brand.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              const _Label('Rewritten paragraph'),
              const SizedBox(height: 6),
              TextField(
                controller: _bodyCtrl,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: brand.surface,
                  hintText: 'Edit the AI rewrite',
                  hintStyle: TextStyle(color: brand.textSoft),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: brand.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: brand.ink),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: brand.border),
                  ),
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: brand.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              const _Label('Keywords'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kw in _keywords)
                    InputChip(
                      label: Text(kw, style: TextStyle(color: brand.ink)),
                      onDeleted: () => setState(() => _keywords.remove(kw)),
                      backgroundColor: brand.surface,
                      side: BorderSide(color: brand.border),
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
                        fillColor: brand.surface,
                        hintText: 'Add a keyword',
                        hintStyle: TextStyle(color: brand.textSoft),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: brand.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: brand.ink),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: brand.border),
                        ),
                      ),
                      style: TextStyle(fontSize: 14, color: brand.ink),
                    ),
                  ),
                  IconButton(
                    onPressed: _addKeyword,
                    icon: Icon(Icons.add_circle_rounded, color: brand.ink),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: brand.ink,
                    foregroundColor: brand.inkInverse,
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
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
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
    final brand = context.brand;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
        color: brand.ink.withValues(alpha: 0.7),
      ),
    );
  }
}

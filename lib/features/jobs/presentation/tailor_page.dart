import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import 'widgets/job_unavailable_view.dart';
import '../../../data/models/job.dart';
import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/step_pill.dart';
import 'widgets/tailor_edit_sheet.dart';

class TailorPage extends StatefulWidget {
  const TailorPage({super.key, this.job});

  final Job? job;

  @override
  State<TailorPage> createState() => _TailorPageState();
}

class _TailorPageState extends State<TailorPage> {
  static const _initialRewrite =
      'Designed and built a responsive AI career prototype with React, Figma workflows, and user-centered job matching features.';
  static const _initialKeywords = [
    'Responsive design',
    'AI workflow',
    'Job matching',
  ];

  String _rewrite = _initialRewrite;
  List<String> _keywords = List.of(_initialKeywords);

  Future<void> _openEditSheet() async {
    final result = await TailorEditSheet.show(
      context,
      initialBody: _rewrite,
      initialKeywords: _keywords,
    );
    if (result == null) return;
    setState(() {
      _rewrite = result.body.isEmpty ? _rewrite : result.body;
      _keywords = result.keywords;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Edits saved to draft'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (widget.job == null) return const JobUnavailableView();
    final j = widget.job!;

    return Scaffold(
      backgroundColor: brand.bg,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.page(
              kicker: '${j.company} · ${j.title}',
              title: AppStrings.tailorResume,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.screenHorizontalPadding,
                  20,
                  AppConstants.screenHorizontalPadding,
                  32,
                ),
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.before,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Created a student app project using React and Figma.',
                          style: TextStyle(
                            color: brand.textMuted,
                            fontSize: 13.5,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    backgroundColor: brand.surfaceMuted,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: brand.accent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                AppStrings.after.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: brand.onAccent,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _rewrite,
                          style: TextStyle(
                            color: brand.ink,
                            fontSize: 13.5,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.keywordsAdded,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final kw in _keywords) StepPill(label: kw),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppPrimaryButton(
                    label: AppStrings.acceptChanges,
                    onPressed: () =>
                        context.go(RouteNames.review, extra: j),
                  ),
                  const SizedBox(height: 12),
                  AppSecondaryButton(
                    label: AppStrings.editChanges,
                    onPressed: _openEditSheet,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => context.go(RouteNames.review, extra: j),
                      icon: Icon(
                        Icons.undo_rounded,
                        size: 16,
                        color: brand.textMuted,
                      ),
                      label: Text(
                        AppStrings.revertToOriginal,
                        style: TextStyle(
                          color: brand.textMuted,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../models/resume_fit.dart';

/// Card that renders a [ResumeFit] as a donut pie + interactive legend.
///
/// Used in two places:
///   * `FitChartBlockView` (chat transcript) — the agent's onboarding chart
///     drops into the chat the moment it emits `propose_fit_chart`.
///   * The dashboard's "Chart" view — the persisted resume-fit snapshot on
///     `users/{uid}.resume_fit` is re-rendered here so the user can revisit
///     the read without re-uploading their resume.
///
/// Tapping a slice or a legend row focuses that segment: the slice puffs out
/// and its rationale (if any) expands inline under the row.
class ResumeFitChart extends StatefulWidget {
  const ResumeFitChart({
    super.key,
    required this.fit,
    this.title = 'Resume fit',
    this.showHeader = true,
    this.elevated = true,
  });

  final ResumeFit fit;

  /// Small caps header shown above the headline. Hidden when [showHeader] is
  /// false — the dashboard suppresses it because its own section title is
  /// already in the segmented control.
  final String title;
  final bool showHeader;

  /// When true, paints a surface + border + shadow around the card. The
  /// dashboard variant turns this off so the chart sits flush against the
  /// dashboard's own card chrome.
  final bool elevated;

  @override
  State<ResumeFitChart> createState() => _ResumeFitChartState();
}

class _ResumeFitChartState extends State<ResumeFitChart> {
  int _touchedIndex = -1;

  List<Color> _palette(BrandTheme brand) => [
        brand.ink,
        brand.accent,
        brand.textMuted,
        brand.border,
        brand.surfaceMuted,
      ];

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final segments = widget.fit.segments;
    final palette = _palette(brand);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader)
          Row(
            children: [
              Icon(Icons.donut_small_rounded, size: 16, color: brand.ink),
              const SizedBox(width: 6),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                  color: brand.ink,
                ),
              ),
            ],
          ),
        if (widget.fit.headline != null) ...[
          if (widget.showHeader) const SizedBox(height: 10),
          Text(
            widget.fit.headline!,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: brand.ink,
              letterSpacing: -0.1,
            ),
          ),
        ],
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 340;
            final chart = AspectRatio(
              aspectRatio: 1,
              child: PieChart(
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            response == null ||
                            response.touchedSection == null) {
                          _touchedIndex = -1;
                          return;
                        }
                        _touchedIndex =
                            response.touchedSection!.touchedSectionIndex;
                      });
                    },
                  ),
                  borderData: FlBorderData(show: false),
                  sectionsSpace: 2,
                  centerSpaceRadius: 36,
                  sections: [
                    for (var i = 0; i < segments.length; i++)
                      _sectionFor(
                        segments[i],
                        palette[i % palette.length],
                        touched: i == _touchedIndex,
                        brand: brand,
                      ),
                  ],
                ),
              ),
            );
            final legend = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < segments.length; i++) ...[
                  _LegendRow(
                    segment: segments[i],
                    color: palette[i % palette.length],
                    focused: i == _touchedIndex,
                    onTap: () => setState(() {
                      _touchedIndex = _touchedIndex == i ? -1 : i;
                    }),
                  ),
                  if (i != segments.length - 1) const SizedBox(height: 8),
                ],
              ],
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 160, child: Center(child: chart)),
                  const SizedBox(height: 14),
                  legend,
                ],
              );
            }
            return SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 160, child: chart),
                  const SizedBox(width: 16),
                  Expanded(child: legend),
                ],
              ),
            );
          },
        ),
        if (widget.fit.recommendation != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: brand.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: brand.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: brand.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.fit.recommendation!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: brand.ink,
                      height: 1.4,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (!widget.elevated) return content;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brand.border),
        boxShadow: [
          BoxShadow(
            color: brand.shadow.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: content,
    );
  }

  PieChartSectionData _sectionFor(
    ResumeFitSegment segment,
    Color color, {
    required bool touched,
    required BrandTheme brand,
  }) {
    final radius = touched ? 64.0 : 54.0;
    final fontSize = touched ? 14.0 : 11.0;
    final percent = segment.percent.round();
    return PieChartSectionData(
      color: color,
      value: segment.percent,
      radius: radius,
      title: '$percent%',
      titleStyle: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        color: brand.inkInverse,
        letterSpacing: -0.1,
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.segment,
    required this.color,
    required this.focused,
    required this.onTap,
  });

  final ResumeFitSegment segment;
  final Color color;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final percent = segment.percent.round();
    final hasRationale =
        segment.rationale != null && segment.rationale!.isNotEmpty;
    return Material(
      color: focused ? brand.surfaceMuted : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            segment.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: brand.ink,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        Text(
                          '$percent%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: brand.textMuted,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
                    if (focused && hasRationale) ...[
                      const SizedBox(height: 4),
                      Text(
                        segment.rationale!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: brand.textMuted,
                          height: 1.35,
                          letterSpacing: -0.05,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

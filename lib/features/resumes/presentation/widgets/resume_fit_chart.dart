import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../models/resume_fit.dart';

/// Minimalist donut chart for a [ResumeFit] snapshot. Used in two surfaces:
///   * the agent chat transcript when `propose_fit_chart` lands
///   * the dashboard's chart view
///
/// Visual contract:
///   - No header, no surface chrome — the chart sits flush against whatever
///     the parent gives it.
///   - Gradient-green palette: the dominant slice is brand lime, successive
///     slices step toward a deep forest green so dominance reads at a glance.
///   - The agent's `headline` + `recommendation` are hidden by default.
///     Tap the donut to reveal them with a smooth expand; tap again to hide.
class ResumeFitChart extends StatefulWidget {
  const ResumeFitChart({super.key, required this.fit});

  final ResumeFit fit;

  @override
  State<ResumeFitChart> createState() => _ResumeFitChartState();
}

class _ResumeFitChartState extends State<ResumeFitChart> {
  /// When true, the headline (above the chart) and the recommendation (below
  /// it) are revealed. Toggled by a tap on the donut.
  bool _revealed = false;

  /// Deep forest green the gradient terminates at. Kept private here so the
  /// chart's palette is self-contained; tweaking it doesn't ripple through
  /// the app's brand theme.
  static const Color _deepGreen = Color(0xFF1E4D14);

  List<Color> _palette(BrandTheme brand) {
    final base = brand.accent;
    return [
      base,
      Color.lerp(base, _deepGreen, 0.28)!,
      Color.lerp(base, _deepGreen, 0.52)!,
      Color.lerp(base, _deepGreen, 0.72)!,
      Color.lerp(base, _deepGreen, 0.88)!,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final segments = widget.fit.segments;
    final palette = _palette(brand);
    final hasMeta = widget.fit.headline != null ||
        widget.fit.recommendation != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Headline reveals above the donut so the eye lands on it first
        // when the user expands. AnimatedSize handles the height delta;
        // AnimatedOpacity fades the text so it doesn't pop.
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            heightFactor: _revealed && widget.fit.headline != null ? 1 : 0,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: AnimatedOpacity(
                opacity: _revealed && widget.fit.headline != null ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: Text(
                  widget.fit.headline ?? '',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: brand.ink,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 340;
            final chart = AspectRatio(
              aspectRatio: 1,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: hasMeta
                    ? () => setState(() => _revealed = !_revealed)
                    : null,
                child: PieChart(
                  PieChartData(
                    // No touch focus — the whole donut is a single tap target
                    // for the reveal interaction so the gesture stays
                    // unambiguous.
                    pieTouchData: PieTouchData(enabled: false),
                    borderData: FlBorderData(show: false),
                    sectionsSpace: 2,
                    centerSpaceRadius: 38,
                    sections: [
                      for (var i = 0; i < segments.length; i++)
                        _sectionFor(
                          segments[i],
                          palette[i % palette.length],
                        ),
                    ],
                  ),
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
                  ),
                  if (i != segments.length - 1) const SizedBox(height: 10),
                ],
              ],
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 168, child: Center(child: chart)),
                  const SizedBox(height: 16),
                  legend,
                ],
              );
            }
            return SizedBox(
              height: 168,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 168, child: chart),
                  const SizedBox(width: 20),
                  Expanded(child: legend),
                ],
              ),
            );
          },
        ),
        // Recommendation reveals below the chart with the same animation
        // contract as the headline. Sits in a quiet pill so the agent's
        // nudge reads as a sticky-note, not body copy.
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            heightFactor:
                _revealed && widget.fit.recommendation != null ? 1 : 0,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: AnimatedOpacity(
                opacity:
                    _revealed && widget.fit.recommendation != null ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: brand.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: _deepGreen,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.fit.recommendation ?? '',
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
              ),
            ),
          ),
        ),
      ],
    );
  }

  PieChartSectionData _sectionFor(ResumeFitSegment segment, Color color) {
    return PieChartSectionData(
      color: color,
      value: segment.percent,
      radius: 56,
      // Titles inside slices removed — percentages live in the legend so the
      // donut itself stays clean (and so the tap-target reads as "tap the
      // shape" rather than "tap one of these numbers").
      showTitle: false,
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.segment, required this.color});

  final ResumeFitSegment segment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final percent = segment.percent.round();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            segment.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: brand.ink,
              letterSpacing: -0.1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$percent%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: brand.textMuted,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

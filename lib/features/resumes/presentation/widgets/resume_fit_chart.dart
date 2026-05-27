import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../models/resume_fit.dart';

/// Minimalist donut for a [ResumeFit] snapshot. Used in two surfaces:
///   * the agent chat transcript when `propose_fit_chart` lands
///   * the dashboard's chart view
///
/// Visual contract:
///   - Donut is **centered** with no surrounding chrome (no card, no title,
///     no persistent legend).
///   - Gradient-green palette: the dominant slice is brand lime, successive
///     slices step toward a deep forest green.
///   - Tap a slice → that slice puffs out, and the slice's label / percent /
///     rationale fade in *below* the donut. Tap again (or another slice) to
///     swap focus; tap outside to dismiss. The chart starts silent — users
///     discover the text by exploring.
class ResumeFitChart extends StatefulWidget {
  const ResumeFitChart({super.key, required this.fit});

  final ResumeFit fit;

  @override
  State<ResumeFitChart> createState() => _ResumeFitChartState();
}

class _ResumeFitChartState extends State<ResumeFitChart> {
  /// Index of the slice the user has tapped. -1 means "nothing focused" —
  /// the donut reads as a quiet shape and the text panel is collapsed.
  int _touched = -1;

  /// Deep forest green the gradient terminates at. Private here so the
  /// chart's palette doesn't ripple into the global brand theme.
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
    final segments = widget.fit.segments;
    final palette = _palette(context.brand);
    final focused =
        (_touched >= 0 && _touched < segments.length) ? _touched : -1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Donut: centered on the cross axis, fixed square footprint so the
        // text panel below stays at a predictable Y. Tapping a slice flips
        // _touched; tapping the same slice again clears focus.
        SizedBox(
          height: 220,
          width: 220,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions ||
                      response == null ||
                      response.touchedSection == null) {
                    return;
                  }
                  final i = response.touchedSection!.touchedSectionIndex;
                  if (i < 0) return;
                  setState(() => _touched = _touched == i ? -1 : i);
                },
              ),
              borderData: FlBorderData(show: false),
              sectionsSpace: 2,
              centerSpaceRadius: 56,
              sections: [
                for (var i = 0; i < segments.length; i++)
                  _sectionFor(
                    segments[i],
                    palette[i % palette.length],
                    touched: i == focused,
                  ),
              ],
            ),
          ),
        ),

        // The text panel below the donut. AnimatedSize collapses to zero
        // when nothing is focused so the chart sits in a calm vertical
        // rhythm — and pops open when the user taps a slice. AnimatedSwitcher
        // cross-fades between slices so swapping focus doesn't snap.
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: child,
            ),
            child: focused == -1
                ? const SizedBox(
                    key: ValueKey('idle'),
                    width: double.infinity,
                  )
                : _FocusPanel(
                    key: ValueKey('focus-$focused'),
                    segment: segments[focused],
                    color: palette[focused % palette.length],
                  ),
          ),
        ),
      ],
    );
  }

  PieChartSectionData _sectionFor(
    ResumeFitSegment segment,
    Color color, {
    required bool touched,
  }) {
    // Touched slice puffs out and gets a soft shadow ring so the focus is
    // unmistakable against neighbouring slices.
    return PieChartSectionData(
      color: color,
      value: segment.percent,
      radius: touched ? 72 : 56,
      showTitle: false,
      borderSide: touched
          ? BorderSide(color: color.withValues(alpha: 0.4), width: 4)
          : BorderSide.none,
    );
  }
}

/// Text card that appears under the donut when the user taps a slice.
/// Lays out:
///   - a small colour swatch matching the slice
///   - the slice label + percent on one line
///   - the optional rationale below, in a quieter muted tone
class _FocusPanel extends StatelessWidget {
  const _FocusPanel({
    super.key,
    required this.segment,
    required this.color,
  });

  final ResumeFitSegment segment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final percent = segment.percent.round();
    final rationale = segment.rationale?.trim();
    final hasRationale = rationale != null && rationale.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
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
              Flexible(
                child: Text(
                  segment.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: brand.ink,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: brand.textMuted,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          if (hasRationale) ...[
            const SizedBox(height: 8),
            Text(
              rationale,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: brand.textMuted,
                height: 1.45,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

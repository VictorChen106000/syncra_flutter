import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../models/resume_fit.dart';

/// Minimalist donut for a [ResumeFit] snapshot, used on the profile page.
///
/// Visual contract:
///   - Donut is **centered** with no surrounding chrome (no card, no title).
///   - An optional [centerChild] (the user's avatar) sits in the donut hole, so
///     the chart doubles as the profile identity — no separate name/email row.
///   - Every slice's label + percent **hangs off the ring** at the slice's own
///     angle, joined by a thin leader line and a colour dot. Nothing is hidden
///     behind a tap to read the basics.
///   - Gradient-green palette: the dominant slice is brand lime, successive
///     slices step toward a deep forest green.
///   - On first paint the dominant slice is pre-focused (puffed + its rationale
///     shown below) so the headline strength reads without discovery.
///   - Tap a slice or its label → that slice puffs out and its rationale swaps
///     in below. Tap the focused slice again to collapse. Only the *tap-up*
///     event toggles focus — fl_chart fires many in-flight pointer events per
///     gesture and reacting to all of them flickered focus mid-press.
class ResumeFitChart extends StatefulWidget {
  const ResumeFitChart({super.key, required this.fit, this.centerChild});

  final ResumeFit fit;

  /// Optional widget painted inside the donut hole — on the profile page this
  /// is the user's avatar, so identity lives in the centre of the chart.
  final Widget? centerChild;

  @override
  State<ResumeFitChart> createState() => _ResumeFitChartState();
}

class _ResumeFitChartState extends State<ResumeFitChart> {
  /// Index of the slice the user has tapped. -1 means "nothing focused".
  /// Defaults to the dominant segment on mount so the user lands on a useful
  /// number; [didUpdateWidget] re-points it if the fit data swaps underneath.
  int _touched = -1;

  @override
  void initState() {
    super.initState();
    _touched = _dominantIndex(widget.fit.segments);
  }

  @override
  void didUpdateWidget(covariant ResumeFitChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.fit, widget.fit)) {
      _touched = _dominantIndex(widget.fit.segments);
    }
  }

  /// Index of the highest-percent slice, or -1 for an empty list. Ties go to
  /// the earlier slice so the palette's bright lime stays the focus.
  static int _dominantIndex(List<ResumeFitSegment> segments) {
    if (segments.isEmpty) return -1;
    var best = 0;
    for (var i = 1; i < segments.length; i++) {
      if (segments[i].percent > segments[best].percent) best = i;
    }
    return best;
  }

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

  /// Mid-angle (degrees, clockwise from the top) of each slice, matching the
  /// `startDegreeOffset: -90` the [PieChart] is drawn with. Used to anchor the
  /// hanging labels and leader lines to the slice they describe.
  List<double> _midAnglesDeg(List<ResumeFitSegment> segments) {
    final total = segments.fold<double>(0, (sum, s) => sum + s.percent);
    if (total <= 0) return List<double>.filled(segments.length, -90);
    var acc = -90.0;
    final mids = <double>[];
    for (final s in segments) {
      final sweep = (s.percent / total) * 360.0;
      mids.add(acc + sweep / 2);
      acc += sweep;
    }
    return mids;
  }

  void _toggle(int i) => setState(() => _touched = _touched == i ? -1 : i);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final segments = widget.fit.segments;
    final palette = _palette(brand);
    final focused = (_touched >= 0 && _touched < segments.length)
        ? _touched
        : -1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final size = math.min(constraints.maxWidth, 480.0);
            final cx = size / 2;
            final cy = size / 2;
            // The donut takes the bulk of the width so it reads big; the rest
            // is the gutter the hanging labels live in.
            final d = size * 0.52; // donut box
            // A thick, bold ring: the slice band is ~42% of the donut radius,
            // so the chart reads buff and substantial rather than a thin hoop.
            final centerSpace = d * 0.27;
            final sliceR = d * 0.20;
            final touchedR = d * 0.23;
            final anchorR = d / 2 + 8;
            final labelMaxW = (((size - d) / 2) - 8)
                .clamp(56.0, 120.0)
                .toDouble();
            final mids = _midAnglesDeg(segments);

            final labels = <Widget>[];
            for (var i = 0; i < segments.length; i++) {
              final theta = mids[i] * math.pi / 180.0;
              final cosT = math.cos(theta);
              final sinT = math.sin(theta);
              labels.add(
                _buildLabel(
                  brand: brand,
                  size: size,
                  anchor: Offset(cx + anchorR * cosT, cy + anchorR * sinT),
                  cosT: cosT,
                  sinT: sinT,
                  maxW: labelMaxW,
                  segment: segments[i],
                  focused: i == focused,
                  onTap: () => _toggle(i),
                ),
              );
            }

            return SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: SizedBox(
                      width: d,
                      height: d,
                      child: PieChart(
                        PieChartData(
                          startDegreeOffset: -90,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, response) {
                              if (event is! FlTapUpEvent) return;
                              final section = response?.touchedSection;
                              if (section == null) return;
                              final i = section.touchedSectionIndex;
                              if (i < 0) return;
                              _toggle(i);
                            },
                          ),
                          borderData: FlBorderData(show: false),
                          sectionsSpace: 2,
                          centerSpaceRadius: centerSpace,
                          sections: [
                            for (var i = 0; i < segments.length; i++)
                              _sectionFor(
                                segments[i],
                                palette[i % palette.length],
                                touched: i == focused,
                                touchedR: touchedR,
                                idleR: sliceR,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (widget.centerChild != null)
                    Center(
                      child: SizedBox(
                        width: centerSpace * 1.46,
                        height: centerSpace * 1.46,
                        child: widget.centerChild,
                      ),
                    ),
                  ...labels,
                ],
              ),
            );
          },
        ),

        // The rationale ("why") for the focused slice, revealed below the ring.
        // AnimatedSize collapses to zero when nothing is focused; AnimatedSwitcher
        // cross-fades the text when focus moves between slices. No card — just
        // a quiet centred caption.
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: focused == -1
                ? const SizedBox(key: ValueKey('idle'), width: double.infinity)
                : _RationaleCaption(
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
    required double touchedR,
    required double idleR,
  }) {
    // The focused slice signals itself by puffing out — no border halo, which
    // keeps the ring clean and minimal.
    return PieChartSectionData(
      color: color,
      value: segment.percent,
      radius: touched ? touchedR : idleR,
      showTitle: false,
    );
  }

  /// A single hanging label, floating just outside the ring at its slice's
  /// angle — no connector dot or line, so position alone ties it to its slice.
  /// Right-half slices grow their text rightward, left-half leftward, and
  /// near-vertical slices centre above/below. Positions are clamped to the box
  /// so a long category never clips at the edge.
  Widget _buildLabel({
    required BrandTheme brand,
    required double size,
    required Offset anchor,
    required double cosT,
    required double sinT,
    required double maxW,
    required ResumeFitSegment segment,
    required bool focused,
    required VoidCallback onTap,
  }) {
    final isVertical = cosT.abs() < 0.34;
    final crossAxis = isVertical
        ? CrossAxisAlignment.center
        : (cosT >= 0 ? CrossAxisAlignment.start : CrossAxisAlignment.end);
    final textAlign = isVertical
        ? TextAlign.center
        : (cosT >= 0 ? TextAlign.left : TextAlign.right);

    final content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxis,
        children: [
          Text(
            segment.label,
            textAlign: textAlign,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: focused ? brand.ink : brand.ink.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${segment.percent.round()}%',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              color: focused ? brand.ink : brand.textMuted,
            ),
          ),
        ],
      ),
    );

    const estH = 38.0;
    if (isVertical) {
      final w = math.min(size * 0.5, 150.0);
      final left = (anchor.dx - w / 2).clamp(4.0, size - w - 4).toDouble();
      final top = (sinT < 0 ? anchor.dy - estH : anchor.dy)
          .clamp(2.0, size - estH - 2)
          .toDouble();
      return Positioned(left: left, top: top, width: w, child: content);
    }
    final top = (anchor.dy - estH / 2).clamp(2.0, size - estH - 2).toDouble();
    if (cosT >= 0) {
      final left = (anchor.dx + 4).clamp(4.0, size - maxW - 4).toDouble();
      return Positioned(left: left, top: top, width: maxW, child: content);
    }
    final right = (size - (anchor.dx - 4))
        .clamp(4.0, size - maxW - 4)
        .toDouble();
    return Positioned(right: right, top: top, width: maxW, child: content);
  }
}

/// The focused slice's rationale ("why"), shown as a quiet centred caption
/// under the donut. No card — it floats in the page's own rhythm.
class _RationaleCaption extends StatelessWidget {
  const _RationaleCaption({
    super.key,
    required this.segment,
    required this.color,
  });

  final ResumeFitSegment segment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final rationale = segment.rationale?.trim();
    final hasRationale = rationale != null && rationale.isNotEmpty;
    if (!hasRationale) return const SizedBox(width: double.infinity);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Text(
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
    );
  }
}

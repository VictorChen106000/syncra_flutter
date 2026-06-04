import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/theme/brand_theme.dart';
import '../../../../shared/widgets/gooey_orb.dart';

/// Hardcoded dark so the view never flips with the system theme — both hosts
/// (the standalone [LinkGmailPage] and the onboarding Gmail beat) present it on
/// a dark surface, so [BrandTheme.dark] is the correct palette in both.
const BrandTheme _brand = BrandTheme.dark;

/// Slightly off-white ink: pure #FFFFFF on true black reads as harsh, so back
/// off ~6% — same softening the morning brief / onboarding use.
const Color _softInk = Color(0xFFF1F1F3);

/// The shared body of the "link your Gmail" moment — paired app-icon tiles
/// joined by a link badge, a two-tone headline, a privacy reassurance, and the
/// slide-to-connect CTA.
///
/// Pure presentation: it owns no service or navigation. The host supplies the
/// [linking] flag and the [onConnect] callback (fired once the user completes
/// the slide), and frames it with its own background / skip affordance. Used by
/// both [LinkGmailPage] (standalone route) and the onboarding Gmail phase so the
/// two stay pixel-identical.
///
/// Contains a [Spacer], so it must be given a bounded height (e.g. wrapped in an
/// [Expanded]).
class GmailLinkView extends StatelessWidget {
  const GmailLinkView({
    super.key,
    required this.linking,
    required this.onConnect,
  });

  /// True while the OAuth grant is resolving — parks the slide thumb at the end
  /// and shows a spinner.
  final bool linking;

  /// Fired when the user completes the slide. The host performs the actual link.
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HeroIcons()
            .animate()
            .fadeIn(duration: 500.ms)
            .scale(
              begin: const Offset(0.9, 0.9),
              end: const Offset(1, 1),
              curve: Curves.easeOutBack,
            ),
        const SizedBox(height: 34),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'link to\n',
                style: TextStyle(color: _softInk),
              ),
              TextSpan(
                text: 'Gmail',
                style: TextStyle(color: _brand.accent),
              ),
            ],
          ),
          style: GoogleFonts.inter(
            fontSize: 46,
            fontWeight: FontWeight.w900,
            height: 1.03,
            letterSpacing: -1.6,
          ),
        )
            .animate(delay: 140.ms)
            .fadeIn(duration: 460.ms)
            .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic),
        const SizedBox(height: 16),
        Text(
          'With this access, Syncra can draft and send your outreach '
          'right from your own inbox — no copy-paste, no switching apps.',
          style: TextStyle(
            color: _softInk.withValues(alpha: 0.66),
            fontSize: 15.5,
            height: 1.5,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.1,
          ),
        )
            .animate(delay: 220.ms)
            .fadeIn(duration: 460.ms)
            .moveY(begin: 8, end: 0, curve: Curves.easeOutCubic),
        const Spacer(),
        const _PrivacyNote().animate(delay: 320.ms).fadeIn(duration: 460.ms),
        const SizedBox(height: 22),
        _SlideToConnect(linking: linking, onConnect: onConnect)
            .animate(delay: 380.ms)
            .fadeIn(duration: 380.ms)
            .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic),
      ],
    );
  }
}

/// The two paired app-icon tiles (Gmail + Syncra) joined by a link badge —
/// the signature of an OS "connect to a service" sheet. The badge sits dead
/// centre in the gap, vertically aligned to the tiles' midline, so the pair
/// reads as physically *connected* rather than two icons that merely sit
/// near each other.
class _HeroIcons extends StatelessWidget {
  const _HeroIcons();

  // Gap between the tiles. Narrow enough that the 36px badge bridges it and
  // laps a few pixels onto each tile — that overlap is what sells the join.
  static const double _gap = 28;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _AppTile(
                background: Colors.white,
                child: Padding(
                  padding: EdgeInsets.all(15),
                  child: _GmailGlyph(),
                ),
              ),
              const SizedBox(width: _gap),
              _AppTile(
                background: _brand.surfaceSubtle,
                bordered: true,
                child: const Center(child: GooeyOrb(size: 58)),
              ),
            ],
          ),
          // Centred in the Stack → centred in the gap, on the tiles' midline.
          const _LinkBadge(),
        ],
      ),
    );
  }
}

/// A rounded "app icon" tile — squircle-ish corners and a soft drop shadow so
/// the pair reads as real home-screen icons.
class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.child,
    required this.background,
    this.bordered = false,
  });

  final Widget child;
  final Color background;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
        border: bordered
            ? Border.all(
                color: _brand.accent.withValues(alpha: 0.22),
                width: 1.2,
              )
            : null,
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The small dark chip with a chain-link glyph that visually "joins" the two
/// app tiles.
class _LinkBadge extends StatelessWidget {
  const _LinkBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _brand.surface,
        shape: BoxShape.circle,
        // A 3px ring in the page colour punches the badge cleanly out of the
        // tiles it overlaps, so the join reads crisp rather than muddy.
        border: Border.all(color: _brand.bg, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.link_rounded,
        size: 18,
        color: _softInk,
      ),
    );
  }
}

/// The multicolour Gmail mark, rendered from a bundled SVG so the brand logo is
/// accurate rather than approximated.
class _GmailGlyph extends StatelessWidget {
  const _GmailGlyph();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      AppAssets.gmailSvg,
      semanticsLabel: 'Gmail',
    );
  }
}

/// Lock icon + reassurance line — the trust anchor that lets people grant a
/// scope that feels sensitive.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.lock_rounded,
          size: 17,
          color: _softInk.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Syncra only sends on your behalf — it never reads your inbox. '
            'Your sign-in stays with Google and is never stored or shared.',
            style: TextStyle(
              color: _softInk.withValues(alpha: 0.55),
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.05,
            ),
          ),
        ),
      ],
    );
  }
}

/// The hero CTA — a "slide to link" control. Granting your inbox is a moment
/// that benefits from a deliberate, physical gesture rather than a one-tap
/// commit: you drag the lime thumb the length of the track and it releases the
/// OAuth grant. A flick that doesn't reach the end snaps back, so the action is
/// hard to trigger by accident. While the grant resolves the thumb parks at the
/// end and spins; screen-reader users get an equivalent activatable button.
class _SlideToConnect extends StatefulWidget {
  const _SlideToConnect({required this.linking, required this.onConnect});

  final bool linking;
  final VoidCallback onConnect;

  @override
  State<_SlideToConnect> createState() => _SlideToConnectState();
}

class _SlideToConnectState extends State<_SlideToConnect> {
  static const double _height = 64;
  // No inset: the thumb is a full-height circle, flush top-and-bottom with the
  // track, so it reads as the bar filling in rather than a knob floating in it.
  static const double _pad = 0;
  // Fraction of the track the thumb must clear to count as a confirmed slide.
  static const double _commit = 0.82;

  double _dragX = 0; // thumb offset from its resting (left) position
  bool _dragging = false; // true mid-drag → kills the snap animation
  bool _done = false; // committed → park at the end and show progress

  double get _thumb => _height - _pad * 2;

  void _settle(double maxX) {
    if (_dragX >= maxX * _commit) {
      setState(() {
        _dragX = maxX;
        _dragging = false;
        _done = true;
      });
      widget.onConnect();
    } else {
      setState(() {
        _dragX = 0;
        _dragging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.linking || _done;

    return Semantics(
      button: true,
      enabled: !locked,
      label: locked ? 'Connecting Gmail' : 'Slide to link Gmail',
      onTap: locked ? null : widget.onConnect,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxX = constraints.maxWidth - _thumb - _pad * 2;
          final progress = maxX <= 0 ? 0.0 : (_dragX / maxX).clamp(0.0, 1.0);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart:
                locked ? null : (_) => setState(() => _dragging = true),
            onHorizontalDragUpdate: locked
                ? null
                : (d) => setState(
                      () => _dragX = (_dragX + d.delta.dx).clamp(0.0, maxX),
                    ),
            onHorizontalDragEnd: locked ? null : (_) => _settle(maxX),
            child: Container(
              height: _height,
              decoration: BoxDecoration(
                color: _brand.surfaceSubtle,
                borderRadius: BorderRadius.circular(_height / 2),
                border: Border.all(
                  color: _brand.accent.withValues(alpha: 0.18),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_height / 2),
                child: Stack(
                  children: [
                    // Solid lime fill that grows in behind the thumb as it
                    // advances — the bar literally fills with green, no fade. It
                    // stops at the thumb's centre so the round thumb caps the
                    // trail: no straight vertical seam ("|") peeks past the knob.
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: _dragX + _thumb / 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: _brand.accent),
                      ),
                    ),
                    // Prompt label, centred in the track to the right of the
                    // thumb. Fades out as the thumb slides over it; a slow
                    // shimmer hints that it's draggable.
                    Positioned.fill(
                      left: _thumb + _pad,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: (1 - progress * 1.4).clamp(0.0, 1.0),
                          child: Center(
                            child: Text(
                              'Slide to link Gmail',
                              style: TextStyle(
                                color: _softInk.withValues(alpha: 0.78),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.1,
                              ),
                            )
                                .animate(onPlay: (c) => c.repeat())
                                .shimmer(
                                  delay: 900.ms,
                                  duration: 1500.ms,
                                  color: _softInk,
                                ),
                          ),
                        ),
                      ),
                    ),
                    // The draggable lime thumb.
                    AnimatedPositioned(
                      duration: _dragging
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                      curve: Curves.easeOutBack,
                      left: _pad + _dragX,
                      top: _pad,
                      child: Container(
                        width: _thumb,
                        height: _thumb,
                        decoration: BoxDecoration(
                          // Same lime as the trail it leaves behind, so the knob
                          // and the fill read as one continuous shape — easy on
                          // the eye, no two-tone seam. No drop shadow: the thumb
                          // is flush with the track and the ClipRRect would clip
                          // one away anyway.
                          color: _brand.accent,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: locked
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor:
                                      AlwaysStoppedAnimation(_brand.onAccent),
                                ),
                              )
                            : Icon(
                                Icons.arrow_forward_rounded,
                                size: 22,
                                color: _brand.onAccent,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../shared/widgets/gooey_orb.dart';
import '../services/gmail_service.dart';

/// Post-onboarding permission moment: invite the user to connect their Gmail so
/// the agent can draft and send outreach straight from their own inbox.
///
/// Modeled on a native iOS "link to a service" sheet — paired app-icon tiles
/// joined by a link badge, a two-tone headline, a privacy reassurance, and a
/// single hero CTA. Kept intentionally dark in both themes (hardcoded
/// [BrandTheme.dark]) so the handoff from setup reads as one continuous,
/// premium moment; the brand's lime accent stands in for the reference's blue.
///
/// Linking is optional — tapping the CTA pre-authorizes the Gmail scopes via
/// [GmailService.link]; declining or skipping still lands the user on the
/// dashboard. They can connect later from outreach.
class LinkGmailPage extends StatefulWidget {
  const LinkGmailPage({super.key});

  @override
  State<LinkGmailPage> createState() => _LinkGmailPageState();
}

class _LinkGmailPageState extends State<LinkGmailPage> {
  // Hardcoded dark so the screen doesn't flip with the system theme — see the
  // class doc. We still pull every colour from the brand tokens so it stays
  // "our theme", just locked to the dark palette.
  static const _brand = BrandTheme.dark;

  // Slightly off-white ink: pure #FFFFFF on true black reads as harsh, so back
  // off ~6% — same softening the morning brief uses.
  static const Color _softInk = Color(0xFFF1F1F3);

  final GmailService _gmail = GmailService();
  bool _linking = false;

  @override
  void dispose() {
    _gmail.dispose();
    super.dispose();
  }

  void _toDashboard() {
    if (!mounted) return;
    context.go(RouteNames.dashboard);
  }

  Future<void> _link() async {
    if (_linking) return;
    setState(() => _linking = true);

    final linked = await _gmail.link();
    if (!mounted) return;

    if (!linked) {
      // Declined / unavailable — don't trap the user. Let them in and surface a
      // quiet note that they can connect later.
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('You can connect Gmail later from outreach.'),
          ),
        );
    }
    _toDashboard();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _brand.bg,
      body: Stack(
        children: [
          // Lime glow behind the hero icons — the warm focal point.
          const _Glow(
            alignment: Alignment(-0.55, -0.62),
            diameter: 360,
            opacity: 0.16,
          ),
          // A soft lime wash rising from the bottom, echoing the reference's
          // gradient — restrained so the CTA stays legible.
          const Align(
            alignment: Alignment.bottomCenter,
            child: _BottomWash(),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 12, 26, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Escape hatch — linking is optional.
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _linking ? null : _toDashboard,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: _softInk.withValues(alpha: 0.62),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
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
                        TextSpan(
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
                  const _PrivacyNote()
                      .animate(delay: 320.ms)
                      .fadeIn(duration: 460.ms),
                  const SizedBox(height: 22),
                  _LinkButton(linking: _linking, onTap: _link)
                      .animate(delay: 380.ms)
                      .fadeIn(duration: 380.ms)
                      .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The two paired app-icon tiles (Gmail + Syncra) joined by a link badge —
/// the signature of an OS "connect to a service" sheet.
class _HeroIcons extends StatelessWidget {
  const _HeroIcons();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
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
              const SizedBox(width: 26),
              _AppTile(
                background: _LinkGmailPageState._brand.surfaceSubtle,
                bordered: true,
                child: const Center(child: GooeyOrb(size: 58)),
              ),
            ],
          ),
          // Link badge straddling the gap between the two tiles.
          Positioned(
            left: 76 - 16,
            top: 84 - 18,
            child: const _LinkBadge(),
          ),
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
                color: _LinkGmailPageState._brand.accent.withValues(alpha: 0.22),
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
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _LinkGmailPageState._brand.surface,
        shape: BoxShape.circle,
        border: Border.all(color: _LinkGmailPageState._brand.bg, width: 3),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.link_rounded,
        size: 17,
        color: _LinkGmailPageState._softInk,
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
    const softInk = _LinkGmailPageState._softInk;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.lock_rounded,
          size: 17,
          color: softInk.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Syncra only sends on your behalf — it never reads your inbox. '
            'Your sign-in stays with Google and is never stored or shared.',
            style: TextStyle(
              color: softInk.withValues(alpha: 0.55),
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

/// The hero CTA — a full-width lime pill that pre-authorizes Gmail, swapping to
/// an in-progress state while the OAuth grant resolves.
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.linking, required this.onTap});

  final bool linking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const brand = _LinkGmailPageState._brand;
    return Semantics(
      button: true,
      enabled: !linking,
      label: linking ? 'Connecting Gmail' : 'Link Gmail',
      child: Material(
        color: brand.accent,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          onTap: linking ? null : onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: double.infinity,
            height: 58,
            alignment: Alignment.center,
            child: linking
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(brand.onAccent),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Link Gmail',
                        style: TextStyle(
                          color: brand.onAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: brand.onAccent,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// A soft radial lime glow used as a focal backdrop behind the hero icons.
class _Glow extends StatelessWidget {
  const _Glow({
    required this.alignment,
    required this.diameter,
    required this.opacity,
  });

  final Alignment alignment;
  final double diameter;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                _LinkGmailPageState._brand.accent.withValues(alpha: opacity),
                _LinkGmailPageState._brand.accent.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A lime wash rising from the bottom edge — the brand-coloured stand-in for
/// the reference screen's gradient.
class _BottomWash extends StatelessWidget {
  const _BottomWash();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: 380,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _LinkGmailPageState._brand.accent.withValues(alpha: 0),
              _LinkGmailPageState._brand.accent.withValues(alpha: 0.10),
            ],
          ),
        ),
      ),
    );
  }
}

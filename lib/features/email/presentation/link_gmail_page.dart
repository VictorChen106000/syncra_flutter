import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../auth/state/user_profile_notifier.dart';
import '../services/gmail_service.dart';
import 'widgets/gmail_link_view.dart';

/// Standalone "link your Gmail" route — the entry point for connecting (or
/// re-connecting) Gmail outside onboarding, e.g. later from outreach. The
/// onboarding flow embeds the same [GmailLinkView] as an in-line beat instead
/// of routing here, so the two stay identical.
///
/// Kept intentionally dark in both themes (hardcoded [BrandTheme.dark]) so the
/// moment reads as one continuous, premium surface; the brand's lime accent
/// stands in for a reference's blue.
///
/// Linking is optional — completing the slide pre-authorizes the Gmail scopes
/// via [GmailService.link]; declining or skipping still lands the user on the
/// dashboard. They can connect later from outreach.
class LinkGmailPage extends ConsumerStatefulWidget {
  const LinkGmailPage({super.key});

  @override
  ConsumerState<LinkGmailPage> createState() => _LinkGmailPageState();
}

class _LinkGmailPageState extends ConsumerState<LinkGmailPage> {
  // Hardcoded dark so the screen doesn't flip with the system theme. We still
  // pull every colour from the brand tokens so it stays "our theme", just
  // locked to the dark palette.
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

    if (linked) {
      // Grant is in place — record it on the profile so the connection sticks:
      // the dashboard reads from it and the Profile › Connections toggle shows
      // Gmail as on. Fire-and-forget; the notifier flips its in-memory state
      // synchronously, so we don't block the handoff on the Firestore write.
      unawaited(ref.read(userProfileProvider.notifier).setGmailConnected(true));
    } else {
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
          const Align(alignment: Alignment.bottomCenter, child: _BottomWash()),
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
                  Expanded(
                    child: GmailLinkView(linking: _linking, onConnect: _link),
                  ),
                ],
              ),
            ),
          ),
        ],
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

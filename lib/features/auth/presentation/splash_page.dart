import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key, this.target = RouteNames.login});

  final String target;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with TickerProviderStateMixin {
  late final AnimationController _c; // assemble + exit reveal (forward once)
  late final AnimationController _shimmer; // looping green shimmer sweep

  @override
  void initState() {
    super.initState();
    // `disableAnimations` isn't reliably available until didChangeDependencies,
    // so the durations are set there once we can read it.
    _c = AnimationController(vsync: this);
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _c.addStatusListener((status) {
      // Navigate the instant the zoom-through reveal finishes, so the next page
      // fades up out of the void underneath it.
      if (status == AnimationStatus.completed && mounted) {
        context.go(widget.target);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.duration != null) return; // already started
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _c
      ..duration = reduce
          ? const Duration(milliseconds: 700)
          : const Duration(milliseconds: 1900)
      ..forward();
    if (!reduce) _shimmer.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Scaffold(
      backgroundColor: brand.bg,
      body: Semantics(
        label: '${AppStrings.appName}, loading',
        child: AnimatedBuilder(
          animation: Listenable.merge([_c, _shimmer]),
          builder: (context, _) {
            final t = _c.value;

            // The wordmark gently scales up and fades on the last beat,
            // revealing the next screen underneath it.
            final reveal = reduce
                ? 0.0
                : Curves.easeIn.transform(((t - 0.82) / 0.18).clamp(0.0, 1.0));

            return Opacity(
              opacity: 1.0 - reveal,
              child: Center(
                child: Transform.scale(
                  scale: 1.0 + reveal * 0.14,
                  child: _Wordmark(
                    t: t,
                    shimmer: _shimmer.value,
                    brand: brand,
                    reduceMotion: reduce,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The "Syncra" wordmark: letters fly up from a blur in a left-to-right
/// stagger, while a green shimmer keeps sweeping across the type.
class _Wordmark extends StatelessWidget {
  const _Wordmark({
    required this.t,
    required this.shimmer,
    required this.brand,
    required this.reduceMotion,
  });

  final double t;
  final double shimmer;
  final BrandTheme brand;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final letters = AppStrings.appName.split('');
    final style = TextStyle(
      color: brand.ink,
      fontSize: 72,
      fontWeight: FontWeight.w800,
      letterSpacing: -2,
      height: 1,
    );

    if (reduceMotion) {
      final p = Curves.easeOut.transform((t / 0.7).clamp(0.0, 1.0));
      return Opacity(opacity: p, child: Text(AppStrings.appName, style: style));
    }

    Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < letters.length; i++)
          _Letter(
            char: letters[i],
            style: style,
            progress: _letterProgress(i, letters.length),
          ),
      ],
    );

    // A band of green light continuously sweeping across the wordmark.
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) =>
          _shimmerShader(bounds, shimmer, brand.ink, brand.accentBright),
      child: row,
    );
  }

  double _letterProgress(int i, int n) {
    final start = 0.12 + (i / (n - 1)) * 0.30;
    final raw = ((t - start) / 0.26).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(raw);
  }
}

/// A single glyph that fades and slides up out of a blur.
class _Letter extends StatelessWidget {
  const _Letter({
    required this.char,
    required this.style,
    required this.progress,
  });

  final String char;
  final TextStyle style;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final blur = (1 - progress) * 7;
    Widget glyph = Text(char, style: style);
    if (blur > 0.05) {
      glyph = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: glyph,
      );
    }
    return Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset(0, (1 - progress) * 18),
        child: glyph,
      ),
    );
  }
}

/// The moving green highlight band that brightens the wordmark as it passes.
Shader _shimmerShader(Rect bounds, double p, Color base, Color glint) {
  final pos = -0.3 + 1.6 * p; // band centre travels left → right, then loops
  const half = 0.14;
  final raw = <double>[0.0, pos - half, pos, pos + half, 1.0];
  final stops = <double>[];
  var prev = double.negativeInfinity;
  for (final s in raw) {
    var v = s;
    if (v <= prev) v = prev + 1e-3; // keep stops strictly ascending
    stops.add(v);
    prev = v;
  }
  return LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [base, base, glint, base, base],
    stops: stops,
  ).createShader(bounds);
}

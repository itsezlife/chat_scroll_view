import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// The soft fade under the composer: a [fadeHeight] ramp at the **top** of
/// [zoneHeight], then a clamped semi-opaque wash down to the bottom edge, so
/// content scrolling under the composer, the panel and the keyboard dims
/// instead of ending in a hard line.
///
/// Hits on the wash are **absorbed** so content under the fade cannot be
/// tapped through it. The glass island is a later [Stack] sibling and still
/// receives taps on top.
///
/// **Stacking.** Mount the fade **under** the island (an earlier [Stack]
/// sibling). The wash is drawn whole, under the island too: the island's glass
/// samples the content and the wash together. An earlier cut punched an
/// island-shaped hole in it so the glass saw the content alone, and had to
/// measure the island after every layout and keep the hole in step with it
/// as the island came and went, for a difference of tint under the glass.
class ComposerBottomFade extends StatelessWidget {
  /// Creates a fade of [zoneHeight] using [color], or the theme's content
  /// fade colour when none is given.
  const ComposerBottomFade({
    required this.zoneHeight,
    this.color,
    this.fadeHeight = defaultFadeHeight,
    super.key,
  });

  /// Soft-edge ramp.
  static const double defaultFadeHeight = 48;

  /// Full fade zone from the physical bottom edge: the composer extent plus
  /// the presentation occupancy under it.
  final double zoneHeight;

  /// Fill colour; defaults to `ComposerTokens.contentFade` of the chrome
  /// theme, which differs from the panel background on purpose.
  final Color? color;

  /// Height of the transparent→wash ramp at the top of the zone.
  final double fadeHeight;

  /// Vertical gradient that paints the fade across a [zoneHeight]-tall box.
  ///
  /// The [opacityStops] of [color] ramp over the top [fadeHeight] of the
  /// zone, then the last stop holds down to the bottom edge. A [fadeHeight]
  /// taller than the zone squeezes the whole ramp into it. The gradient's
  /// positions are fractions of the zone, so shade exactly the zone's rect;
  /// outside it the default clamp tiling continues the end stops.
  ///
  /// Only the alpha of [color] shapes the ramp, so an opaque colour also
  /// works as a mask for [BlendMode.dstIn] compositing of other content.
  static LinearGradient gradient({
    required double zoneHeight,
    required Color color,
    double fadeHeight = defaultFadeHeight,
  }) {
    final stops = opacityStops(color);
    final end = zoneHeight <= 0
        ? 1.0
        : (fadeHeight.clamp(0.0, zoneHeight) / zoneHeight).clamp(0.0, 1.0);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[...stops, if (end < 1) stops.last],
      stops: <double>[0, end / 3, end * 2 / 3, end, if (end < 1) 1],
    );
  }

  /// Four [color] stops with rising alpha — transparent, then roughly 34%,
  /// 62% and 81% of [color]'s own alpha — that shape the fade ramp.
  static List<Color> opacityStops(Color color) {
    final a = color.a;
    Color stop(int numer) =>
        color.withValues(alpha: ((numer * a) / 285).clamp(0.0, 1.0));
    return <Color>[
      color.withValues(alpha: 0),
      stop(0x60),
      stop(0xB0),
      stop(0xE8),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (zoneHeight <= 0) return const SizedBox.shrink();
    return AbsorbPointer(
      child: SizedBox(
        height: zoneHeight,
        width: double.infinity,
        child: CustomPaint(
          painter: _FadePainter(
            gradient: ComposerBottomFade.gradient(
              zoneHeight: zoneHeight,
              color: color ?? ChromeThemeScope.composerOf(context).contentFade,
              fadeHeight: fadeHeight,
            ),
          ),
        ),
      ),
    );
  }
}

class _FadePainter extends CustomPainter {
  _FadePainter({required this.gradient});

  final LinearGradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _FadePainter oldDelegate) =>
      oldDelegate.gradient != gradient;
}

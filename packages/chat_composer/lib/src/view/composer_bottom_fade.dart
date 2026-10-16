import 'package:chat_composer/src/view/composer_metrics.dart';
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
/// sibling) and pass the island's key as [glassKey], so the wash punches an
/// island-shaped hole. The island's glass then samples the content through
/// the hole, not the wash. While the island is unmounted (the host hides the
/// composer) [glassKey] has no context and the hole clears, the wash stays.
/// The fade does **not** rebuild when the island unmounts and [zoneHeight] is
/// unchanged, so the host passes [cutoutSync], a listenable that fires when
/// the island may have appeared or gone; otherwise the hole lingers until the
/// next height change.
class ComposerBottomFade extends StatefulWidget {
  /// Creates a fade of [zoneHeight] using [color], or the theme's content
  /// fade colour when none is given.
  const ComposerBottomFade({
    required this.zoneHeight,
    this.color,
    this.fadeHeight = defaultFadeHeight,
    this.glassKey,
    this.glassCornerRadius = ComposerMetrics.islandRadius,
    this.cutoutSync,
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

  /// Key on the glass island. Null or unmounted gives a full wash, no hole.
  final GlobalKey? glassKey;

  /// Corner radius of the DestinationOut hole (matches island).
  final double glassCornerRadius;

  /// Notifies when island visibility may change without [zoneHeight] changing.
  ///
  /// A host that hides the island but keeps its occupancy in the inset leaves
  /// [zoneHeight] unchanged; without this, the cutout never re-syncs and the
  /// hole stays.
  final Listenable? cutoutSync;

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
  State<ComposerBottomFade> createState() => ComposerBottomFadeState();
}

/// State of [ComposerBottomFade].
class ComposerBottomFadeState extends State<ComposerBottomFade> {
  /// Island rect in this fade's local coordinates; null = no hole.
  Rect? _cutout;
  var _syncScheduled = false;

  /// Test seam: local island hole, or `null` when the wash is unclipped.
  @visibleForTesting
  Rect? get debugCutout => _cutout;

  @override
  void initState() {
    super.initState();
    widget.cutoutSync?.addListener(_scheduleSync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant ComposerBottomFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.cutoutSync, widget.cutoutSync)) {
      oldWidget.cutoutSync?.removeListener(_scheduleSync);
      widget.cutoutSync?.addListener(_scheduleSync);
    }
    if (oldWidget.zoneHeight != widget.zoneHeight ||
        oldWidget.glassKey != widget.glassKey ||
        oldWidget.glassCornerRadius != widget.glassCornerRadius) {
      _scheduleSync();
    }
  }

  @override
  void dispose() {
    widget.cutoutSync?.removeListener(_scheduleSync);
    super.dispose();
  }

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      _syncCutout();
      // Island can unmount later in this frame (selection) without a fade
      // rebuild. Probe once more while a hole is punched.
      if (_cutout != null) _scheduleSync();
    });
  }

  void _syncCutout() {
    final key = widget.glassKey;
    final glassContext = key?.currentContext;
    if (glassContext == null) {
      _setCutout(null);
      return;
    }

    final glassBox = glassContext.findRenderObject() as RenderBox?;
    final fadeBox = context.findRenderObject() as RenderBox?;
    if (glassBox == null ||
        !glassBox.hasSize ||
        fadeBox == null ||
        !fadeBox.hasSize) {
      _setCutout(null);
      // Glass may still be laying out — try again next frame.
      _scheduleSync();
      return;
    }

    final topLeft = fadeBox.globalToLocal(glassBox.localToGlobal(Offset.zero));
    final next = topLeft & glassBox.size;
    final bounds = Offset.zero & fadeBox.size;
    // Only punch where the island intersects the fade layer.
    final clipped = next.intersect(bounds);
    _setCutout(clipped.isEmpty ? null : clipped);
  }

  bool _cutoutChanged(Rect? a, Rect? b) {
    if (identical(a, b)) return false;
    if (a == null || b == null) return a != b;
    return (a.left - b.left).abs() > 0.5 ||
        (a.top - b.top).abs() > 0.5 ||
        (a.width - b.width).abs() > 0.5 ||
        (a.height - b.height).abs() > 0.5;
  }

  void _setCutout(Rect? next) {
    if (!_cutoutChanged(_cutout, next)) return;
    setState(() => _cutout = next);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.zoneHeight <= 0) return const SizedBox.shrink();

    // Re-measure after this build (resize / first layout).
    _scheduleSync();

    return AbsorbPointer(
      child: SizedBox(
        height: widget.zoneHeight,
        width: double.infinity,
        child: CustomPaint(
          painter: _FadeWithCutoutPainter(
            gradient: ComposerBottomFade.gradient(
              zoneHeight: widget.zoneHeight,
              color:
                  widget.color ??
                  ChromeThemeScope.composerOf(context).contentFade,
              fadeHeight: widget.fadeHeight,
            ),
            cutout: _cutout,
            cornerRadius: widget.glassCornerRadius,
          ),
        ),
      ),
    );
  }
}

class _FadeWithCutoutPainter extends CustomPainter {
  _FadeWithCutoutPainter({
    required this.gradient,
    required this.cutout,
    required this.cornerRadius,
  });

  final LinearGradient gradient;
  final Rect? cutout;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final shader = gradient.createShader(rect);

    final hole = cutout;
    if (hole == null || hole.isEmpty) {
      canvas.drawRect(rect, Paint()..shader = shader);
      return;
    }

    // Full wash, then clear the island so glass under this layer stays bright
    // and BackdropFilter samples chat — not the fade.
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..shader = shader);
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole, Radius.circular(cornerRadius)),
      Paint()..blendMode = BlendMode.dstOut,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FadeWithCutoutPainter oldDelegate) =>
      oldDelegate.cutout != cutout ||
      oldDelegate.cornerRadius != cornerRadius ||
      oldDelegate.gradient != gradient;
}

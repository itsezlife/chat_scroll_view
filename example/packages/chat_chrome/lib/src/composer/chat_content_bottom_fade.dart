import 'package:chat_chrome/src/composer/chat_input_metrics.dart';
import 'package:flutter/material.dart';

/// Soft bottom content fade under the composer / keyboard chrome.
///
/// Ports the color fast-path of Telegram's bottom
/// `BlurredBackgroundWithFadeDrawable` (`opacity: true`): a [fadeHeight]
/// ramp at the **top** of [zoneHeight], then a clamped semi-opaque wash to
/// the bottom edge.
///
/// **Stacking:** mount **under** the glass island (earlier [Stack] sibling)
/// and pass [glassKey] so the wash punches an island-shaped hole. The island
/// [BackdropFilter] then samples chat through the hole — not this wash. When
/// the island is unmounted (e.g. selection mode), [glassKey] has no context
/// and the hole clears — wash stays. The fade does **not** rebuild on island
/// unmount when [zoneHeight] is unchanged, so pass [cutoutSync] (selection
/// listenable) or the hole can linger until the next inset tick.
class ChatContentBottomFade extends StatefulWidget {
  /// Creates a bottom content fade of [zoneHeight] using [color].
  const ChatContentBottomFade({
    required this.zoneHeight,
    required this.color,
    this.fadeHeight = defaultFadeHeight,
    this.glassKey,
    this.glassCornerRadius = ChatInputMetrics.bubbleRadius,
    this.cutoutSync,
    super.key,
  });

  /// Soft-edge ramp (`setFadeHeightBottom(dp(48))`).
  static const double defaultFadeHeight = 48;

  /// Full fade zone from the physical bottom (inset + island + gaps).
  final double zoneHeight;

  /// Fill color ([ChatChromeColors.contentBottomFade] — not panel fill).
  final Color color;

  /// Height of the transparent→wash ramp at the top of the zone.
  final double fadeHeight;

  /// Key on the glass island. Null / unmounted → full wash, no hole.
  final GlobalKey? glassKey;

  /// Corner radius of the DestinationOut hole (matches island).
  final double glassCornerRadius;

  /// Notifies when island visibility may change without [zoneHeight] changing.
  ///
  /// Selection mode keeps composer occupancy in the inset but unmounts the
  /// glass; without this, cutout sync never runs and the hole stays.
  final Listenable? cutoutSync;

  /// Alpha stops for the opacity gradient (`createGradient(…, opacity=true)`).
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
  State<ChatContentBottomFade> createState() => ChatContentBottomFadeState();
}

/// State for [ChatContentBottomFade].
class ChatContentBottomFadeState extends State<ChatContentBottomFade> {
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
  void didUpdateWidget(covariant ChatContentBottomFade oldWidget) {
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

    final ramp = widget.fadeHeight.clamp(0.0, widget.zoneHeight);
    final stops = ChatContentBottomFade.opacityStops(widget.color);
    final end = widget.zoneHeight <= 0
        ? 1.0
        : (ramp / widget.zoneHeight).clamp(0.0, 1.0);
    final colors = <Color>[
      stops[0],
      stops[1],
      stops[2],
      stops[3],
      if (end < 1) stops[3],
    ];
    final positions = <double>[0, end / 3, end * 2 / 3, end, if (end < 1) 1];

    return IgnorePointer(
      child: SizedBox(
        height: widget.zoneHeight,
        width: double.infinity,
        child: CustomPaint(
          painter: _FadeWithCutoutPainter(
            colors: colors,
            positions: positions,
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
    required this.colors,
    required this.positions,
    required this.cutout,
    required this.cornerRadius,
  });

  final List<Color> colors;
  final List<double> positions;
  final Rect? cutout;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: positions,
    ).createShader(rect);

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
      oldDelegate.colors != colors ||
      oldDelegate.positions != positions;
}

import 'package:flutter/material.dart';

/// The chat's alphabets in every chat text style, for [GlyphWarmupLayer].
///
/// The atlas adds glyphs on the raster thread in the frame that first shows
/// them, and redrawing it costs milliseconds; a row scrolled in for the first
/// time can miss its frame on that alone. Glyphs are kept per size, weight,
/// scale and horizontal subpixel offset, so the warm-up draws each style at
/// four horizontal offsets, and at each scale the chat's text is drawn at:
/// a glass captures the chat below it at a pixel ratio of its own, and the
/// glyphs of that capture are entries of their own. Every glyph it adds is
/// redrawn whenever the atlas has to grow, so it warms only what the chat
/// draws.
abstract final class GlyphWarmup {
  static const String _charset =
      'abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 '
      'абвгдеёжзийклмнопрстуфхцчшщъыьэюя АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ '
      '.,:;!?…"'
      r"'«»()[]{}<>-–—_/\|@#$%^&*+=~`№";

  /// Body, its emphasis and code, and the chrome around it, in logical px.
  static const List<TextStyle> _styles = [
    TextStyle(fontSize: 15, height: 1.35),
    TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.bold),
    TextStyle(fontSize: 15, height: 1.35, fontStyle: FontStyle.italic),
    TextStyle(fontSize: 14, height: 1.35, fontFamily: 'monospace'),
    // Avatar initials and the unread separator.
    TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    TextStyle(fontSize: 13, height: 1.15, fontWeight: FontWeight.w600),
    TextStyle(fontSize: 13),
    TextStyle(fontSize: 11, height: 1),
  ];

  static const Color _unseen = Color(0x01000000);

  /// The height of the rows at one scale, in logical px at scale 1.
  static const double _rows = 4 * 24.0;

  /// Paints every style at four horizontal subpixel offsets at each of
  /// [scales], ending at [bottom].
  static void paint(
    Canvas canvas,
    double bottom, {
    List<double> scales = const [1],
  }) {
    final height = _styles.length * _rows * scales.fold(0.0, (a, b) => a + b);
    var y = bottom - height;
    for (final style in _styles) {
      final painter = TextPainter(
        // Glyphs are cached by shape, not colour: an alpha nobody sees warms
        // the same entries as the chat's own text.
        text: TextSpan(
          text: _charset,
          style: style.copyWith(color: _unseen),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 2000);
      for (final scale in scales) {
        canvas
          ..save()
          ..translate(0, y)
          ..scale(scale);
        for (var i = 0; i < 4; i++) {
          // A quarter of a device pixel apart, whatever the scale.
          painter.paint(canvas, Offset(i / 4 / scale, i * 24.0));
        }
        canvas.restore();
        y += _rows * scale;
      }
      painter.dispose();
    }
  }
}

/// Paints [GlyphWarmup] under [child] for the first two frames of the app
/// run, so the glyph atlas holds the chat's glyphs before the chat shows
/// them.
///
/// Above the navigator it warms while the first page shows, before any chat
/// opens: the atlas grows, and is drawn again whole, in a frame nothing
/// animates in, not in the route transition bringing the chat in. The text
/// is drawn at an alpha nobody sees, under [child].
class GlyphWarmupLayer extends StatefulWidget {
  /// Warms under [child] when [enabled], at each of [scales].
  const GlyphWarmupLayer({
    required this.child,
    this.enabled = true,
    this.scales = const [1],
    super.key,
  });

  /// The scales the chat's text is drawn at, relative to the frame: 1, and
  /// each glass capture's pixel ratio over the device's.
  final List<double> scales;

  /// Whether the warm-up paints at all.
  final bool enabled;

  /// Lets the next layer warm again, as on a fresh app run.
  @visibleForTesting
  static void debugReset() => _GlyphWarmupLayerState._warmed = false;

  /// The opaque content drawn over the warm-up.
  final Widget child;

  @override
  State<GlyphWarmupLayer> createState() => _GlyphWarmupLayerState();
}

class _GlyphWarmupLayerState extends State<GlyphWarmupLayer> {
  static bool _warmed = false;

  /// Frames left to paint the warm-up in; once per app run.
  int _frames = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled || _warmed) return;
    _warmed = true;
    _frames = 2;
    WidgetsBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _onFrame(Duration _) {
    if (!mounted) return;
    setState(() => _frames--);
    if (_frames > 0) WidgetsBinding.instance.addPostFrameCallback(_onFrame);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    // The warm-up keeps its slot once done, so the child stays second and
    // is not rebuilt from scratch when the text goes.
    return Stack(
      // Both children fill it; no direction to resolve.
      alignment: Alignment.topLeft,
      children: [
        Positioned.fill(
          child: _frames > 0
              ? RepaintBoundary(
                  child: CustomPaint(painter: _WarmupPainter(widget.scales)),
                )
              : const SizedBox.shrink(),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _WarmupPainter extends CustomPainter {
  const _WarmupPainter(this.scales);

  final List<double> scales;

  @override
  void paint(Canvas canvas, Size size) =>
      GlyphWarmup.paint(canvas, size.height, scales: scales);

  @override
  bool shouldRepaint(_WarmupPainter oldDelegate) => false;
}

import 'package:flutter/material.dart';

/// The chat's alphabets in every chat text style, for [GlyphWarmupLayer].
///
/// The atlas adds glyphs on the raster thread in the frame that first shows
/// them, and redrawing it costs milliseconds; a row scrolled in for the first
/// time can miss its frame on that alone. Glyphs are kept per size, weight,
/// scale and horizontal subpixel offset, so the warm-up draws each style at
/// four horizontal offsets. Every glyph it adds is redrawn whenever the
/// atlas has to grow, so it warms only what the chat draws.
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

  static double get _height => _styles.length * 4 * 24.0;

  /// Paints every style at four horizontal subpixel offsets, ending at
  /// [bottom].
  static void paint(Canvas canvas, double bottom) {
    var y = bottom - _height;
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
      for (var i = 0; i < 4; i++) {
        painter.paint(canvas, Offset(i / 4, y));
        y += 24;
      }
      painter.dispose();
    }
  }
}

/// Paints [GlyphWarmup] under [child] for the first two frames of the app
/// run, so the glyph atlas holds the chat's glyphs before a scroll needs
/// them.
///
/// Inside a glass source the glass captures the warm-up too, at the scale it
/// captures the chat at, so its glyphs warm as well. The text is drawn at an
/// alpha nobody sees, under [child].
class GlyphWarmupLayer extends StatefulWidget {
  /// Warms under [child] when [enabled].
  const GlyphWarmupLayer({required this.child, this.enabled = true, super.key});

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
              ? const RepaintBoundary(
                  child: CustomPaint(painter: _WarmupPainter()),
                )
              : const SizedBox.shrink(),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _WarmupPainter extends CustomPainter {
  const _WarmupPainter();

  @override
  void paint(Canvas canvas, Size size) =>
      GlyphWarmup.paint(canvas, size.height);

  @override
  bool shouldRepaint(_WarmupPainter oldDelegate) => false;
}

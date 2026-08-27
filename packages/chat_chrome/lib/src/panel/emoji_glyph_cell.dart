import 'package:chat_chrome/src/motion/scale_pressable.dart';
import 'package:chat_chrome/src/panel/emoji_glyph.dart';
import 'package:chat_chrome/src/panel/emoji_page.dart';
import 'package:flutter/material.dart';

/// One emoji grid cell with press feedback.
///
/// Provides:
/// - Press scale (linear press-in, overshoot release — see [releaseDuration] /
///   [releaseTension]).
/// - Soft rounded ripple via [Material] + [InkWell] is **temporarily disabled**
///   (see restore block in [build]); scale-only feedback for now.
///
/// [AnimationController] is created lazily on first press so idle mounts skip
/// ticker allocation. Scale starts on pointer DOWN ([Listener]); release on
/// pointer UP / cancel.
class EmojiGlyphCell extends StatefulWidget {
  /// Creates the cell.
  const EmojiGlyphCell({
    required this.glyph,
    required this.cellSize,
    required this.onTap,
    this.onLongPressStart,
    this.onLongPressMove,
    this.onLongPressEnd,
    super.key,
  });

  /// Unicode glyph to paint.
  final String glyph;

  /// Hit-target / layout pitch for the cell.
  final double cellSize;

  /// Fired on tap.
  final VoidCallback onTap;

  /// Optional long-press start (skin-tone picker / clear-recents request).
  ///
  /// When null, [onLongPressMove] / [onLongPressEnd] MUST also be null —
  /// any non-null long-press callback registers a recognizer that cancels tap.
  final GestureLongPressStartCallback? onLongPressStart;

  /// Optional long-press drag update while the picker is open.
  final GestureLongPressMoveUpdateCallback? onLongPressMove;

  /// Optional long-press end.
  final GestureLongPressEndCallback? onLongPressEnd;

  /// Nominal corner radius in density-independent units before platform
  /// density scaling (see [selectorRadiusOf]).
  ///
  /// Kept for [Material]/[InkWell] restore (see build restore block).
  static const double selectorRadiusDp = 2;

  /// Corner radius of the press highlight on the current device.
  ///
  /// Reference clients apply density conversion twice to the nominal
  /// [selectorRadiusDp] (convert to device pixels, then treat those pixels as
  /// density-independent units again). Effective radius ≈
  /// `selectorRadiusDp × devicePixelRatio` logical pixels (6 on 3×).
  ///
  /// Kept for [Material]/[InkWell] restore (see build restore block).
  static double selectorRadiusOf(BuildContext context) =>
      selectorRadiusDp * MediaQuery.devicePixelRatioOf(context);

  /// List-selector tint for light chrome (`0x0f000000`).
  ///
  /// Kept for [Material]/[InkWell] restore (see build restore block).
  static const Color listSelectorLight = Color(0x0F000000);

  /// Night-friendly list selector (~6% white).
  ///
  /// Kept for [Material]/[InkWell] restore (see build restore block).
  static const Color listSelectorDark = Color(0x0FFFFFFF);

  /// Release settle duration (overshoot curve / 350ms).
  static const Duration releaseDuration = Duration(milliseconds: 350);

  /// Overshoot tension for [releaseDuration] settle ([OvershootCurve]).
  static const double releaseTension = 5;

  @override
  State<EmojiGlyphCell> createState() => _EmojiGlyphCellState();
}

class _EmojiGlyphCellState extends State<EmojiGlyphCell>
    with SingleTickerProviderStateMixin {
  /// `1` = fully pressed, `0` = idle; may go slightly negative on overshoot.
  /// Null until first press — idle mounts skip ticker allocation.
  AnimationController? _pressed;
  var _pointerDown = false;

  AnimationController get _ensurePressed {
    return _pressed ??= AnimationController(
      vsync: this,
      value: 0,
      lowerBound: -0.35,
      upperBound: 1,
    );
  }

  @override
  void dispose() {
    _pressed?.dispose();
    super.dispose();
  }

  double get _pressStep {
    final hz = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .display
        .refreshRate
        .clamp(30.0, 120.0);
    return (1000.0 / hz).clamp(0.0, 40.0) / 100.0;
  }

  Duration _pressInDuration(AnimationController pressed) {
    final hz = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .display
        .refreshRate
        .clamp(30.0, 120.0);
    final remaining = (1 - pressed.value).clamp(0.0, 1.0);
    final step = _pressStep;
    final frames = step <= 0 ? 6.0 : remaining / step;
    return Duration(
      milliseconds: (frames * (1000 / hz)).round().clamp(16, 200),
    );
  }

  void _pressIn() {
    if (_pointerDown) return;
    _pointerDown = true;
    final pressed = _ensurePressed;
    pressed.stop();
    // One paint step immediately so UP before the first ticker
    // tick still has progress to spring from.
    pressed.value = (pressed.value + _pressStep).clamp(0.0, 1.0);
    pressed.animateTo(
      1,
      duration: _pressInDuration(pressed),
      curve: Curves.linear,
    );
    if (mounted) setState(() {});
  }

  void _pressOut() {
    _pointerDown = false;
    final pressed = _pressed;
    if (pressed == null) return;
    if (pressed.value == 0 && !pressed.isAnimating) return;
    // Guarantees release spring even when DOWN→UP was shorter than one frame.
    if (pressed.value < _pressStep) {
      pressed.value = _pressStep;
    }
    pressed.animateTo(
      0,
      duration: EmojiGlyphCell.releaseDuration,
      curve: const OvershootCurve(EmojiGlyphCell.releaseTension),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paint = (EmojiPage.glyphSize / widget.cellSize).clamp(0.55, 0.92);
    final glyph = EmojiGlyph(
      glyph: widget.glyph,
      size: widget.cellSize,
      paintFraction: paint,
    );

    final scaled = switch (_pressed) {
      final pressed? => AnimatedBuilder(
        animation: pressed,
        builder: (context, child) {
          final scale = 0.8 + 0.2 * (1 - pressed.value);
          return Transform.scale(scale: scale, child: child);
        },
        child: glyph,
      ),
      null => glyph,
    };

    // [Listener] starts scale on DOWN before the gesture arena (quick taps).
    //
    // Long-press callbacks are all-or-nothing: any non-null long-press slot
    // registers a recognizer that cancels [GestureDetector.onTap] after the
    // timeout.
    //
    // --- RESTORE Material + InkWell (soft list-selector ripple) -------------
    // [InkWell.onHighlightChanged] cancels scale when the finger leaves the
    // cell — same bounds check Material uses for ink, which [Listener] alone
    // does not get on MOVE.
    //
    // final ink = Theme.brightnessOf(context) == Brightness.dark
    //     ? EmojiGlyphCell.listSelectorDark
    //     : EmojiGlyphCell.listSelectorLight;
    // final selectorRadius = EmojiGlyphCell.selectorRadiusOf(context);
    // final radius = BorderRadius.circular(selectorRadius);
    //
    // Then wrap `scaled` (instead of passing it as GestureDetector.child) and
    // remove [GestureDetector.onTap] (InkWell owns tap):
    //
    // Material(
    //   type: MaterialType.transparency,
    //   child: InkWell(
    //     borderRadius: radius,
    //     splashColor: ink,
    //     highlightColor: ink,
    //     onTap: widget.onTap,
    //     onHighlightChanged: (highlighted) {
    //       if (highlighted) {
    //         _pressIn();
    //         return;
    //       }
    //       _pressOut();
    //     },
    //     child: scaled,
    //   ),
    // )
    // -----------------------------------------------------------------------
    final longPress = widget.onLongPressStart;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _pressIn(),
      onPointerUp: (_) => _pressOut(),
      onPointerCancel: (_) => _pressOut(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPressStart: longPress,
        onLongPressMoveUpdate: longPress != null
            ? widget.onLongPressMove
            : null,
        onLongPressEnd: longPress != null ? widget.onLongPressEnd : null,
        child: scaled,
      ),
    );
  }
}

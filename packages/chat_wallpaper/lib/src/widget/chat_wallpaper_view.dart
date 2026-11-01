import 'dart:async';
import 'dart:ui' as ui;

import 'package:chat_wallpaper/src/model/chat_wallpaper.dart';
import 'package:chat_wallpaper/src/motion/chat_wallpaper_motion_controller.dart';
import 'package:chat_wallpaper/src/motion/freeform_keyframes.dart';
import 'package:chat_wallpaper/src/render/freeform_gradient.dart';
import 'package:chat_wallpaper/src/render/wallpaper_pattern_image.dart';
import 'package:chat_wallpaper/src/widget/chat_wallpaper_patterns.dart';
import 'package:chat_wallpaper/src/widget/patterned_fill.dart';
import 'package:flutter/widgets.dart';

/// Paints a [ChatWallpaper] across its whole box.
///
/// ## Layout and painting
///
/// Fills the incoming constraints (they must be bounded) and paints inside
/// its own [RepaintBoundary], so content scrolling or animating above it
/// never repaints the wallpaper. It draws nothing but the fill and takes no
/// input; hosts stack it as the bottom layer and size it to the surface that
/// must stay still, e.g. a box that does not shrink when the keyboard opens.
///
/// ## Fills
///
/// - Freeform: the [FreeformGradient] raster, cover-fit and upscaled with
///   bilinear filtering. Rasterizing completes asynchronously; until then the
///   view paints [ChatWallpaper.averageColor], so the first frame already
///   carries the wallpaper's tone instead of an unrelated colour.
///   - Without [motion]: the raster at phase 0. The view owns the decoded
///     image and disposes it when the fill leaves the tree.
///   - With [motion]: the raster at the controller's phase and progress,
///     painted from keyframes the controller shares with every other view
///     painting the same value under it. During a run the view paints one
///     keyframe with its neighbour crossfaded over it; at rest, one image.
///     The controller keeps and warms the wallpaper's whole ring of
///     keyframes while it is held, so a run on a warm ring paints held
///     keyframes from its first frame, and every copy paints the same
///     images across step boundaries.
///     The view holds the keyframes while the fill is in the tree and
///     releases them when it leaves. Keyframes the controller already
///     holds — for another view, or for a `ChatWallpaperWarmUp` under the
///     same controller — paint on the view's first frame once one has
///     landed.
/// - Solid: its colour, flat.
/// - Linear: a [LinearGradient] from [ChatWallpaper$Linear.top] to
///   [ChatWallpaper$Linear.bottom]. The first colour starts at the edge
///   midpoint or corner its [WallpaperRotation] names and the second ends at
///   the opposite point, so diagonals run corner to corner whatever the box's
///   aspect ratio.
///
/// Solid and linear fills are opaque: colours' own alpha is ignored, as it is
/// for freeform rasters.
///
/// ## Patterns
///
/// A [ChatWallpaper$Patterned] paints its fill as above, with the pattern
/// artwork from the nearest [ChatWallpaperPatterns] composited over it. The
/// artwork is rasterized through [WallpaperPatternImage] once per display, at
/// its shorter side in physical pixels, so every view shares one raster per
/// pattern and a window resize or rotation rasterizes nothing. It is drawn
/// cover-fit and centred, scaled to the window ([MediaQuery], which must be
/// an ancestor): a view smaller than the window (a thumbnail) crops the
/// pattern instead of shrinking it, keeping shapes at the size a
/// full-window view draws them.
///
/// - [WallpaperPatternBlend.softLight]: the fill, then the pattern recoloured
///   with an `srcIn` colour filter — black over a light fill, white over a
///   dark one ([ChatWallpaper.isDark]) — at [WallpaperPattern.opacity], with
///   the soft-light blend mode.
/// - [WallpaperPatternBlend.mask]: the fill kept at
///   [WallpaperPattern.opacity] where the pattern is opaque, black where it
///   is transparent.
///
/// Until the raster is ready — and for good when no artwork is registered
/// for the slug — the fill paints alone. Once it lands the fill keeps its
/// state, so a freeform fill is not rasterized again. A raster already in
/// the cache composites at full strength on the first frame; a
/// `ChatWallpaperWarmUp` above the view keeps it there. A raster that lands
/// after the view mounted fades in from the bare fill over
/// [patternFadeDuration], or appears at once while
/// [MediaQuery.disableAnimationsOf] is set.
///
/// ## Changes
///
/// A [wallpaper] that differs by value crossfades from the old fill to the new
/// one over [crossfadeDuration] along [crossfadeCurve]. An equal value keeps
/// the current fill and its image; the first build appears without a
/// transition. A change of pattern intensity alone repaints in place,
/// without a crossfade and without restarting a running pattern fade, so a
/// live intensity control stays cheap and direct.
class ChatWallpaperView extends StatelessWidget {
  /// Paints [wallpaper], moving with [motion] when given.
  const ChatWallpaperView({required this.wallpaper, this.motion, super.key});

  /// Length of the crossfade when [wallpaper] changes.
  static const Duration crossfadeDuration = Duration(milliseconds: 200);

  /// Easing of the crossfade when [wallpaper] changes, for both the incoming
  /// and the outgoing fill. Hosts that move other colors with the wallpaper
  /// pair it with [crossfadeDuration] to stay on the same timeline.
  static const Curve crossfadeCurve = Curves.linear;

  /// Length of the fade-in of a pattern whose raster lands after the view
  /// mounted.
  static const Duration patternFadeDuration = Duration(milliseconds: 250);

  /// Wallpaper to paint.
  final ChatWallpaper wallpaper;

  /// Phase source and keyframe owner for a freeform fill; `null` paints a
  /// static phase 0. Views that must match pixel for pixel share one
  /// controller.
  final ChatWallpaperMotionController? motion;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedSwitcher(
      duration: crossfadeDuration,
      switchInCurve: crossfadeCurve,
      switchOutCurve: crossfadeCurve,
      layoutBuilder: _expand,
      child: switch (wallpaper) {
        final ChatWallpaper$ColorFill fill => _fill(fill),
        ChatWallpaper$Patterned(:final fill, :final pattern) => PatternedFill(
          key: ValueKey((fill, pattern.slug, pattern.blend)),
          pattern: pattern,
          darkFill: wallpaper.isDark,
          fadeDuration: patternFadeDuration,
          fill: fill,
          motion: motion,
          child: _fill(fill),
        ),
      },
    ),
  );

  Widget _fill(ChatWallpaper$ColorFill fill) => switch (fill) {
    final ChatWallpaper$Freeform freeform => switch (motion) {
      final motion? => _MovingFreeformFill(
        key: ValueKey(freeform),
        wallpaper: freeform,
        motion: motion,
      ),
      null => _FreeformFill(key: ValueKey(freeform), wallpaper: freeform),
    },
    ChatWallpaper$Solid(:final color) => ColoredBox(
      key: ValueKey(fill),
      color: color.withAlpha(0xFF),
    ),
    ChatWallpaper$Linear(:final top, :final bottom, :final rotation) =>
      DecoratedBox(
        key: ValueKey(fill),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: rotation.startAlignment,
            end: -rotation.startAlignment,
            colors: [top.withAlpha(0xFF), bottom.withAlpha(0xFF)],
          ),
        ),
      ),
  };

  /// Stacks the outgoing and incoming fills at full size; the default
  /// switcher layout would hand them loose constraints and a childless
  /// [ColoredBox] would collapse to nothing.
  static Widget _expand(Widget? current, List<Widget> previous) =>
      Stack(fit: StackFit.expand, children: [...previous, ?current]);
}

/// Freeform fill that owns its rasterized image.
///
/// Keyed by its wallpaper, so a different value always gets a fresh state and
/// [didUpdateWidget] never has to swap images.
class _FreeformFill extends StatefulWidget {
  const _FreeformFill({required this.wallpaper, super.key});

  final ChatWallpaper$Freeform wallpaper;

  @override
  State<_FreeformFill> createState() => _FreeformFillState();
}

class _FreeformFillState extends State<_FreeformFill> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    unawaited(_rasterize());
  }

  /// Decodes the raster; an image that arrives after unmount is disposed
  /// straight away instead of leaking.
  Future<void> _rasterize() async {
    final image = await FreeformGradient.image(widget.wallpaper);
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() => _image = image);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (_image) {
    final image? => _rasterImage(image),
    null => ColoredBox(color: widget.wallpaper.averageColor),
  };
}

/// Freeform fill painted from [motion]'s shared keyframes.
///
/// Repaints, without rebuilding, on every motion tick and whenever a keyframe
/// lands; each paint draws at most two images, so no raster work happens per
/// frame.
class _MovingFreeformFill extends StatefulWidget {
  const _MovingFreeformFill({
    required this.wallpaper,
    required this.motion,
    super.key,
  });

  final ChatWallpaper$Freeform wallpaper;
  final ChatWallpaperMotionController motion;

  @override
  State<_MovingFreeformFill> createState() => _MovingFreeformFillState();
}

class _MovingFreeformFillState extends State<_MovingFreeformFill> {
  late FreeformKeyframes _keyframes;

  /// Motion ticks and keyframe arrivals: each changes the frame to paint.
  late Listenable _frameChanges;

  @override
  void initState() {
    super.initState();
    _hold(widget.motion);
  }

  @override
  void didUpdateWidget(_MovingFreeformFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.motion, widget.motion)) return;
    oldWidget.motion.releaseKeyframes(widget.wallpaper);
    _hold(widget.motion);
  }

  void _hold(ChatWallpaperMotionController motion) {
    _keyframes = motion.acquireKeyframes(widget.wallpaper);
    _frameChanges = Listenable.merge([motion, _keyframes]);
  }

  @override
  void dispose() {
    widget.motion.releaseKeyframes(widget.wallpaper);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: CustomPaint(
      painter: _FreeformFramePainter(
        keyframes: _keyframes,
        motion: widget.motion,
        averageColor: widget.wallpaper.averageColor,
        repaint: _frameChanges,
      ),
    ),
  );
}

/// Paints the frame [keyframes] hold for [motion]'s current phase and
/// progress, or [averageColor] before the first keyframe lands.
class _FreeformFramePainter extends CustomPainter {
  _FreeformFramePainter({
    required this.keyframes,
    required this.motion,
    required this.averageColor,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final FreeformKeyframes keyframes;
  final ChatWallpaperMotionController motion;
  final Color averageColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    switch (keyframes.frameAt(phase: motion.phase, progress: motion.progress)) {
      case null:
        canvas.drawRect(rect, Paint()..color = averageColor);
      case (:final base, :final overlay, :final overlayOpacity):
        _paintRaster(canvas, rect, base);
        if (overlay != null)
          _paintRaster(canvas, rect, overlay, opacity: overlayOpacity);
    }
  }

  @override
  bool shouldRepaint(_FreeformFramePainter oldDelegate) =>
      !identical(oldDelegate.keyframes, keyframes) ||
      !identical(oldDelegate.motion, motion) ||
      oldDelegate.averageColor != averageColor;
}

/// A freeform raster drawn cover-fit with the bilinear upscale that is part of its look.
Widget _rasterImage(ui.Image image) =>
    RawImage(image: image, fit: _rasterFit, filterQuality: _rasterFilter);

/// Paints [image] into [rect] the way [_rasterImage] lays it out.
void _paintRaster(
  Canvas canvas,
  Rect rect,
  ui.Image image, {
  double opacity = 1,
}) => paintImage(
  canvas: canvas,
  rect: rect,
  image: image,
  fit: _rasterFit,
  filterQuality: _rasterFilter,
  opacity: opacity,
);

const BoxFit _rasterFit = BoxFit.cover;
const FilterQuality _rasterFilter = FilterQuality.low;

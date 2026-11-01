/// @docImport 'package:chat_wallpaper/src/widget/chat_wallpaper_view.dart';
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chat_wallpaper/src/model/chat_wallpaper.dart';
import 'package:chat_wallpaper/src/model/wallpaper_service_shade.dart';
import 'package:chat_wallpaper/src/motion/chat_wallpaper_motion_controller.dart';
import 'package:chat_wallpaper/src/motion/freeform_keyframes.dart';
import 'package:chat_wallpaper/src/render/freeform_gradient.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The box a chat wallpaper covers, lending its gradient to the service
/// chrome drawn inside it.
///
/// Wrap the box whose full extent a [ChatWallpaperView] fills — the view and
/// the content stacked over it — and pass the same [wallpaper] and [motion]
/// the view paints. Every [WallpaperServiceFill] below then fills its shape
/// with the part of the gradient behind it, through the
/// [WallpaperServiceShade] for [darkTheme].
///
/// Fills paint the gradient without the pattern, from the same keyframes the
/// view shows under [motion], so they move with the wallpaper frame by frame.
/// Only a [ChatWallpaper.freeformFill] has a gradient to lend: over a solid or
/// linear wallpaper the surface offers nothing and fills paint their fallback.
class ChatWallpaperSurface extends StatefulWidget {
  /// Lends [wallpaper]'s gradient, moving with [motion], to fills in [child].
  const ChatWallpaperSurface({
    required this.wallpaper,
    required this.darkTheme,
    required this.child,
    this.motion,
    super.key,
  });

  /// Wallpaper the [ChatWallpaperView] in this box paints.
  final ChatWallpaper wallpaper;

  /// Whether the app theme is dark; picks the [WallpaperServiceShade].
  final bool darkTheme;

  /// Motion controller the view paints with; `null` for a static phase 0.
  final ChatWallpaperMotionController? motion;

  /// The wallpaper view and everything drawn over it.
  final Widget child;

  @override
  State<ChatWallpaperSurface> createState() => _ChatWallpaperSurfaceState();
}

class _ChatWallpaperSurfaceState extends State<ChatWallpaperSurface> {
  final _backdrop = _ServiceBackdrop();

  @override
  void initState() {
    super.initState();
    _configure();
  }

  @override
  void didUpdateWidget(ChatWallpaperSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  void _configure() => _backdrop.configure(
    widget.wallpaper,
    motion: widget.motion,
    darkTheme: widget.darkTheme,
  );

  @override
  void dispose() {
    _backdrop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _BackdropScope(
    backdrop: _backdrop,
    lendsGradient: _backdrop.shade != null,
    child: _SurfaceBox(backdrop: _backdrop, child: widget.child),
  );
}

/// Fills a rounded box behind [child] with the wallpaper gradient behind it.
///
/// Under a [ChatWallpaperSurface] that lends a gradient, paints [borderRadius]
/// over its box at [fillOpacity]: the gradient without its pattern, cover-fit
/// and aligned to the surface exactly as the wallpaper view draws it, through
/// [shade] or else the surface's [WallpaperServiceShade]. It repaints as the
/// wallpaper moves and whenever it moves inside the surface — scrolled,
/// transformed, laid out anew — even when no ancestor repaints, one frame
/// after the move.
///
/// Anywhere else — no surface, or one over a solid or linear wallpaper —
/// paints [fallback] instead, also at [fillOpacity].
class WallpaperServiceFill extends StatelessWidget {
  /// Fills [borderRadius] behind [child], or paints [fallback].
  const WallpaperServiceFill({
    required this.borderRadius,
    required this.fallback,
    required this.child,
    this.fillOpacity = 1,
    this.shade,
    super.key,
  }) : assert(
         fillOpacity >= 0 && fillOpacity <= 1,
         'fillOpacity must be in [0, 1], got $fillOpacity',
       );

  /// Corners of the filled box.
  ///
  /// With [BorderRadius.zero] the shaded fill snaps its edges to the
  /// nearest physical pixel (unless the box is rotated or skewed) and draws
  /// without anti-aliasing, so square fills on abutting boxes meet without a
  /// seam even off the pixel grid; each may grow or shrink by up to half a
  /// physical pixel per edge. [fallback] paints as its decoration does.
  final BorderRadius borderRadius;

  /// Decoration painted when no surface lends a gradient.
  final Decoration fallback;

  /// Content drawn over the fill.
  final Widget child;

  /// Opacity of the fill alone, in `[0, 1]`; the default `1` paints it
  /// opaque.
  ///
  /// Scales whichever fill paints — the shaded gradient, its flat colour
  /// before the first keyframe lands, or [fallback] — as one layer, so what
  /// lies behind shows through it evenly and the fill's own overlapping parts
  /// never show through each other. [child] paints over the fill, unscaled.
  ///
  /// At `0` the shaded gradient is skipped outright, with no layer pushed.
  final double fillOpacity;

  /// Shade this fill passes the gradient through, or `null` for the
  /// surface's own ([WallpaperServiceShade.of] its wallpaper and theme).
  ///
  /// Only picks how a lent gradient is shaded: whether one is lent is still
  /// the surface's call, so [fallback] paints wherever it would without it.
  final WallpaperServiceShade? shade;

  /// Whether fills built with [context] paint the wallpaper gradient rather
  /// than their fallback. Registers a dependency, like the fills themselves.
  static bool lendsGradient(BuildContext context) =>
      _BackdropScope.maybeOf(context) != null;

  @override
  Widget build(BuildContext context) =>
      switch (_BackdropScope.maybeOf(context)) {
        final backdrop? => _ServiceFillBox(
          backdrop: backdrop,
          borderRadius: borderRadius,
          fillOpacity: fillOpacity,
          shade: shade,
          devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
          child: child,
        ),
        null => DecoratedBox(
          decoration: fillOpacity == 1
              ? fallback
              : _FadedDecoration(fallback, opacity: fillOpacity),
          child: child,
        ),
      };
}

/// What a surface lends its fills: the gradient's keyframes, the shade, and
/// the box the wallpaper covers. Notifies when any of them changes what a
/// fill paints.
final class _ServiceBackdrop extends ChangeNotifier {
  ChatWallpaper$Freeform? _fill;
  ChatWallpaperMotionController? _motion;
  FreeformKeyframes? _keyframes;
  WallpaperServiceShade? _shade;
  RenderBox? _surface;
  bool _disposed = false;

  final Set<_RenderServiceFill> _fills = {};
  bool _checkScheduled = false;

  /// Shade applied to the gradient; `null` when there is no gradient to lend.
  WallpaperServiceShade? get shade => _shade;

  /// Gradient the wallpaper shows under the motion's current phase.
  ChatWallpaper$Freeform? get fill => _fill;

  /// Frame the wallpaper view paints right now, or `null` before the first
  /// keyframe lands.
  FreeformFrame? get frame => _keyframes?.frameAt(
    phase: _motion?.phase ?? 0,
    progress: _motion?.progress ?? 1,
  );

  void configure(
    ChatWallpaper wallpaper, {
    required ChatWallpaperMotionController? motion,
    required bool darkTheme,
  }) {
    final fill = wallpaper.freeformFill;
    final shade = WallpaperServiceShade.of(wallpaper, darkTheme: darkTheme);
    final refill = fill != _fill || !identical(motion, _motion);
    if (!refill && shade == _shade) return;
    if (refill) {
      _release();
      _fill = fill;
      _motion = motion;
      _hold();
    }
    _shade = shade;
    notifyListeners();
  }

  /// Takes the fill's keyframes: shared with the view under a motion
  /// controller, owned here without one — phase 0 alone, since nothing runs.
  void _hold() {
    final fill = _fill;
    if (fill == null) return;
    _keyframes =
        (_motion?.acquireKeyframes(fill) ??
              FreeformKeyframes(fill, from: 0, warmsRing: false))
          ..addListener(notifyListeners);
    _motion?.addListener(notifyListeners);
  }

  void _release() {
    final (fill, keyframes) = (_fill, _keyframes);
    if (fill == null || keyframes == null) return;
    keyframes.removeListener(notifyListeners);
    switch (_motion) {
      case final motion?:
        motion
          ..removeListener(notifyListeners)
          ..releaseKeyframes(fill);
      case null:
        keyframes.dispose();
    }
    _keyframes = null;
  }

  void _track(_RenderServiceFill fill) {
    _fills.add(fill);
    _scheduleCheck();
  }

  void _untrack(_RenderServiceFill fill) => _fills.remove(fill);

  /// Checks every tracked fill's placement after each frame that runs while
  /// fills are mounted. The callback waits for a frame rather than scheduling
  /// one, so an idle surface costs nothing.
  void _scheduleCheck() {
    if (_checkScheduled || _fills.isEmpty || _disposed) return;
    _checkScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      for (final fill in _fills.toList()) {
        fill._repaintIfMoved();
      }
      _scheduleCheck();
    }, debugLabel: 'WallpaperServiceFill.placement');
  }

  @override
  void dispose() {
    _disposed = true;
    _release();
    _fills.clear();
    super.dispose();
  }
}

class _BackdropScope extends InheritedWidget {
  const _BackdropScope({
    required this.backdrop,
    required this.lendsGradient,
    required super.child,
  });

  final _ServiceBackdrop backdrop;
  final bool lendsGradient;

  static _ServiceBackdrop? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_BackdropScope>();
    return scope != null && scope.lendsGradient ? scope.backdrop : null;
  }

  @override
  bool updateShouldNotify(_BackdropScope oldWidget) =>
      lendsGradient != oldWidget.lendsGradient ||
      !identical(backdrop, oldWidget.backdrop);
}

class _SurfaceBox extends SingleChildRenderObjectWidget {
  const _SurfaceBox({required this.backdrop, super.child});

  final _ServiceBackdrop backdrop;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSurface(backdrop);
}

class _RenderSurface extends RenderProxyBox {
  _RenderSurface(this._backdrop);

  final _ServiceBackdrop _backdrop;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _backdrop._surface = this;
  }

  @override
  void detach() {
    if (identical(_backdrop._surface, this)) _backdrop._surface = null;
    super.detach();
  }
}

class _ServiceFillBox extends SingleChildRenderObjectWidget {
  const _ServiceFillBox({
    required this.backdrop,
    required this.borderRadius,
    required this.fillOpacity,
    required this.shade,
    required this.devicePixelRatio,
    super.child,
  });

  final _ServiceBackdrop backdrop;
  final BorderRadius borderRadius;
  final double fillOpacity;
  final WallpaperServiceShade? shade;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderServiceFill(
    backdrop: backdrop,
    borderRadius: borderRadius,
    fillOpacity: fillOpacity,
    shade: shade,
    devicePixelRatio: devicePixelRatio,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderServiceFill renderObject,
  ) => renderObject
    ..backdrop = backdrop
    ..borderRadius = borderRadius
    ..fillOpacity = fillOpacity
    ..shade = shade
    ..devicePixelRatio = devicePixelRatio;
}

/// Where a fill sits: its transform into the surface, and the surface size
/// the gradient is cover-fit to.
typedef _Placement = ({Matrix4 toSurface, Size surface});

class _RenderServiceFill extends RenderProxyBox {
  _RenderServiceFill({
    required _ServiceBackdrop backdrop,
    required BorderRadius borderRadius,
    required double fillOpacity,
    required WallpaperServiceShade? shade,
    required double devicePixelRatio,
  }) : _backdrop = backdrop,
       _borderRadius = borderRadius,
       _fillOpacity = fillOpacity,
       _shade = shade,
       _devicePixelRatio = devicePixelRatio;

  _ServiceBackdrop _backdrop;
  _ServiceBackdrop get backdrop => _backdrop;
  set backdrop(_ServiceBackdrop value) {
    if (identical(value, _backdrop)) return;
    if (attached) _unlisten();
    _backdrop = value;
    if (attached) _listen();
    markNeedsPaint();
  }

  BorderRadius _borderRadius;
  BorderRadius get borderRadius => _borderRadius;
  set borderRadius(BorderRadius value) {
    if (value == _borderRadius) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  double _fillOpacity;
  double get fillOpacity => _fillOpacity;
  set fillOpacity(double value) {
    if (value == _fillOpacity) return;
    _fillOpacity = value;
    markNeedsPaint();
  }

  WallpaperServiceShade? _shade;
  WallpaperServiceShade? get shade => _shade;
  set shade(WallpaperServiceShade? value) {
    if (value == _shade) return;
    _shade = value;
    markNeedsPaint();
  }

  /// Physical pixels per logical pixel: the grid a square fill snaps to.
  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// Placement the last paint used; a different one on a later frame means
  /// the fill moved without repainting.
  _Placement? _painted;

  void _listen() {
    _backdrop
      ..addListener(markNeedsPaint)
      .._track(this);
  }

  void _unlisten() {
    _backdrop
      ..removeListener(markNeedsPaint)
      .._untrack(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
  }

  @override
  void detach() {
    _unlisten();
    super.detach();
  }

  /// This box's placement in the surface, or `null` when the surface is not
  /// laid out or is not an ancestor.
  _Placement? _placement() {
    final surface = _backdrop._surface;
    if (surface == null || !surface.attached || !surface.hasSize) return null;
    for (var node = parent; node != null; node = node.parent) {
      if (identical(node, surface))
        return (toSurface: getTransformTo(surface), surface: surface.size);
    }
    return null;
  }

  void _repaintIfMoved() {
    if (!attached || !hasSize) return;
    if (_placement() != _painted) markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final placement = _painted = _placement();
    // The surface's shade doubles as its "lends a gradient" flag: an own
    // shade never paints a gradient the surface has stopped lending.
    if (_backdrop.shade case final surfaceShade? when _fillOpacity > 0) {
      _paintFill(context.canvas, offset, placement, _shade ?? surfaceShade);
    }
    super.paint(context, offset);
  }

  void _paintFill(
    Canvas canvas,
    Offset offset,
    _Placement? placement,
    WallpaperServiceShade shade,
  ) {
    final rrect = _borderRadius.toRRect(offset & size);
    // A square fill covers whole physical pixels: two fills meeting off the
    // grid would each cover the shared row partly — anti-aliased, or at a
    // layer's edge — and the backdrop would show through as a hairline.
    // Neighbours round their shared edge alike, so they tile exactly.
    final square = rrect.isRect
        ? _snapToPixels(Offset.zero & size).shift(offset)
        : null;
    void draw(Paint paint) => switch (square) {
      final rect? => canvas.drawRect(rect, paint..isAntiAlias = false),
      null => canvas.drawRRect(rrect, paint),
    };
    // The fill opacity scales the matrix's alpha rather than riding the
    // layer's paint: Impeller ignores a layer paint's alpha beside an image
    // filter.
    final filter = ColorFilter.matrix(shade.matrixAt(_fillOpacity));
    final frame = _backdrop.frame;
    final toCanvas = placement == null
        ? null
        : _gradientToCanvas(offset, placement);
    if (frame == null || toCanvas == null) {
      final fill = _backdrop.fill;
      if (fill == null) return;
      draw(
        Paint()
          ..color = shade
              .apply(fill.averageColor)
              .withValues(alpha: _fillOpacity),
      );
      return;
    }
    Paint layer(ui.Image image, double opacity) => Paint()
      ..shader = ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        toCanvas,
        filterQuality: FilterQuality.low,
      )
      ..color = Color.fromRGBO(0, 0, 0, opacity);
    // The filter goes on a layer: Impeller blends a colour filter on an image
    // shader's paint with transparency near the image's edges, clamp or not.
    // It is the layer's image filter: Impeller drops a layer's colour filter
    // around a single image-shader draw after the first such layer per picture.
    canvas.saveLayer(square ?? rrect.outerRect, Paint()..imageFilter = filter);
    draw(layer(frame.base, 1));
    if (frame.overlay case final overlay?)
      draw(layer(overlay, frame.overlayOpacity));
    canvas.restore();
  }

  /// [rect], in this box's coordinates, with each edge moved to the nearest
  /// physical pixel boundary of the screen.
  ///
  /// Unchanged under a transform that rotates, skews, or projects: its
  /// edges don't run along the pixel grid, so there is nothing to snap to.
  Rect _snapToPixels(Rect rect) {
    final m = getTransformTo(null).storage;
    final (scaleX, scaleY, dx, dy) = (m[0], m[5], m[12], m[13]);
    final axisAligned =
        m[1] == 0 && m[4] == 0 && m[3] == 0 && m[7] == 0 && m[15] == 1;
    if (!axisAligned || scaleX == 0 || scaleY == 0) return rect;
    final ratio = _devicePixelRatio;
    double snap(double value, double scale, double translate) =>
        (((value * scale + translate) * ratio).roundToDouble() / ratio -
            translate) /
        scale;
    return Rect.fromLTRB(
      snap(rect.left, scaleX, dx),
      snap(rect.top, scaleY, dy),
      snap(rect.right, scaleX, dx),
      snap(rect.bottom, scaleY, dy),
    );
  }

  /// Maps gradient raster pixels onto this box's canvas: cover-fit and
  /// centred in the surface, as the wallpaper view draws it, then into this
  /// box's coordinates at [offset].
  static Float64List? _gradientToCanvas(Offset offset, _Placement placement) {
    final fromSurface = Matrix4.tryInvert(placement.toSurface);
    if (fromSurface == null) return null;
    const width = FreeformGradient.width;
    const height = FreeformGradient.height;
    final Size(width: surfaceWidth, height: surfaceHeight) = placement.surface;
    final scale = math.max(surfaceWidth / width, surfaceHeight / height);
    final cover = Matrix4.identity()
      ..translateByDouble(
        (surfaceWidth - width * scale) / 2,
        (surfaceHeight - height * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
    return (Matrix4.translationValues(offset.dx, offset.dy, 0)
          ..multiply(fromSurface)
          ..multiply(cover))
        .storage;
  }
}

/// [decoration] painted as one layer at [opacity]: what lies behind shows
/// through it evenly, and its own overlapping parts — a border over its
/// colour, a shadow under it — never show through each other.
///
/// Shape, padding, and hit testing are [decoration]'s own, so swapping it in
/// for [decoration] changes only how opaque the box paints.
final class _FadedDecoration extends Decoration {
  const _FadedDecoration(this.decoration, {required this.opacity});

  final Decoration decoration;
  final double opacity;

  @override
  EdgeInsetsGeometry get padding => decoration.padding;

  @override
  bool get isComplex => decoration.isComplex;

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) =>
      decoration.hitTest(size, position, textDirection: textDirection);

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) =>
      decoration.getClipPath(rect, textDirection);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _FadedBoxPainter(switch (onChanged) {
        final onChanged? => decoration.createBoxPainter(onChanged),
        null => decoration.createBoxPainter(),
      }, opacity: opacity);

  @override
  bool operator ==(Object other) =>
      other is _FadedDecoration &&
      other.decoration == decoration &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(decoration, opacity);
}

class _FadedBoxPainter extends BoxPainter {
  _FadedBoxPainter(this._painter, {required double opacity})
    : _opacity = opacity;

  final BoxPainter _painter;
  final double _opacity;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    // Unbounded: a shadow may paint past the box.
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, _opacity));
    _painter.paint(canvas, offset, configuration);
    canvas.restore();
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}

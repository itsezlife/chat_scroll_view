import 'dart:ui' as ui;

import 'package:chrome_foundation/src/menu/pointer_menu_metrics.dart';
import 'package:chrome_foundation/src/motion/appear_motion.dart';
import 'package:chrome_foundation/src/motion/chrome_motion_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Plays an [AppearMotion] on [child]: the one way a menu, a popup or a
/// preview comes up and goes.
///
/// It shows when it first builds. Turning [visible] off plays the hide and
/// then calls [onHidden], once; the owner removes the surface from there.
/// Turning it on again during the hide shows the surface again from the
/// start. The durations come from the nearest `ChromeMotionScope`, so an
/// instant speed shows and hides at once.
///
/// The motion is relative to [origin]: the corner a pointer menu grows from,
/// the edge a popup unfolds from (top for a menu that hangs below what it
/// belongs to), the point a context menu scales about.
///
/// A grow draws [child] through a frame that is smaller than it; anything
/// [child] paints outside its box (a shadow of its own) is cut while the frame
/// grows. A surface with a shadow gives it as [shadows] instead, and
/// `ChromeAppear` paints it under the frame. [revealColor], the surface's own
/// background, is the colour of the strip that uncovers the content during a
/// grow; without it the content shows through the frame at once.
class ChromeAppear extends StatefulWidget {
  /// Plays [motion] (the platform's when null) on [child].
  const ChromeAppear({
    required this.child,
    this.visible = true,
    this.onHidden,
    this.motion,
    this.origin = AlignmentDirectional.topStart,
    this.rows = 0,
    this.borderRadius = BorderRadius.zero,
    this.revealColor,
    this.shadows = const <BoxShadow>[],
    super.key,
  });

  /// The surface.
  final Widget child;

  /// Whether the surface is up; off plays the hide.
  final bool visible;

  /// Called once the hide is over.
  final VoidCallback? onHidden;

  /// The motion, or null for `AppearMotion.forPlatform` of the running
  /// platform.
  final AppearMotion? motion;

  /// Where the surface is anchored.
  final AlignmentGeometry origin;

  /// How many rows the surface has, for a motion whose length depends on
  /// it.
  final int rows;

  /// The surface's corners, which the frame of a grow takes.
  final BorderRadiusGeometry borderRadius;

  /// The surface's background, for the strip of a grow.
  final Color? revealColor;

  /// The surface's shadows, painted under the frame.
  final List<BoxShadow> shadows;

  @override
  State<ChromeAppear> createState() => _ChromeAppearState();
}

class _ChromeAppearState extends State<ChromeAppear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this);
  var _started = false;
  var _hiding = false;

  AppearMotion get _motion =>
      widget.motion ?? AppearMotion.forPlatform(defaultTargetPlatform);

  ChromeMotionData get _speed =>
      ChromeMotionScope.maybeOf(context) ?? ChromeMotionData.standard;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.visible) {
      _show();
    } else {
      _hide();
    }
  }

  @override
  void didUpdateWidget(ChromeAppear oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      _show();
    } else {
      _hide();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _show() {
    _hiding = false;
    _clock.duration = _motion.showDuration(_speed, rows: widget.rows);
    _clock.forward(from: 0).ignore();
  }

  void _hide() {
    _hiding = true;
    _clock.duration = _motion.hideDuration(_speed);
    _clock.forward(from: 0).orCancel.then((_) {
      if (mounted && _hiding) widget.onHidden?.call();
    }, onError: (Object _) {}).ignore();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _clock,
    builder: (context, child) => AppearFrameView(
      frame: _hiding
          ? _motion.hideAt(_clock.value)
          : _motion.showAt(_clock.value),
      origin: widget.origin,
      borderRadius: widget.borderRadius,
      revealColor: widget.revealColor,
      shadows: widget.shadows,
      child: child!,
    ),
    child: widget.child,
  );
}

/// Draws [child] as one [AppearFrame] of an appear motion.
///
/// What `ChromeAppear` builds on each tick; a surface whose clock is driven
/// elsewhere (a presentation that reports when its motion settles) evaluates
/// the motion itself and draws the frame with this. The frame cuts what
/// [child] paints, never what it takes: presses land on the whole box while
/// it grows. [origin], [borderRadius], [revealColor] and [shadows] are as in
/// `ChromeAppear`.
class AppearFrameView extends StatelessWidget {
  /// Draws [child] at [frame].
  const AppearFrameView({
    required this.frame,
    required this.child,
    this.origin = AlignmentDirectional.topStart,
    this.borderRadius = BorderRadius.zero,
    this.revealColor,
    this.shadows = const <BoxShadow>[],
    super.key,
  });

  /// The moment to draw.
  final AppearFrame frame;

  /// Where the surface is anchored.
  final AlignmentGeometry origin;

  /// The surface's corners.
  final BorderRadiusGeometry borderRadius;

  /// The surface's background, for the strip of a grow.
  final Color? revealColor;

  /// The surface's shadows, painted under the frame.
  final List<BoxShadow> shadows;

  /// The surface.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.maybeOf(context);
    final origin = this.origin.resolve(direction);
    final radius = borderRadius.resolve(direction);
    return Opacity(
      opacity: frame.opacity.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, origin.y * frame.drift),
        child: Transform.scale(
          scale: frame.scale,
          alignment: origin,
          child: CustomPaint(
            painter: _ShadowPainter(
              frame: frame,
              origin: origin,
              radius: radius,
              shadows: shadows,
            ),
            child: _FrameClip(
              frame: frame,
              origin: origin,
              radius: radius,
              child: CustomPaint(
                foregroundPainter: _StripPainter(
                  frame: frame,
                  origin: origin,
                  color: revealColor,
                ),
                child: _AppearContentScope(
                  frame: frame,
                  origin: origin,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The content of a surface an appear motion plays on: the part that fades
/// and scales over the surface's own background
/// (`AppearFrame.contentOpacity`, `AppearFrame.contentScale`), about the
/// motion's origin.
///
/// A surface whose background and content move apart (a menu whose panel
/// opens while its rows come in) wraps its content in this, inside the
/// background. Outside an appear motion, or under one that does not move the
/// content, it draws [child] as is.
class AppearContent extends StatelessWidget {
  /// The content [child].
  const AppearContent({required this.child, super.key});

  /// The content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_AppearContentScope>();
    final frame = scope?.frame ?? AppearFrame.rest;
    // One shape whatever the frame, so the content keeps its state.
    return Opacity(
      opacity: frame.contentOpacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: frame.contentScale,
        alignment: scope?.origin ?? Alignment.center,
        child: child,
      ),
    );
  }
}

class _AppearContentScope extends InheritedWidget {
  const _AppearContentScope({
    required this.frame,
    required this.origin,
    required super.child,
  });

  final AppearFrame frame;
  final Alignment origin;

  @override
  bool updateShouldNotify(_AppearContentScope oldWidget) =>
      oldWidget.frame.contentOpacity != frame.contentOpacity ||
      oldWidget.frame.contentScale != frame.contentScale ||
      oldWidget.origin != origin;
}

class _FrameClip extends SingleChildRenderObjectWidget {
  const _FrameClip({
    required this.frame,
    required this.origin,
    required this.radius,
    super.child,
  });

  final AppearFrame frame;
  final Alignment origin;
  final BorderRadius radius;

  @override
  _RenderFrameClip createRenderObject(BuildContext context) =>
      _RenderFrameClip(frame, origin, radius);

  @override
  void updateRenderObject(BuildContext context, _RenderFrameClip renderObject) {
    renderObject
      ..frame = frame
      ..origin = origin
      ..radius = radius;
  }
}

class _RenderFrameClip extends RenderProxyBox {
  _RenderFrameClip(this._frame, this._origin, this._radius);

  AppearFrame _frame;
  set frame(AppearFrame value) {
    if (value == _frame) return;
    _frame = value;
    markNeedsPaint();
  }

  Alignment _origin;
  set origin(Alignment value) {
    if (value == _origin) return;
    _origin = value;
    markNeedsPaint();
  }

  BorderRadius _radius;
  set radius(BorderRadius value) {
    if (value == _radius) return;
    _radius = value;
    markNeedsPaint();
  }

  final _clip = LayerHandle<ClipRRectLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (!_frame.clips) {
      _clip.layer = null;
      super.paint(context, offset);
      return;
    }
    _clip.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      _radius.toRRect(_frame.frameIn(size, _origin)),
      super.paint,
      oldLayer: _clip.layer,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}

class _ShadowPainter extends CustomPainter {
  const _ShadowPainter({
    required this.frame,
    required this.origin,
    required this.radius,
    required this.shadows,
  });

  final AppearFrame frame;
  final Alignment origin;
  final BorderRadius radius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) return;
    final box = frame.frameIn(size, origin);
    for (final shadow in shadows) {
      canvas.drawRRect(
        radius.toRRect(box.shift(shadow.offset).inflate(shadow.spreadRadius)),
        shadow.toPaint(),
      );
    }
  }

  @override
  bool shouldRepaint(_ShadowPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.origin != origin ||
      oldDelegate.radius != radius ||
      !listEquals(oldDelegate.shadows, shadows);
}

// The strip that uncovers the content from the top: the surface's colour over
// everything below it, fading to nothing along its height.
class _StripPainter extends CustomPainter {
  const _StripPainter({
    required this.frame,
    required this.origin,
    required this.color,
  });

  final AppearFrame frame;
  final Alignment origin;
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final color = this.color;
    if (color == null || frame.revealed >= 1) return;
    final box = frame.frameIn(size, origin);
    final top = box.top + box.height * frame.revealed;
    final strip = box.height * PointerMenuMetrics.fadeHeight;
    canvas.drawRect(
      Rect.fromLTRB(box.left, top, box.right, box.bottom),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, top + strip), [
          color.withValues(alpha: 0),
          color,
        ]),
    );
  }

  @override
  bool shouldRepaint(_StripPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.origin != origin ||
      oldDelegate.color != color;
}

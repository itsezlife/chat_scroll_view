import 'dart:async';
import 'dart:math' as math;

import 'package:chat_composer/src/draft_options/draft_options_presentation_motion.dart';
import 'package:chat_composer/src/draft_options/draft_options_session.dart';
import 'package:chat_composer/src/draft_options/draft_options_spring_surface.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The iOS skin of the draft options overlay: the [preview] in a rounded
/// content rect and the [actions] under it, springing out of the strip on
/// open and back into it on close, laid out and timed by [surface].
///
/// The open starts when the view is first built; the close starts when the
/// [scrim] starts its own, so the content and the backdrop leave together.
/// The strip is the [session]'s origin, a global rect: the overlay stands in
/// the root overlay, at the window's origin. With no origin the content
/// grows in place.
///
/// Each motion is reported through the session's `motion` event. Under
/// reduce motion (`ChromeMotionSpeed.instant`) every motion lands on its end
/// state at once.
class DraftOptionsSpringView extends StatefulWidget {
  /// The spring skin of [session] over [scrim].
  const DraftOptionsSpringView({
    required this.surface,
    required this.session,
    required this.scrim,
    required this.preview,
    this.actions,
    super.key,
  });

  /// The key of the content rect, the preview's frame.
  static const Key contentKey = ValueKey('draftOptionsSpringContent');

  /// The key of the actions list.
  static const Key actionsKey = ValueKey('draftOptionsSpringActions');

  /// The layout, motion and haptic.
  final DraftOptionsSpringSurface surface;

  /// The open: its origin, edits and motion reports.
  final DraftOptionsSession session;

  /// The scrim under the view, whose close starts the view's.
  final ChromeScrimController scrim;

  /// The live preview.
  final Widget preview;

  /// The link page's rows; null draws the content alone.
  final Widget? actions;

  @override
  State<DraftOptionsSpringView> createState() => _DraftOptionsSpringViewState();
}

class _DraftOptionsSpringViewState extends State<DraftOptionsSpringView>
    with TickerProviderStateMixin, DraftOptionsPresentationMotion {
  late final AnimationController _open = AnimationController(vsync: this);
  late final AnimationController _close = AnimationController(vsync: this);
  late final Listenable _clocks = Listenable.merge([_open, _close]);
  final _frame = _SpringFrameHolder();

  DraftOptionsSpringMotion get _motion => widget.surface.motion;

  @override
  DraftOptionsSession get motionSession => widget.session;

  @override
  ChromeScrimController get motionScrim => widget.scrim;

  @override
  void initState() {
    super.initState();
    widget.session.value.addListener(_onEdit);
  }

  @override
  void dispose() {
    widget.session.value.removeListener(_onEdit);
    _open.dispose();
    _close.dispose();
    super.dispose();
  }

  @override
  Duration playOpen(ChromeMotionSpeed speed) {
    final duration = _open.duration = speed.scale(_motion.springCut);
    unawaited(_open.forward());
    return duration;
  }

  @override
  Duration playClose(ChromeMotionSpeed speed) {
    final duration = _close.duration = speed.scale(_motion.close.duration);
    unawaited(_close.forward());
    return duration;
  }

  void _onEdit() => reportMotion(
    DraftOptionsMotionPhase.change,
    motionSpeed.scale(_motion.change.duration),
  );

  /// The pose of the content and the actions at the clocks' values: the
  /// open's spring and fades, then the close's ease and fade over it.
  ({_SpringPose content, _SpringPose actions}) _poses() {
    final motion = _motion;
    final start = motion.startScale;
    final opened = motion.springCut * _open.value;
    final grown = motion.grownAt(opened);
    double fade(MotionSpec spec, Duration elapsed) =>
        spec.duration <= Duration.zero
        ? 1
        : spec.curve.transform(
            (elapsed.inMicroseconds / spec.duration.inMicroseconds).clamp(
              0.0,
              1.0,
            ),
          );
    var scale = start + (1 - start) * grown;
    var toward = 1 - grown;
    var contentOpacity = fade(motion.contentShowFade, opened);
    var actionsOpacity = fade(motion.actionsShowFade, opened);
    if (_close.value > 0) {
      final closed = motion.close.duration * _close.value;
      final eased = motion.close.curve.transform(_close.value);
      scale = math.min(scale, 1 - (1 - start) * eased);
      toward = math.max(toward, eased);
      final out = 1 - fade(motion.contentHideFade, closed);
      contentOpacity = math.min(contentOpacity, out);
      actionsOpacity = math.min(actionsOpacity, out);
    }
    return (
      content: _SpringPose(scale, toward, contentOpacity),
      actions: _SpringPose(scale, toward, actionsOpacity),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = widget.surface;
    final palette = ChromeThemeScope.of(context).palette;
    final origin = widget.session.origin?.center.dy;
    final change = surface.motion.change.withSpeed(motionSpeed);
    final content = ClipRRect(
      key: DraftOptionsSpringView.contentKey,
      borderRadius: BorderRadius.circular(surface.cornerRadius),
      child: ColoredBox(
        color: palette.surface,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(bottom: surface.previewExtra),
            child: AnimatedSize(
              duration: change.duration,
              curve: change.curve,
              alignment: Alignment.topCenter,
              child: widget.preview,
            ),
          ),
        ),
      ),
    );
    final actions = switch (widget.actions) {
      final actions? => ConstrainedBox(
        key: DraftOptionsSpringView.actionsKey,
        constraints: BoxConstraints(minWidth: surface.actionsMinWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(surface.actionsCornerRadius),
          child: ColoredBox(color: palette.surfaceRaised, child: actions),
        ),
      ),
      null => null,
    };
    return AnimatedBuilder(
      animation: _clocks,
      builder: (context, _) {
        final poses = _poses();
        return CustomMultiChildLayout(
          delegate: _SpringLayout(
            surface: surface,
            padding: MediaQuery.viewPaddingOf(context),
            strip: widget.session.origin,
            frame: _frame,
          ),
          children: [
            LayoutId(
              id: _SpringSlot.content,
              child: _SpringPaint(
                pose: poses.content,
                originY: origin,
                frame: _frame,
                anchor: _SpringAnchor.centre,
                child: Opacity(opacity: poses.content.opacity, child: content),
              ),
            ),
            if (actions != null)
              LayoutId(
                id: _SpringSlot.actions,
                child: _SpringPaint(
                  pose: poses.actions,
                  originY: origin,
                  frame: _frame,
                  anchor: _SpringAnchor.topRight,
                  child: Opacity(
                    opacity: poses.actions.opacity,
                    child: actions,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

enum _SpringSlot { content, actions }

/// What a child of the spring view scales about.
enum _SpringAnchor { centre, topRight }

/// One child's pose: its [scale], how far it stands [toward] the strip's
/// centre (0 in place, 1 there) and its [opacity] (drawn by an `Opacity`
/// over the child).
final class _SpringPose {
  const _SpringPose(this.scale, this.toward, this.opacity);

  final double scale;
  final double toward;
  final double opacity;

  bool get isRest => scale == 1 && toward == 0;
}

/// The last layout's frame, read when the children paint: their move
/// toward the strip is measured from the content's centre.
final class _SpringFrameHolder {
  DraftOptionsSpringFrame? frame;
}

class _SpringLayout extends MultiChildLayoutDelegate {
  _SpringLayout({
    required this.surface,
    required this.padding,
    required this.strip,
    required this.frame,
  });

  final DraftOptionsSpringSurface surface;
  final EdgeInsets padding;
  final Rect? strip;
  final _SpringFrameHolder frame;

  @override
  void performLayout(Size size) {
    var actions = Size.zero;
    if (hasChild(_SpringSlot.actions)) {
      actions = layoutChild(
        _SpringSlot.actions,
        BoxConstraints.loose(
          Size(
            math.max(0, size.width - 2 * surface.actionsEdgeInset),
            size.height,
          ),
        ),
      );
    }
    final bounds = surface.contentHeightBounds(
      size,
      padding,
      actionsHeight: actions.height,
    );
    final width = surface.contentWidth(size);
    final content = layoutChild(
      _SpringSlot.content,
      BoxConstraints(
        minWidth: width,
        maxWidth: width,
        minHeight: bounds.min,
        maxHeight: bounds.max,
      ),
    );
    final placed = surface.place(
      size,
      padding,
      content: content,
      actions: actions,
      strip: strip,
    );
    frame.frame = placed;
    positionChild(_SpringSlot.content, placed.content.topLeft);
    if (hasChild(_SpringSlot.actions)) {
      positionChild(_SpringSlot.actions, placed.actions);
    }
  }

  @override
  bool shouldRelayout(_SpringLayout old) =>
      old.surface != surface || old.padding != padding || old.strip != strip;
}

/// Paints its child at a [pose]'s scale, about its [anchor], moved toward
/// the strip's centre line [originY] (global) by the content's centre in
/// the last [frame].
class _SpringPaint extends SingleChildRenderObjectWidget {
  const _SpringPaint({
    required this.pose,
    required this.originY,
    required this.frame,
    required this.anchor,
    super.child,
  });

  final _SpringPose pose;
  final double? originY;
  final _SpringFrameHolder frame;
  final _SpringAnchor anchor;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSpringPaint(pose, originY, frame, anchor);

  @override
  void updateRenderObject(BuildContext context, _RenderSpringPaint render) =>
      render
        ..pose = pose
        ..originY = originY;
}

class _RenderSpringPaint extends RenderProxyBox {
  _RenderSpringPaint(this._pose, this._originY, this._frame, this._anchor);

  final _SpringFrameHolder _frame;
  final _SpringAnchor _anchor;

  _SpringPose _pose;
  set pose(_SpringPose pose) {
    _pose = pose;
    markNeedsPaint();
  }

  double? _originY;
  set originY(double? value) {
    if (value == _originY) return;
    _originY = value;
    markNeedsPaint();
  }

  Matrix4 _transform() {
    final anchor = switch (_anchor) {
      _SpringAnchor.centre => size.center(Offset.zero),
      _SpringAnchor.topRight => size.topRight(Offset.zero),
    };
    var dy = 0.0;
    if ((_originY, _frame.frame) case (final origin?, final frame?)) {
      // The layout's top in the window: the strip's rect is global.
      final layout = parent;
      final layoutTop = layout is RenderBox
          ? layout.localToGlobal(Offset.zero).dy
          : 0.0;
      dy = (origin - layoutTop - frame.content.center.dy) * _pose.toward;
    }
    return Matrix4.identity()
      ..translateByDouble(anchor.dx, anchor.dy + dy, 0, 1)
      ..scaleByDouble(_pose.scale, _pose.scale, 1, 1)
      ..translateByDouble(-anchor.dx, -anchor.dy, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_pose.isRest) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform(),
      (context, offset) => context.paintChild(child, offset),
      oldLayer: layer as TransformLayer?,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_pose.isRest) return super.hitTest(result, position: position);
    return result.addWithPaintTransform(
      transform: _transform(),
      position: position,
      hitTest: (result, position) => super.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (!_pose.isRest) transform.multiply(_transform());
  }
}

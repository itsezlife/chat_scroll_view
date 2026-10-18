import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Opens, closes and scrubs the More page of a [SelectionMenuSwipeBack].
///
/// One controller serves one host for as long as the host is mounted; the
/// owner disposes it. Its calls do nothing before a host attaches.
class SelectionMenuPageController extends ChangeNotifier {
  AnimationController? _animation;
  Duration _duration = Duration.zero;
  Curve _curve = Curves.linear;

  /// Progress in `[0, 1]`: 0 is the main row, 1 the More page.
  double get progress => _animation?.value ?? 0;

  /// Whether the More page is the one showing, past half way.
  bool get isForegroundOpen => progress > 0.5;

  /// Whether a turn is running.
  bool get isAnimating => _animation?.isAnimating ?? false;

  void _attach(AnimationController animation) {
    _animation?.removeListener(notifyListeners);
    _animation = animation..addListener(notifyListeners);
  }

  void _detach() {
    _animation?.removeListener(notifyListeners);
    _animation = null;
  }

  // The duration is for a full turn and is the role's, speed applied; a turn
  // that starts part way takes proportionally less, never under half. It is
  // handed to each `animateTo` rather than set on the controller, which would
  // scale it by the distance a second time.
  void _configure(Duration duration, Curve curve) {
    _duration = duration;
    _curve = curve;
  }

  Duration _scaled(double factor) => _duration * factor;

  /// Opens the More page. Ignored while a turn is running.
  void openForeground() {
    final animation = _animation;
    if (animation == null || animation.isAnimating) return;
    final delta = 1.0 - animation.value;
    unawaited(
      animation.animateTo(
        1,
        duration: _scaled(math.max(0.5, delta)),
        curve: _curve,
      ),
    );
  }

  /// Closes the More page, at once when not [animated]. Ignored while a turn
  /// is running.
  void closeForeground({bool animated = true}) {
    final animation = _animation;
    if (animation == null) return;
    if (!animated) {
      animation.value = 0;
      return;
    }
    if (animation.isAnimating) return;
    unawaited(
      animation.animateTo(
        0,
        duration: _scaled(math.max(0.5, animation.value)),
        curve: _curve,
      ),
    );
  }

  /// Follows a drag: sets the progress, clamped.
  void scrubTo(double value) {
    final animation = _animation;
    if (animation == null || animation.isAnimating) return;
    animation.value = value.clamp(0.0, 1.0);
  }

  /// Settles a drag that ended at [velocityX] (logical pixels per second,
  /// positive to the right) over a page [width] wide: a fling of
  /// [SelectionMenuMetrics.flingVelocity] or more closes the page, anything
  /// slower snaps to the nearer end.
  void snapFromFling({required double velocityX, required double width}) {
    final animation = _animation;
    if (animation == null) return;
    final flingClose = velocityX >= SelectionMenuMetrics.flingVelocity;
    final target = flingClose || animation.value < 0.5 ? 0.0 : 1.0;
    final fling = flingClose
        ? (velocityX / math.max(width, 1)).clamp(0.0, 1.0)
        : 0.0;
    final delta = (target - animation.value).abs();
    unawaited(
      animation.animateTo(
        target,
        duration: _scaled(math.max(0.5, delta - math.min(0.2, fling))),
        curve: _curve,
      ),
    );
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }
}

/// Two pages in one card, turned by one progress: the main row [root] and the
/// More page [foreground].
///
/// One value drives everything, as a slide and not a cross-fade. The card's
/// size is the sizes of the two pages blended by the progress, and a rounded
/// clip shows it. The root slides left by half its width and shrinks to 0.95
/// about its top-left corner while a [dim] scrim darkens it; the foreground
/// slides in from the right (not mirrored in right-to-left). A drag to the
/// right over the open More page follows the finger and closes it.
///
/// Only the page the progress is closer to answers hits, focus and semantics.
class SelectionMenuSwipeBack extends StatefulWidget {
  /// Hosts [root] and [foreground] under [controller].
  const SelectionMenuSwipeBack({
    required this.controller,
    required this.root,
    required this.foreground,
    required this.pageColor,
    required this.dim,
    required this.duration,
    required this.curve,
    required this.borderRadius,
    this.initialProgress = 0,
    super.key,
  });

  /// Turns the pages.
  final SelectionMenuPageController controller;

  /// The main row.
  final Widget root;

  /// The More page.
  final Widget foreground;

  /// The opaque fill under each page, so the root does not show through.
  final Color pageColor;

  /// The scrim over the root; its alpha is the most it reaches, with the More
  /// page fully open.
  final Color dim;

  /// The time of a full turn, with the speed applied.
  final Duration duration;

  /// The curve of a turn.
  final Curve curve;

  /// The radius of the clip.
  final double borderRadius;

  /// Where the pages start, in `[0, 1]`.
  final double initialProgress;

  @override
  State<SelectionMenuSwipeBack> createState() => _SelectionMenuSwipeBackState();
}

class _SelectionMenuSwipeBackState extends State<SelectionMenuSwipeBack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late var _foregroundActive = widget.initialProgress > 0.5;

  double? _dragStartProgress;
  double? _dragStartX;
  double? _dragWidth;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      value: widget.initialProgress.clamp(0.0, 1.0),
    )..addListener(_onProgress);
    widget.controller
      .._attach(_animation)
      .._configure(widget.duration, widget.curve);
  }

  @override
  void didUpdateWidget(SelectionMenuSwipeBack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._detach();
      widget.controller._attach(_animation);
    }
    widget.controller._configure(widget.duration, widget.curve);
  }

  @override
  void dispose() {
    widget.controller._detach();
    _animation
      ..removeListener(_onProgress)
      ..dispose();
    super.dispose();
  }

  // Focus follows the page that shows: the other is out of traversal, so Tab
  // does not walk into a page nobody can see.
  void _onProgress() {
    final active = _animation.value > 0.5;
    if (active != _foregroundActive) setState(() => _foregroundActive = active);
  }

  void _onDragStart(DragStartDetails details) {
    if (_animation.value < 0.99 || _animation.isAnimating) return;
    // The width is read before scrubbing: a scrub dirties layout, and the
    // size is not readable then.
    final width = context.size?.width;
    if (width == null || width <= 0) return;
    _dragWidth = width;
    _dragStartProgress = _animation.value;
    _dragStartX = details.globalPosition.dx;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final startX = _dragStartX;
    final startProgress = _dragStartProgress;
    final width = _dragWidth;
    if (startX == null || startProgress == null || width == null) return;
    final dx = details.globalPosition.dx - startX;
    widget.controller.scrubTo(startProgress - dx / width);
  }

  void _onDragEnd(DragEndDetails details) {
    final width = _dragWidth;
    final dragged = _dragStartX != null;
    _dragStartX = null;
    _dragStartProgress = null;
    _dragWidth = null;
    if (!dragged || width == null) return;
    widget.controller.snapFromFling(
      velocityX: details.velocity.pixelsPerSecond.dx,
      width: width,
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onHorizontalDragStart: _onDragStart,
    onHorizontalDragUpdate: _onDragUpdate,
    onHorizontalDragEnd: _onDragEnd,
    behavior: HitTestBehavior.deferToChild,
    child: _SwipeBackRender(
      progress: _animation,
      borderRadius: widget.borderRadius,
      pageColor: widget.pageColor,
      dim: widget.dim,
      children: [
        ExcludeFocus(excluding: _foregroundActive, child: widget.root),
        ExcludeFocus(excluding: !_foregroundActive, child: widget.foreground),
      ],
    ),
  );
}

class _SwipeBackRender extends MultiChildRenderObjectWidget {
  const _SwipeBackRender({
    required this.progress,
    required this.borderRadius,
    required this.pageColor,
    required this.dim,
    required super.children,
  });

  final Animation<double> progress;
  final double borderRadius;
  final Color pageColor;
  final Color dim;

  @override
  _RenderSwipeBack createRenderObject(BuildContext context) => _RenderSwipeBack(
    progress: progress,
    borderRadius: borderRadius,
    pageColor: pageColor,
    dim: dim,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderSwipeBack renderObject) {
    renderObject
      ..progress = progress
      ..borderRadius = borderRadius
      ..pageColor = pageColor
      ..dim = dim;
  }
}

class _SwipeBackParentData extends ContainerBoxParentData<RenderBox> {}

// Measures both pages, sizes itself to their blend and paints the slide, the
// scale, the scrim and the clip.
class _RenderSwipeBack extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SwipeBackParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SwipeBackParentData> {
  _RenderSwipeBack({
    required Animation<double> progress,
    required double borderRadius,
    required Color pageColor,
    required Color dim,
  }) : _progress = progress,
       _borderRadius = borderRadius,
       _pageColor = pageColor,
       _dim = dim {
    _progress.addListener(_onProgress);
  }

  Animation<double> _progress;
  // ignore: avoid_setters_without_getters
  set progress(Animation<double> value) {
    if (identical(_progress, value)) return;
    _progress.removeListener(_onProgress);
    _progress = value;
    _progress.addListener(_onProgress);
    _onProgress();
  }

  double _borderRadius;
  // ignore: avoid_setters_without_getters
  set borderRadius(double value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  Color _pageColor;
  // ignore: avoid_setters_without_getters
  set pageColor(Color value) {
    if (_pageColor == value) return;
    _pageColor = value;
    markNeedsPaint();
  }

  Color _dim;
  // ignore: avoid_setters_without_getters
  set dim(Color value) {
    if (_dim == value) return;
    _dim = value;
    markNeedsPaint();
  }

  Size _rootSize = Size.zero;
  Size _foregroundSize = Size.zero;
  late var _foregroundActive = _t > 0.5;

  RenderBox? get _root => firstChild;
  RenderBox? get _foreground {
    final root = firstChild;
    return root == null ? null : childAfter(root);
  }

  double get _t => _progress.value.clamp(0.0, 1.0);

  void _onProgress() {
    markNeedsLayout();
    final active = _t > 0.5;
    if (active != _foregroundActive) {
      _foregroundActive = active;
      markNeedsSemanticsUpdate();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SwipeBackParentData) {
      child.parentData = _SwipeBackParentData();
    }
  }

  @override
  void dispose() {
    _progress.removeListener(_onProgress);
    super.dispose();
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final active = _foregroundActive ? _foreground : _root;
    if (active != null) visitor(active);
  }

  @override
  void performLayout() {
    final root = _root!;
    final foreground = _foreground!;
    final maxWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : constraints.minWidth;
    final childConstraints = BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : double.infinity,
    );
    root.layout(childConstraints, parentUsesSize: true);
    foreground.layout(childConstraints, parentUsesSize: true);
    _rootSize = root.size;
    _foregroundSize = foreground.size;
    final t = _t;
    size = constraints.constrain(
      Size(
        ui.lerpDouble(_rootSize.width, _foregroundSize.width, t)!,
        ui.lerpDouble(_rootSize.height, _foregroundSize.height, t)!,
      ),
    );
    (root.parentData! as _SwipeBackParentData).offset = Offset.zero;
    (foreground.parentData! as _SwipeBackParentData).offset = Offset.zero;
  }

  // Slides left by half the host and shrinks to 0.95 about the top-left
  // corner, as the page leaves.
  Matrix4 _rootTransform(Size host) {
    final t = _t;
    final scale = 0.95 + (1 - t) * 0.05;
    return Matrix4.identity()
      ..translateByDouble(-t * host.width * 0.5, 0, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  // Slides in from the right edge.
  Matrix4 _foregroundTransform(Size host) =>
      Matrix4.translationValues((1 - _t) * host.width, 0, 0);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (child == _root) {
      transform.multiply(_rootTransform(size));
    } else if (child == _foreground) {
      transform.multiply(_foregroundTransform(size));
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final foreground = _t > 0.5;
    final active = foreground ? _foreground : _root;
    if (active == null) return false;
    return result.addWithPaintTransform(
      transform: foreground ? _foregroundTransform(size) : _rootTransform(size),
      position: position,
      hitTest: (result, transformed) =>
          active.hitTest(result, position: transformed),
    );
  }

  // The fill covers at least the host, so a page narrower than the card still
  // hides the other.
  void _paintPage(PaintingContext context, Offset offset, RenderBox child) {
    final cover = Size(
      math.max(child.size.width, size.width),
      math.max(child.size.height, size.height),
    );
    context.canvas.drawRect(offset & cover, Paint()..color = _pageColor);
    context.paintChild(child, offset);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final root = _root;
    final foreground = _foreground;
    if (root == null || foreground == null) return;
    final t = _t;
    final host = size;
    final clip = offset & host;
    context.canvas
      ..save()
      ..clipRRect(
        RRect.fromRectAndRadius(clip, Radius.circular(_borderRadius)),
      );

    // The root is skipped once fully covered: its anti-aliased top-left edge
    // would bleed through.
    if (t < 1) {
      context.pushTransform(needsCompositing, offset, _rootTransform(host), (
        context,
        offset,
      ) {
        _paintPage(context, offset, root);
      });
    }
    if (t > 0) {
      context.canvas.drawRect(
        clip,
        Paint()..color = _dim.withValues(alpha: _dim.a * t),
      );
      context.pushTransform(
        needsCompositing,
        offset,
        _foregroundTransform(host),
        (context, offset) {
          _paintPage(context, offset, foreground);
        },
      );
    }
    context.canvas.restore();
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.min(_rootSize.width, _foregroundSize.width);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(_rootSize.width, _foregroundSize.width);

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.min(_rootSize.height, _foregroundSize.height);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(_rootSize.height, _foregroundSize.height);
}

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Clip-reveals a fixed-[extent] child as [progress] rises, top-aligned.
///
/// Layout height is `extent * progress`; the child always lays out at
/// [extent] and is clipped from the top, so the upper part of the strip
/// appears first. A bottom-aligned clip would show the wrong half and read as
/// the strip floating in.
class RevealBox extends SingleChildRenderObjectWidget {
  /// Reveals [child] by [progress] of [extent].
  const RevealBox({
    required this.progress,
    required this.extent,
    required Widget super.child,
    super.key,
  });

  /// Revealed fraction, 0 to 1.
  final double progress;

  /// Full height of the child.
  final double extent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderRevealBox(progress: progress, extent: extent);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderRevealBox renderObject,
  ) {
    renderObject
      ..progress = progress
      ..extent = extent;
  }
}

/// Render object of [RevealBox].
class RenderRevealBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  /// Creates the render object.
  RenderRevealBox({required double progress, required double extent})
    : _progress = progress,
      _extent = extent;

  double _progress;
  set progress(double value) {
    if (_progress == value) return;
    _progress = value;
    markNeedsLayout();
  }

  double _extent;
  set extent(double value) {
    if (_extent == value) return;
    _extent = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : (child?.getMaxIntrinsicWidth(double.infinity) ?? 0);
    child?.layout(
      BoxConstraints.tightFor(width: width, height: _extent),
      parentUsesSize: true,
    );
    size = constraints.constrain(
      Size(width, _extent * _progress.clamp(0.0, 1.0)),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null || size.isEmpty) return;
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (
      context,
      offset,
    ) {
      context.paintChild(c, offset);
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null || position.dy > size.height) return false;
    return c.hitTest(result, position: position);
  }
}

/// A box whose height is driven from outside while its child lays out at its
/// intrinsic height, painted bottom-aligned so growth expands above a fixed
/// baseline.
///
/// The child's natural size is reported through [onChildSize] after the frame,
/// so the owner can animate [height] toward it.
class DrivenHeightBox extends SingleChildRenderObjectWidget {
  /// A box of [height] around [child].
  const DrivenHeightBox({
    required this.height,
    required this.onChildSize,
    required Widget super.child,
    super.key,
  });

  /// The height to take.
  final double height;

  /// Called after layout whenever the child's size changed.
  final ValueChanged<Size> onChildSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderDrivenHeightBox(height: height, onChildSize: onChildSize);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderDrivenHeightBox renderObject,
  ) {
    renderObject
      ..height = height
      ..onChildSize = onChildSize;
  }
}

/// Render object of [DrivenHeightBox].
class RenderDrivenHeightBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  /// Creates the render object.
  RenderDrivenHeightBox({required double height, required this.onChildSize})
    : _height = height;

  /// Called after layout whenever the child's size changed.
  ValueChanged<Size> onChildSize;
  Size? _reported;

  double _height;
  set height(double value) {
    if (_height == value) return;
    _height = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : (child?.getMaxIntrinsicWidth(double.infinity) ?? 0);
    final c = child;
    if (c != null) {
      c.layout(
        BoxConstraints(
          minWidth: width,
          maxWidth: width,
          maxHeight: double.infinity,
        ),
        parentUsesSize: true,
      );
      final childSize = c.size;
      if (childSize != _reported) {
        _reported = childSize;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (attached) onChildSize(childSize);
        });
      }
    }
    size = constraints.constrain(Size(width, _height));
  }

  double get _dy => size.height - (child?.size.height ?? 0);

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    context.paintChild(c, offset + Offset(0, _dy));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    return result.addWithPaintOffset(
      offset: Offset(0, _dy),
      position: position,
      hitTest: (result, transformed) =>
          c.hitTest(result, position: transformed),
    );
  }
}

/// Reports the height its child takes, after every layout in which it
/// changed.
///
/// Used to publish the composer extent and the field height as data. The
/// report is deferred to after the frame, so a listener may rebuild without a
/// layout-time `setState`.
class HeightReporter extends SingleChildRenderObjectWidget {
  /// Reports the height of [child] through [onHeight].
  const HeightReporter({
    required this.onHeight,
    required Widget super.child,
    super.key,
  });

  /// Called with the laid-out height.
  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderHeightReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

/// Render object of [HeightReporter].
class RenderHeightReporter extends RenderProxyBox {
  /// Creates the render object.
  RenderHeightReporter(this.onHeight);

  /// Called with the laid-out height.
  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(height);
    });
  }
}

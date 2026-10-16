import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Reports the height its child laid out to, after each frame in which it
/// changed.
///
/// A page that pins a strip at the bottom tells the shell how tall it really
/// is (zero while it draws nothing) rather than repeating the strip's own
/// constant, so a strip that shrinks to nothing for want of tabs, or waits for
/// its mount, takes the floating chrome's clearance with it. The call is made
/// after the frame: a report is a change in another widget's inputs, which
/// layout must not make.
class BottomExtentReporter extends SingleChildRenderObjectWidget {
  /// Reports the height of [child] to [onExtent].
  const BottomExtentReporter({
    required this.onExtent,
    required super.child,
    super.key,
  });

  /// Called with the child's height, after the frame that changed it.
  final ValueChanged<double> onExtent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBottomExtentReporter(onExtent);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderBottomExtentReporter).onExtent = onExtent;
}

final class _RenderBottomExtentReporter extends RenderProxyBox {
  _RenderBottomExtentReporter(this.onExtent);

  ValueChanged<double> onExtent;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final extent = size.height;
    if (extent == _reported) return;
    _reported = extent;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onExtent(extent);
    });
  }
}

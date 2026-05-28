import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Reports its [child]'s laid-out size through [onChange] whenever it changes.
///
/// The callback is deferred to after the current frame, so it is safe to use
/// it to drive a `ValueNotifier` / `setState` that dirties other render
/// objects (e.g. feeding a composer's measured height into a scroll view's
/// bottom inset).
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({
    required this.onChange,
    required Widget super.child,
    super.key,
  });

  /// Called with the child's size after every layout in which it changed.
  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMeasureSize).onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final next = size;
    if (next == _reported) return;
    _reported = next;
    // Reporting synchronously would dirty other render objects mid-layout;
    // defer to the end of the frame instead.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onChange(next);
    });
  }
}

import 'package:flutter/animation.dart';

/// Continuous smooth scroll for near-path section jumps.
///
/// Owns one [AnimationController] driven by a [TickerProvider]. Applies
/// intermediate offsets through [applyOffset] (typically silent viewport
/// [PanelCatalogController.correctOffset] writes) and repaints each tick.
/// Does **not** own path selection, landing math, or stitch.
final class CatalogNearScroll {
  /// Creates idle near-scroll state bound to [vsync].
  CatalogNearScroll({
    required TickerProvider vsync,
    required VoidCallback onTick,
  }) : _vsync = vsync,
       _onTick = onTick;

  final TickerProvider _vsync;
  final VoidCallback _onTick;

  AnimationController? _controller;
  void Function(double offset)? _applyOffset;

  /// Whether a near-path section jump animation is driving offset.
  bool get isActive => _controller?.isAnimating ?? false;

  /// Runs a near-path scroll from [from] to [to].
  ///
  /// [applyOffset] receives clamp-ready absolute offsets each tick. Cancels any
  /// in-flight animation first. Completes when the controller settles or
  /// [cancel] runs (completes the returned future without error).
  Future<void> animate({
    required double from,
    required double to,
    required void Function(double offset) applyOffset,
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.decelerate,
  }) {
    cancel();
    if ((to - from).abs() < 1) {
      applyOffset(to);
      _onTick();
      return Future.value();
    }

    _applyOffset = applyOffset;
    final controller = AnimationController(vsync: _vsync, duration: duration);
    _controller = controller;
    final animation = CurvedAnimation(parent: controller, curve: curve);
    final tween = Tween<double>(begin: from, end: to);

    void listener() {
      _applyOffset?.call(tween.evaluate(animation));
      _onTick();
    }

    controller.addListener(listener);
    var disposed = false;
    void disposeController() {
      if (disposed) return;
      disposed = true;
      controller.removeListener(listener);
      animation.dispose();
      controller.dispose();
      if (identical(_controller, controller)) {
        _controller = null;
        _applyOffset = null;
      }
    }

    final future = controller.forward().orCancel.catchError((_) {});
    return future.whenComplete(disposeController);
  }

  /// Stops an in-flight near-path animation without applying the final offset.
  ///
  /// Idempotent. Leaves [applyOffset] at the last tick value.
  void cancel() {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    _applyOffset = null;
    controller.stop();
  }

  /// Releases the animation controller. Idempotent.
  void dispose() => cancel();
}

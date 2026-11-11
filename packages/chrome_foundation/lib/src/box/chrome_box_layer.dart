import 'dart:async';

import 'package:flutter/widgets.dart';

/// One modal layer that hosts a stack of boxes: one barrier and one route for
/// however many boxes are opened on it.
///
/// A box shown on the layer ([show]) takes the place of the shown one at
/// once, with no animation; the box it covers keeps its state, hidden, and
/// comes back at once when the new box closes. Only the layer animates, on
/// its first box coming in and its last box going out.
///
/// What closes what:
///
/// | Action | Closes |
/// |---|---|
/// | `Navigator.pop(boxContext, result)`, Escape, a back button | the shown box, with `result`; the last one closes the layer |
/// | [closeBox] | the box of the context, shown or not |
/// | a tap on the barrier ([barrierDismissible]), [closeAll] | every box, and the layer |
///
/// Every box's future ([show]) completes once it closes: with the result it
/// was popped with, or null when it went with the layer. The layer's own
/// future (from `Navigator.push`, or [open]) completes when the layer goes,
/// with the result its first box closed with.
///
/// The layer centres the shown box over its barrier; a box sizes itself.
///
/// Why one route rather than a route per box: a route per box stacks a
/// barrier per box (the dim darkens with each), animates every swap, and
/// replacing one route with another loses the box below for good. Popping
/// inside one route is the navigator's own tool for that
/// ([Route.willHandlePopInternally]), so Escape, a back button and
/// `Navigator.maybePop` all close the shown box first.
final class ChromeBoxLayer extends PopupRoute<Object?> {
  /// A layer whose first box [builder] builds, over [barrierColor], coming in
  /// and going out over [transitionDuration].
  ChromeBoxLayer({
    required WidgetBuilder builder,
    required this.barrierColor,
    required this.transitionDuration,
    this.barrierLabel,
    this.barrierDismissible = true,
    this.overlay,
    super.requestFocus,
    super.settings,
  }) : _first = _LayerBox(builder) {
    _boxes.value = [_first];
  }

  /// Pushes a [ChromeBoxLayer] over [context]'s navigator; completes when the
  /// layer has gone, with what its first box closed with.
  static Future<T?> open<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    required Color barrierColor,
    required Duration transitionDuration,
    String? barrierLabel,
    bool barrierDismissible = true,
    bool? requestFocus,
    RouteSettings? settings,
    TransitionBuilder? overlay,
  }) async {
    final result = await Navigator.of(context).push(
      ChromeBoxLayer(
        builder: builder,
        barrierColor: barrierColor,
        transitionDuration: transitionDuration,
        barrierLabel: barrierLabel,
        barrierDismissible: barrierDismissible,
        overlay: overlay,
        requestFocus: requestFocus,
        settings: settings,
      ),
    );
    return result as T?;
  }

  /// The layer [context] is a box of, or null outside one.
  static ChromeBoxLayer? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BoxScope>()?.layer;

  /// The layer [context] is a box of.
  static ChromeBoxLayer of(BuildContext context) {
    final layer = maybeOf(context);
    assert(layer != null, 'ChromeBoxLayer.of called outside a box layer.');
    return layer!;
  }

  /// Whether the box [context] belongs to is the one shown: false for a box
  /// another box was shown over, and outside a layer.
  ///
  /// A box that asks its host for something checks it after asking: a host
  /// that answered by showing a box over it (a confirmation) wants it kept
  /// for when that box closes.
  static bool isShown(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_BoxScope>();
    if (scope == null) return false;
    return identical(scope.layer._boxes.value.lastOrNull, scope.box);
  }

  /// Closes the box [context] belongs to with [result], whether it is shown
  /// or under the shown one: a box under it goes without anything changing
  /// on the screen. Closing the last box closes the layer.
  static void closeBox(BuildContext context, [Object? result]) {
    final scope = context.getInheritedWidgetOfExactType<_BoxScope>();
    assert(scope != null, 'ChromeBoxLayer.closeBox called outside a box.');
    if (scope == null) return;
    scope.layer._close(scope.box, result);
  }

  @override
  final Color barrierColor;

  @override
  final String? barrierLabel;

  @override
  final bool barrierDismissible;

  @override
  final Duration transitionDuration;

  /// What the host lays over the layer's whole area, above the barrier and
  /// the shown box: given the faded boxes as its child, it returns them
  /// with its own layer on top (a bulletin host, so a notice raised while
  /// the layer is up shows over it). It does not fade with the boxes.
  final TransitionBuilder? overlay;

  final _boxes = ValueNotifier<List<_LayerBox>>(const []);

  // The box the layer opened with, closed or not.
  final _LayerBox _first;

  // What the first box closed with: the layer's result.
  Object? _firstResult;

  /// How many boxes the layer holds, the shown one included.
  int get depth => _boxes.value.length;

  /// Shows the box [builder] builds in place of the shown one, at once,
  /// keeping that one for when this box closes. Completes when the new box
  /// closes, with its result, or null when it goes with the layer.
  Future<T?> show<T>(WidgetBuilder builder) {
    assert(isActive, 'show on a layer that has gone.');
    final box = _LayerBox(builder);
    _boxes.value = [..._boxes.value, box];
    changedInternalState();
    return box.done.future.then((result) => result as T?);
  }

  /// Closes every box and the layer, as a tap on the barrier does: the shown
  /// box with [result], the others with null.
  ///
  /// The shown box stays on the screen as the layer fades out; none under it
  /// is shown again. A box whose answer ends the whole flow (a confirmed
  /// removal of what the box under it shows) closes the layer this way.
  void closeAll([Object? result]) {
    final boxes = _boxes.value;
    if (boxes.isEmpty || !isActive) return;
    for (final box in boxes.take(boxes.length - 1)) {
      _complete(box, null);
    }
    _boxes.value = [boxes.last];
    changedInternalState();
    if (isCurrent) {
      navigator!.pop(result);
    } else {
      _complete(boxes.last, result);
      navigator!.removeRoute(this, _firstResult);
    }
  }

  void _close(_LayerBox box, Object? result) {
    final boxes = _boxes.value;
    if (!boxes.contains(box)) return;
    if (boxes.length == 1) {
      if (isCurrent) {
        navigator!.pop(result);
      } else {
        _complete(box, result);
        navigator!.removeRoute(this, _firstResult);
      }
      return;
    }
    _complete(box, result);
    _boxes.value = [
      for (final other in boxes)
        if (other != box) other,
    ];
    changedInternalState();
  }

  void _complete(_LayerBox box, Object? result) {
    if (box.done.isCompleted) return;
    if (identical(box, _first)) _firstResult = result;
    box.done.complete(result);
  }

  @override
  bool get willHandlePopInternally =>
      _boxes.value.length > 1 || super.willHandlePopInternally;

  @override
  bool didPop(Object? result) {
    final boxes = _boxes.value;
    if (boxes.length > 1) {
      _close(boxes.last, result);
      return false;
    }
    if (boxes case [final last]) _complete(last, result);
    return super.didPop(_firstResult);
  }

  @override
  void dispose() {
    for (final box in _boxes.value) {
      _complete(box, null);
    }
    _boxes.dispose();
    super.dispose();
  }

  // The barrier closes every box, not only the shown one, which is what the
  // framework's barrier would do through the internal pop.
  @override
  Widget buildModalBarrier() => AnimatedModalBarrier(
    color: animation!.drive(
      ColorTween(begin: barrierColor.withValues(alpha: 0), end: barrierColor),
    ),
    dismissible: barrierDismissible,
    semanticsLabel: barrierLabel,
    onDismiss: closeAll,
  );

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => ValueListenableBuilder(
    valueListenable: _boxes,
    builder: (context, boxes, _) => Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final (index, box) in boxes.indexed)
            Visibility(
              key: ObjectKey(box),
              visible: index == boxes.length - 1,
              maintainState: true,
              child: _BoxScope(
                layer: this,
                box: box,
                child: Builder(builder: box.builder),
              ),
            ),
        ],
      ),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => switch (overlay) {
    final overlay? => overlay(
      context,
      FadeTransition(opacity: animation, child: child),
    ),
    null => FadeTransition(opacity: animation, child: child),
  };
}

final class _LayerBox {
  _LayerBox(this.builder);

  final WidgetBuilder builder;
  final done = Completer<Object?>();
}

class _BoxScope extends InheritedWidget {
  const _BoxScope({
    required this.layer,
    required this.box,
    required super.child,
  });

  final ChromeBoxLayer layer;
  final _LayerBox box;

  @override
  bool updateShouldNotify(_BoxScope oldWidget) =>
      !identical(layer, oldWidget.layer) || !identical(box, oldWidget.box);
}

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// [ScrollController] that builds positions which forward unused edge scroll
/// to the nearest same-axis ancestor [Scrollable].
///
/// When [mirror] is set, each created position is also attached there so a
/// caller holding that controller can read offset and jump without owning the
/// [Scrollable].
class OverscrollHandoffScrollController extends ScrollController {
  /// Creates a controller whose positions hand off edge scroll to an ancestor.
  OverscrollHandoffScrollController({
    ScrollController? mirror,
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  }) : _mirror = mirror;

  ScrollController? _mirror;

  /// Optional second controller that observes the same positions.
  ScrollController? get mirror => _mirror;

  /// Retargets [mirror] while keeping the live [ScrollPosition]s.
  ///
  /// Call when the widget-owned controller identity changes so the new
  /// controller receives attach/detach without rebuilding the scrollable.
  void updateMirror(ScrollController? next) {
    if (identical(_mirror, next)) {
      return;
    }
    if (_mirror case final previous?) {
      positions.forEach(previous.detach);
    }
    _mirror = next;
    if (next != null) {
      positions.forEach(next.attach);
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => OverscrollHandoffScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    debugLabel: debugLabel,
  );

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    _mirror?.attach(position);
  }

  @override
  void detach(ScrollPosition position) {
    _mirror?.detach(position);
    super.detach(position);
  }

  @override
  void dispose() {
    if (_mirror case final mirror?) {
      positions.toList().forEach(mirror.detach);
    }
    super.dispose();
  }
}

/// Nested [ScrollPosition] that keeps the drag on this scrollable and applies
/// unused outward delta / fling velocity to an ancestor on the same axis.
///
/// At `minScrollExtent` / `maxScrollExtent`, further motion in the outward
/// direction is applied to the parent instead of being discarded as empty
/// overscroll. Mid-range motion stays local.
///
/// Drag handoff uses [ScrollPosition.pointerScroll] because the ancestor is
/// typically idle ([applyUserOffset] requires an active scrolling activity).
/// Fling handoff uses [goBallistic] so velocity is preserved on the parent.
class OverscrollHandoffScrollPosition extends ScrollPositionWithSingleContext {
  /// Creates a handoff scroll position.
  OverscrollHandoffScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    super.initialPixels,
    super.keepScrollOffset,
    super.debugLabel,
  });

  ScrollPositionWithSingleContext? get _parentPosition {
    final notificationContext = context.notificationContext;
    if (notificationContext == null) {
      return null;
    }

    // [ScrollContext.notificationContext] is the gesture detector under this
    // Scrollable, so the first ancestor is usually this position's own host.
    var scrollable = notificationContext
        .findAncestorStateOfType<ScrollableState>();
    if (scrollable != null && identical(scrollable.position, this)) {
      scrollable = scrollable.context
          .findAncestorStateOfType<ScrollableState>();
    }

    final position = scrollable?.position;
    if (position is! ScrollPositionWithSingleContext ||
        position.axis != axis ||
        identical(position, this)) {
      return null;
    }
    return position;
  }

  bool get _atMin => pixels <= minScrollExtent + precisionErrorTolerance;

  bool get _atMax => pixels >= maxScrollExtent - precisionErrorTolerance;

  /// Positive [delta] decreases [pixels] (finger down on a vertical list).
  bool _shouldHandoffDrag(double delta) =>
      (delta > 0 && _atMin) || (delta < 0 && _atMax);

  /// Positive [velocity] increases [pixels] (fling toward max).
  bool _shouldHandoffBallistic(double velocity) =>
      (velocity > 0 && _atMax) || (velocity < 0 && _atMin);

  /// Applies [delta] with the same pixel effect as [applyUserOffset]
  /// (`pixels - delta`) while the parent may still be idle.
  void _handoffUserOffset(
    ScrollPositionWithSingleContext parent,
    double delta,
  ) {
    if (delta.abs() <= precisionErrorTolerance) {
      return;
    }
    // [pointerScroll] adds to pixels; negate so the result matches
    // [applyUserOffset]'s subtractive convention.
    parent.pointerScroll(-delta);
  }

  @override
  void applyUserOffset(double delta) {
    final parent = _parentPosition;
    if (parent == null || axis != Axis.vertical) {
      super.applyUserOffset(delta);
      return;
    }

    if (_shouldHandoffDrag(delta)) {
      _handoffUserOffset(parent, delta);
      return;
    }

    // Crossing an edge in one update: consume up to the bound, hand off the
    // remainder.
    final applied = physics.applyPhysicsToUserOffset(this, delta);
    final target = pixels - applied;
    if (target < minScrollExtent) {
      final deltaToMin = pixels - minScrollExtent;
      if (deltaToMin.abs() > precisionErrorTolerance) {
        super.applyUserOffset(deltaToMin);
      } else if (!_atMin) {
        forcePixels(minScrollExtent);
      }
      _handoffUserOffset(parent, delta - deltaToMin);
      return;
    }
    if (target > maxScrollExtent) {
      final deltaToMax = pixels - maxScrollExtent;
      if (deltaToMax.abs() > precisionErrorTolerance) {
        super.applyUserOffset(deltaToMax);
      } else if (!_atMax) {
        forcePixels(maxScrollExtent);
      }
      _handoffUserOffset(parent, delta - deltaToMax);
      return;
    }

    super.applyUserOffset(delta);
  }

  @override
  void goBallistic(double velocity) {
    final parent = _parentPosition;
    if (parent != null &&
        axis == Axis.vertical &&
        _shouldHandoffBallistic(velocity)) {
      parent.goBallistic(velocity);
      goIdle();
      return;
    }
    super.goBallistic(velocity);
  }
}

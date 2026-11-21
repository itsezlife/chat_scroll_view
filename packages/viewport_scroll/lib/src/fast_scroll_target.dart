import 'package:flutter/widgets.dart';

/// What a fast scrollbar drives: some scrolled content, read and moved as a
/// fraction of its whole length, whatever engine scrolls it.
///
/// Fraction-based because not every engine knows its content's length in
/// pixels: an anchor viewport over a list of unknown rows only estimates it.
/// A pixel interface would make every such engine fake an extent; a
/// fraction lets each say what it knows in its own terms.
///
/// The scrollbar reads [progress] and [visibleShare] whenever the target
/// notifies (a [Listenable]: on any move, and on any change of length or
/// viewport the engine can report), and on a scrollable's
/// `ScrollMetricsNotification` from under it. It moves the content with
/// [jumpTo] and stops it with [stop]; [dragStarted] and [dragEnded] bracket
/// a drag, for an engine that keeps something fixed while the finger moves.
///
/// Adapters: [ScrollControllerFastScrollTarget] here, and one beside each
/// engine that has its own scroll controller.
abstract class FastScrollTarget implements Listenable {
  /// Abstract constructor for subclasses.
  const FastScrollTarget();

  /// Where the content is: 0 at its start, 1 at its end; null while the
  /// content cannot scroll (its length unknown yet, or no longer than the
  /// view).
  double? get progress;

  /// The share of the content in view, in `(0, 1]`: 1 when it all fits.
  double get visibleShare;

  /// Moves the content to [progress] at once (clamped to `[0, 1]`),
  /// stopping any motion it had.
  void jumpTo(double progress);

  /// Stops any motion (a fling, an animation) where it is, moving nothing.
  void stop();

  /// A drag on the scrollbar began: the [jumpTo]s until [dragEnded] are its
  /// moves. Nothing by default.
  void dragStarted() {}

  /// The drag ended (lifted or cancelled). Nothing by default.
  void dragEnded() {}
}

/// A [FastScrollTarget] on the one position of a [ScrollController]: the
/// offset within the scroll range, the viewport against range plus
/// viewport.
///
/// Equal to another on the same controller, so a widget rebuilt with a new
/// adapter keeps its listeners.
@immutable
final class ScrollControllerFastScrollTarget extends FastScrollTarget {
  /// The target of [controller], whose scrollable must have one position.
  const ScrollControllerFastScrollTarget(this.controller);

  /// The controller moved.
  final ScrollController controller;

  ScrollPosition? get _position =>
      controller.positions.length == 1 ? controller.position : null;

  ScrollPosition? get _measured => switch (_position) {
    final p? when p.hasPixels && p.hasContentDimensions => p,
    _ => null,
  };

  @override
  double? get progress {
    final position = _measured;
    if (position == null) return null;
    final range = position.maxScrollExtent - position.minScrollExtent;
    if (range <= 0) return null;
    return ((position.pixels - position.minScrollExtent) / range).clamp(
      0.0,
      1.0,
    );
  }

  @override
  double get visibleShare {
    final position = _measured;
    if (position == null || !position.hasViewportDimension) return 1;
    final range = position.maxScrollExtent - position.minScrollExtent;
    final viewport = position.viewportDimension;
    if (range <= 0 || viewport <= 0) return 1;
    return viewport / (viewport + range);
  }

  /// The scroll offset at [progress], for a host whose labels are keyed by
  /// offset; the start of the range while it is unknown.
  double offsetAt(double progress) {
    final position = _measured;
    if (position == null) return 0;
    final min = position.minScrollExtent;
    return min + progress.clamp(0.0, 1.0) * (position.maxScrollExtent - min);
  }

  @override
  void jumpTo(double progress) {
    final position = _measured;
    if (position == null) return;
    position.jumpTo(offsetAt(progress));
  }

  // A jump to where it is ends a ballistic activity without moving.
  @override
  void stop() {
    final position = _measured;
    if (position == null) return;
    position.jumpTo(position.pixels);
  }

  @override
  void addListener(VoidCallback listener) => controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      controller.removeListener(listener);

  @override
  bool operator ==(Object other) =>
      other is ScrollControllerFastScrollTarget &&
      identical(other.controller, controller);

  @override
  int get hashCode => identityHashCode(controller);
}

import 'package:flutter/gestures.dart';
import 'package:swipe_pager/src/swipe_pager_physics.dart';

/// The swipe pager's drag recognizer: one pointer, claimed past
/// [SwipePagerPhysics.claimSlop] along the horizontal axis unless it first
/// went [SwipePagerPhysics.crossAxisSlop] across.
///
/// A stock `HorizontalDragGestureRecognizer` claims at the platform touch
/// slop whatever the vertical movement, so a slightly diagonal drag over a
/// vertical list is taken as a swipe; and it cannot give way across the
/// axis, catch a settle on the down, or start on a fling that never reached
/// its slop. Those are the reference pager's rules, so this recognizer
/// implements them.
///
/// The claim is decided on the straight line from the down position: the
/// drag is the pager's when it leaves the box `claimSlop` x `crossAxisSlop`
/// through a side, and not when it leaves through the top or bottom. That
/// makes the decision independent of how the platform samples the moves; a
/// finely sampled straight drag decides as the reference does event by
/// event.
///
/// Deltas reported to [onUpdate] are screen-space horizontal pixels; the
/// slop is consumed, so the first update after the claim starts from the
/// claim position and the page does not jump.
class SwipeDragRecognizer extends OneSequenceGestureRecognizer {
  /// A recognizer for the pointers of [supportedDevices].
  SwipeDragRecognizer({super.debugOwner, super.supportedDevices});

  /// The slops and the fling rule.
  SwipePagerPhysics physics = const SwipePagerPhysics();

  /// The device pixel ratio the physical velocities convert with.
  double devicePixelRatio = 1;

  /// Whether a drag by a screen-space horizontal [delta] can move the pager:
  /// there is a page that way and nothing holds it.
  bool Function(double delta) canMove = _never;

  /// Whether a down catches a running settle: the pager claims it at once.
  bool Function() catchesOnDown = _no;

  /// The drag is claimed; [caught] when it caught a settle.
  void Function({required bool caught})? onStart;

  /// The drag moved by a screen-space horizontal delta.
  void Function(double delta)? onUpdate;

  /// The drag ended with a velocity in logical pixels per second, clamped to
  /// [SwipePagerPhysics.maxVelocity]; a cancelled drag ends with none.
  void Function(Offset velocity)? onEnd;

  int? _pointer;
  PointerDeviceKind? _kind;
  Offset _origin = Offset.zero;
  Offset _last = Offset.zero;
  VelocityTracker? _velocity;
  // The arena gave the pointer to this recognizer. A lone member wins its
  // arena unasked, on the down; the swipe still waits for the slop then.
  bool _won = false;
  // This recognizer asked for the pointer: the slop or a fling said so.
  bool _requested = false;
  // The swipe started: [onStart] was called.
  bool _claimed = false;
  bool _caught = false;

  static bool _never(double delta) => false;
  static bool _no() => false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) return;
    _begin(event, event.position);
    if (catchesOnDown()) {
      _caught = true;
      _claim();
    }
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    if (_pointer != null) return;
    // A trackpad pan reports its offset from the start, not a position.
    _begin(event, Offset.zero);
    if (catchesOnDown()) {
      _caught = true;
      _claim();
    }
  }

  void _begin(PointerEvent event, Offset origin) {
    _pointer = event.pointer;
    _kind = event.kind;
    _origin = origin;
    _last = Offset.zero;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, origin);
    _won = false;
    _requested = false;
    _claimed = false;
    _caught = false;
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    switch (event) {
      case PointerMoveEvent(:final position, :final timeStamp):
        _velocity?.addPosition(timeStamp, position);
        _moved(position - _origin);
      case PointerPanZoomUpdateEvent(:final pan, :final timeStamp):
        _velocity?.addPosition(timeStamp, pan);
        _moved(pan);
      case PointerUpEvent() || PointerPanZoomEndEvent():
        _released();
        stopTrackingPointer(event.pointer);
      case PointerCancelEvent():
        if (_claimed) onEnd?.call(Offset.zero);
        stopTrackingPointer(event.pointer);
      default:
    }
  }

  void _moved(Offset offset) {
    if (_claimed) {
      final delta = offset.dx - _last.dx;
      _last = offset;
      if (delta != 0) onUpdate?.call(delta);
      return;
    }
    _last = offset;
    final along = offset.dx.abs() / _claimSlop;
    final across = offset.dy.abs() / physics.crossAxisSlop;
    if (along < 1 && across < 1) return;
    if (across >= along) {
      _giveUp();
      return;
    }
    // Past the slop toward an edge, or not yet more along than across: the
    // reference keeps watching rather than letting go.
    if (offset.dx.abs() <= offset.dy.abs() || !canMove(offset.dx)) return;
    _claim();
  }

  void _claim() {
    _requested = true;
    if (_won) {
      _start();
    } else {
      resolve(GestureDisposition.accepted);
    }
  }

  void _start() {
    if (_claimed) return;
    _claimed = true;
    onStart?.call(caught: _caught);
  }

  void _giveUp() {
    if (_won) {
      // Nobody else wanted the pointer; there is no arena to leave.
      if (_pointer case final pointer?) stopTrackingPointer(pointer);
    } else {
      resolve(GestureDisposition.rejected);
    }
  }

  /// The claim slop, never under the platform's drag slop for the pointer,
  /// so a nested scroller along the same axis always claims first: its
  /// recognizer sees each move before this one, and both claim strictly
  /// past their slop.
  double get _claimSlop {
    final platform = switch (_kind) {
      final kind? => computeHitSlop(kind, gestureSettings),
      null => kTouchSlop,
    };
    return physics.claimSlop > platform ? physics.claimSlop : platform;
  }

  void _released() {
    final velocity = _clamped(
      _velocity?.getVelocity().pixelsPerSecond ?? Offset.zero,
    );
    if (_claimed) {
      onEnd?.call(velocity);
      return;
    }
    if (physics.startsFling(
          velocity: velocity.dx,
          crossVelocity: velocity.dy,
          devicePixelRatio: devicePixelRatio,
        ) &&
        canMove(velocity.dx)) {
      _claim();
      if (_claimed) onEnd?.call(velocity);
    }
  }

  Offset _clamped(Offset velocity) {
    final max = physics.maxVelocity;
    return Offset(velocity.dx.clamp(-max, max), velocity.dy.clamp(-max, max));
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer != _pointer) return;
    _won = true;
    if (_requested) _start();
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer != _pointer) return;
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    if (!_claimed) resolve(GestureDisposition.rejected);
    _pointer = null;
    _kind = null;
    _velocity = null;
    _won = false;
    _requested = false;
    _claimed = false;
    _caught = false;
  }

  @override
  String get debugDescription => 'swipe pager drag';
}

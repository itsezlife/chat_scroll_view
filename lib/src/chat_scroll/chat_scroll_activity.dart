import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:chat_scroll_view/src/util/sine_in_out_curve.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Timing of the viewport's scroll-activity clock.
///
/// Scroll activity is a factor in `[0, 1]` that row chrome and day header
/// delegates read. It eases to `1` when the list starts moving, holds while it
/// moves, stays up for [idleDelay] once it settles, then eases to `0`.
/// Programmatic navigation (a jump, or an animated scroll to a message) keeps
/// it up for the longer [navigationIdleDelay] instead.
@immutable
final class ChatScrollActivityTiming {
  /// Clock timing; defaults hold 500 ms after a user scroll, 1000 ms after
  /// navigation, and fade over 150 ms along the exact sine ease-in-out
  /// `(1 - cos(πt)) / 2` ([Curves.easeInOutSine] is a cubic approximation
  /// of it).
  const ChatScrollActivityTiming({
    this.idleDelay = const Duration(milliseconds: 500),
    this.navigationIdleDelay = const Duration(milliseconds: 1000),
    this.fadeIn = const Duration(milliseconds: 150),
    this.fadeOut = const Duration(milliseconds: 150),
    this.curve = const SineInOutCurve(),
  });

  /// Hold after a user scroll settles, before fading out.
  final Duration idleDelay;

  /// Hold after programmatic navigation, before fading out.
  final Duration navigationIdleDelay;

  /// Ease to `1`.
  final Duration fadeIn;

  /// Ease to `0`.
  final Duration fadeOut;

  /// Easing for both fades.
  final Curve curve;

  @override
  bool operator ==(Object other) =>
      other is ChatScrollActivityTiming &&
      other.idleDelay == idleDelay &&
      other.navigationIdleDelay == navigationIdleDelay &&
      other.fadeIn == fadeIn &&
      other.fadeOut == fadeOut &&
      other.curve == curve;

  @override
  int get hashCode =>
      Object.hash(idleDelay, navigationIdleDelay, fadeIn, fadeOut, curve);
}

/// Scroll-activity state machine: a [Timer] for the idle hold and a [Ticker]
/// for the fades.
///
/// - [hold] — the list is moving; ease to `1` and cancel any pending hide.
/// - [release] — movement ended; hide after the pending delay.
/// - [pulse] — a discrete move (jump, step); show, and hide after the delay
///   unless a [hold] is active.
/// - [hide] — fade out now instead of after the pending delay, unless a
///   [hold] is active.
/// - [pinned] — chrome must stay fully shown; snap to `1` until cleared.
///
/// [value] changes inside ticker frames, and [onChanged] fires there — never
/// synchronously from [hold] / [release] / [pulse] / [hide], so callers may
/// use them from layout or gesture callbacks. Setting [pinned] is the one
/// synchronous change, and it does not notify.
///
/// Not an `AnimationController`: the owner is a render object with no
/// `TickerProvider`, and a zero-duration `animateTo` notifies synchronously.
@internal
final class ChatScrollActivityClock {
  /// Starts at rest at [initialValue] — idle at `0` by default — with no
  /// fade running and no hide pending.
  ChatScrollActivityClock({
    required ChatScrollActivityTiming timing,
    required VoidCallback onChanged,
    double initialValue = 0,
  }) : assert(
         initialValue >= 0 && initialValue <= 1,
         'initialValue must be in [0, 1]',
       ),
       _timing = timing,
       _onChanged = onChanged,
       _value = initialValue,
       _from = initialValue,
       _target = initialValue {
    _ticker = Ticker(_tick, debugLabel: 'ChatScrollActivityClock');
  }

  final VoidCallback _onChanged;
  late final Ticker _ticker;
  Timer? _hideTimer;

  ChatScrollActivityTiming _timing;

  /// Takes effect on the next hold, release, or fade.
  set timing(ChatScrollActivityTiming value) => _timing = value;

  /// Mutes fades while the host's `TickerMode` is off.
  set muted(bool value) => _ticker.muted = value;

  double _value;
  double _from;
  double _target;
  Duration _duration = Duration.zero;
  bool _holding = false;
  bool _pinned = false;

  /// Whether the next scheduled hide waits the navigation delay.
  bool _nextNavigation = false;
  bool _navigationHidePending = false;

  /// Current activity in `[0, 1]`.
  double get value => _value;

  /// Whether a [hold] is active.
  bool get isHolding => _holding;

  /// Whether a hide is pending and waits out the navigation delay — from a
  /// navigation [pulse], or a [release] after a navigation [hold]. `false`
  /// once it fires or is cancelled.
  bool get isNavigationHidePending => _navigationHidePending;

  /// While `true`, [value] stays at `1` with no pending hide. Setting it
  /// snaps [value] to `1` synchronously, without notifying; clearing it
  /// starts the idle delay unless a [hold] is active.
  set pinned(bool value) {
    if (_pinned == value) return;
    _pinned = value;
    if (value) {
      _cancelHide();
      _ticker.stop();
      _value = _from = _target = 1;
    } else if (!_holding) {
      _scheduleHide();
    }
  }

  /// The list is moving. Use [navigation] when the motion is programmatic,
  /// so the later [release] waits for the navigation delay.
  void hold({bool navigation = false}) {
    _holding = true;
    _cancelHide();
    _nextNavigation = navigation;
    _animateTo(1, _timing.fadeIn);
  }

  /// Movement ended. No-op unless a [hold] is active.
  void release() {
    if (!_holding) return;
    _holding = false;
    if (!_pinned) _scheduleHide();
  }

  /// A discrete move with no continuous motion to hold for; the later hide
  /// waits for the navigation delay when [navigation] is set, the user idle
  /// delay otherwise.
  void pulse({bool navigation = true}) {
    _nextNavigation = navigation;
    _animateTo(1, _timing.fadeIn);
    if (!_holding && !_pinned) _scheduleHide();
  }

  /// Starts the fade-out now: cancels a pending hide — a navigation delay
  /// included — and eases from the current value to `0` over the fade-out.
  /// No-op while a [hold] is active or [pinned]. The next hide waits the
  /// idle delay again.
  void hide() {
    if (_holding || _pinned) return;
    _cancelHide();
    _nextNavigation = false;
    _animateTo(0, _timing.fadeOut);
  }

  void _scheduleHide() {
    _cancelHide();
    _navigationHidePending = _nextNavigation;
    _nextNavigation = false;
    final delay = _navigationHidePending
        ? _timing.navigationIdleDelay
        : _timing.idleDelay;
    _hideTimer = Timer(delay, () {
      _hideTimer = null;
      _navigationHidePending = false;
      _animateTo(0, _timing.fadeOut);
    });
  }

  void _cancelHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _navigationHidePending = false;
  }

  void _animateTo(double target, Duration duration) {
    if (_target == target && (_ticker.isActive || _value == target)) return;
    _from = _value;
    _target = target;
    _duration = duration;
    _ticker
      ..stop()
      ..start();
  }

  void _tick(Duration elapsed) {
    final t = _duration <= Duration.zero
        ? 1.0
        : (elapsed.inMicroseconds / _duration.inMicroseconds).clamp(0.0, 1.0);
    final next = t >= 1.0
        ? _target
        : lerpDouble(_from, _target, _timing.curve.transform(t))!;
    if (t >= 1.0) _ticker.stop();
    if (next == _value) return;
    _value = next;
    _onChanged();
  }

  /// Cancels the pending hide and disposes the ticker.
  void dispose() {
    _cancelHide();
    _ticker.dispose();
  }
}

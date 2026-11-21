import 'dart:async';
import 'dart:math' as math;

import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';
import 'package:flutter/scheduler.dart';
import 'package:panel_presentation/panel_presentation.dart';

/// Feeds the platform's soft keyboard into a panel presentation's
/// [ImeInput]: each height the keyboard reports, its motion, and the bottom
/// safe area, as one [ImeSample].
///
/// The keyboard slot measures the keyboard with the bottom safe area in it;
/// a platform that reports it without that band gets the band added back
/// while the keyboard shows any height at all.
final class ImeSampleFeed {
  /// A feed of [keyboard] into [ime]. Reads the keyboard's resting height
  /// at once: a screen opened with the keyboard up has no event yet.
  ImeSampleFeed({required SoftKeyboardPort keyboard, required this.ime})
    : _keyboard = keyboard,
      _height = keyboard.restingHeight {
    _heights = keyboard.heights.listen(_onHeight);
    _motion = keyboard.animatingChanges.listen((_) => _onMotion());
  }

  /// Where the samples go.
  final ImeInput ime;

  final SoftKeyboardPort _keyboard;
  late final StreamSubscription<double> _heights;
  late final StreamSubscription<bool> _motion;
  double _height;
  // The height last reported, while paused the one a keyboard going down
  // is followed under.
  double? _reported;
  double _safeBottom = 0;
  var _paused = false;
  var _disposed = false;

  /// The keyboard's last reported height.
  double get height => _height;

  /// The bottom safe area; a change is reported.
  set safeBottom(double value) {
    if (_safeBottom == value) return;
    _safeBottom = value;
    report();
  }

  /// While paused (another surface owns the keyboard) a keyboard rising
  /// is not reported, but one going down still is: what this surface stood
  /// on is gone, so it is at rest when it is unpaused. Unpaused, the
  /// keyboard is reported as it is then, on a frame of its own when the
  /// unpause comes in a frame's build (a surface disposed as its route
  /// goes), where listeners could not rebuild.
  bool get paused => _paused;
  set paused(bool value) {
    if (_paused == value) return;
    _paused = value;
    if (!value) _reportWhenUnlocked();
  }

  void _onHeight(double height) {
    _height = height;
    if (_paused) {
      _followDown();
    } else {
      report();
    }
  }

  void _onMotion() {
    if (_paused) {
      _followDown();
    } else {
      report();
    }
  }

  // While paused: a keyboard at or under the height last reported.
  void _followDown() {
    final reported = _reported;
    if (reported == null || _height > reported) return;
    _send();
  }

  void _reportWhenUnlocked() {
    final scheduler = SchedulerBinding.instance;
    switch (scheduler.schedulerPhase) {
      case SchedulerPhase.idle || SchedulerPhase.postFrameCallbacks:
        report();
      case _:
        scheduler.addPostFrameCallback((_) => report());
    }
  }

  double get _heightWithSafeArea {
    final height = math.max<double>(0, _height);
    if (_keyboard.heightsIncludeSafeArea || height <= 0) return height;
    return height + _safeBottom;
  }

  /// Reports the keyboard as it is now.
  void report() {
    if (_paused) return;
    _send();
  }

  void _send() {
    if (_disposed) return;
    _reported = _height;
    ime.report(
      ImeSample(
        height: _heightWithSafeArea,
        animating: _keyboard.isAnimating,
        safeAreaBottom: _safeBottom,
      ),
    );
  }

  /// Stops listening. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_heights.cancel());
    unawaited(_motion.cancel());
  }
}

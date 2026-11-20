import 'dart:async';
import 'dart:math' as math;

import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';
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
    _motion = keyboard.animatingChanges.listen((_) => report());
  }

  /// Where the samples go.
  final ImeInput ime;

  final SoftKeyboardPort _keyboard;
  late final StreamSubscription<double> _heights;
  late final StreamSubscription<bool> _motion;
  double _height;
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

  /// While paused nothing is reported (another surface owns the keyboard);
  /// unpaused, the keyboard is reported as it is then.
  bool get paused => _paused;
  set paused(bool value) {
    if (_paused == value) return;
    _paused = value;
    if (!value) report();
  }

  void _onHeight(double height) {
    _height = height;
    report();
  }

  double get _heightWithSafeArea {
    final height = math.max<double>(0, _height);
    if (_keyboard.heightsIncludeSafeArea || height <= 0) return height;
    return height + _safeBottom;
  }

  /// Reports the keyboard as it is now.
  void report() {
    if (_disposed || _paused) return;
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

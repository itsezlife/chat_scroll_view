/// A soft keyboard the suite moves, in the host's input port.
///
/// The example host reads its keyboard from `SoftKeyboardPort` alone, not from
/// `MediaQuery`, so a scenario moves the keyboard by writing the port.
library;

import 'dart:async';

import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';

/// A soft keyboard the suite moves: heights in logical pixels, written by the
/// scenario one value per frame.
final class SyntheticSoftKeyboard implements SoftKeyboardPort {
  final StreamController<double> _heights = StreamController<double>.broadcast(
    sync: true,
  );
  final StreamController<bool> _animating = StreamController<bool>.broadcast(
    sync: true,
  );

  @override
  bool isAnimating = false;

  @override
  double restingHeight = 0;

  /// Android reports the keyboard without the bottom system bars.
  @override
  bool heightsIncludeSafeArea = false;

  /// The last height written, in logical pixels.
  double heightDp = 0;

  /// How many times the host asked the keyboard to hide.
  int hideCount = 0;

  @override
  Stream<double> get heights => _heights.stream;

  @override
  Stream<bool> get animatingChanges => _animating.stream;

  /// The keyboard moving through [height].
  void move(double height) {
    if (!isAnimating) {
      isAnimating = true;
      _animating.add(true);
    }
    heightDp = height;
    _heights.add(height);
  }

  /// The keyboard at rest at [height].
  void rest(double height) {
    heightDp = height;
    restingHeight = height;
    _heights.add(height);
    if (isAnimating) {
      isAnimating = false;
      _animating.add(false);
    }
  }

  @override
  Future<void> hide() async => hideCount++;

  Future<void> dispose() async {
    await _heights.close();
    await _animating.close();
  }
}

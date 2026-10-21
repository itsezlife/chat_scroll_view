import 'dart:async';

import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';

/// A soft keyboard a test moves by hand and whose commands it can count.
final class FakeSoftKeyboard implements SoftKeyboardPort {
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

  @override
  bool heightsIncludeSafeArea = true;

  /// How many times the keyboard was asked to hide.
  int hideCount = 0;

  @override
  Stream<double> get heights => _heights.stream;

  @override
  Stream<bool> get animatingChanges => _animating.stream;

  /// A reading of [height], as the system reports one.
  void move(double height, {bool animating = false}) {
    isAnimating = animating;
    _heights.add(height);
  }

  /// The keyboard stops moving where its last reading left it, and says so
  /// with no new height, as a platform that reports the end of the motion
  /// apart from the heights does.
  void stopMoving() {
    if (!isAnimating) return;
    isAnimating = false;
    _animating.add(false);
  }

  /// The keyboard finishes rising to [height] and rests.
  void rest(double height) {
    restingHeight = height;
    move(height);
  }

  @override
  Future<void> hide() async => hideCount++;

  /// Releases the stream.
  Future<void> dispose() async {
    await _heights.close();
    await _animating.close();
  }
}

import 'dart:async';

import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';

/// A soft keyboard a test moves by hand and whose commands it can count.
final class FakeSoftKeyboard implements SoftKeyboardPort {
  final StreamController<double> _heights = StreamController<double>.broadcast(
    sync: true,
  );

  @override
  bool isAnimating = false;

  @override
  double restingHeight = 0;

  @override
  bool heightsIncludeSafeArea = true;

  /// How many times the keyboard was asked to show.
  int showCount = 0;

  /// How many times the keyboard was asked to hide.
  int hideCount = 0;

  @override
  Stream<double> get heights => _heights.stream;

  /// A reading of [height], as the system reports one.
  void move(double height, {bool animating = false}) {
    isAnimating = animating;
    _heights.add(height);
  }

  /// The keyboard finishes rising to [height] and rests.
  void rest(double height) {
    restingHeight = height;
    move(height);
  }

  @override
  Future<void> hide() async => hideCount++;

  @override
  Future<void> show() async => showCount++;

  /// Releases the stream.
  Future<void> dispose() => _heights.close();
}

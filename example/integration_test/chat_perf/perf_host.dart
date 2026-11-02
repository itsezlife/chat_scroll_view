/// What a scenario runs on: a mounted chat viewport the device context can
/// drive. Two subjects implement it: the bench host and the real chat screen.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// A mounted viewport over a seeded history.
abstract interface class PerfHost {
  WidgetTester get tester;

  /// The controller of the mounted viewport.
  ChatScrollController get controller;

  /// Finds the viewport the pointer input goes to.
  Finder get viewport;

  /// Messages in the seeded history, ids `0..history-1`.
  int get history;

  /// Removes the viewport and returns the process to a comparable state.
  Future<void> dispose();
}

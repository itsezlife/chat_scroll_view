/// The real example chat screen as a scenario host (spec 4: chrome scenarios).
///
/// Mounts `ChatDemoApp` over a generated message source, with a synthetic soft
/// keyboard in the host's input port: the host reads the keyboard from that
/// port alone (`SoftKeyboardPort`), not from `MediaQuery`, so a scenario
/// moves the keyboard by writing the port.
library;

import 'dart:async';

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// A mounted chat screen.
final class ChatScreenHost {
  ChatScreenHost._(
    this.tester,
    this.services,
    this.keyboard,
    this.controller,
    this.pad,
    this.history,
  );

  /// Mounts the chat over a generated source of [history] messages and waits
  /// for its first message.
  static Future<ChatScreenHost> mount(WidgetTester tester, int history) async {
    final services = await AppServices.create(
      keyValueStore: FakeKeyValueStore(),
    );
    final keyboard = SyntheticSoftKeyboard();
    await tester.pumpWidget(
      ChatDemoApp(
        services: services,
        softKeyboard: keyboard,
        chatDataSourceLoader: () async =>
            GeneratedChatDataSource(messageCount: history),
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (find.byType(DemoMessageBubble).evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('no message in 30 s');
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 500));
    final view = tester.widget<ChatScrollView>(find.byType(ChatScrollView));
    return ChatScreenHost._(
      tester,
      services,
      keyboard,
      view.controller,
      view.bottomPadding!,
      history,
    );
  }

  final WidgetTester tester;
  final AppServices services;
  final SyntheticSoftKeyboard keyboard;
  final ChatScrollController controller;

  /// The pad the host reserves under the viewport, in logical pixels.
  final ValueListenable<double> pad;

  /// Messages in the seeded history.
  final int history;

  Finder get viewport => find.byType(ChatScrollView);

  /// Whether writing `viewInsets` on the view alone moves the host's pad.
  ///
  /// The host reads its keyboard from the port, so this is expected to be
  /// false; it is measured, not assumed.
  Future<bool> insetOverrideReachesPad() async {
    await tester.pump(const Duration(milliseconds: 100));
    final before = pad.value;
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final reached = (pad.value - before).abs() > 1;
    tester.view.resetViewInsets();
    await tester.pump(const Duration(milliseconds: 300));
    return reached;
  }

  /// Removes the screen and returns the process to a comparable state.
  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    services.dispose();
    await keyboard.dispose();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    PaintingBinding.instance.handleMemoryPressure();
    final end = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

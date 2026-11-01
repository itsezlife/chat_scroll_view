import 'package:chat_scroll_view/chat_scroll_view.dart' show ChatScrollView;
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/view/chat_page_route.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chat_scroll_view_example/src/features/chat_list/view/chat_list_screen.dart';
import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../panel_perf/scenario_support.dart' show settle;

/// Long enough that no fling reaches an end of the chat.
const int kWallpaperPerfMessages = 5000;

/// The real [ChatDemoApp] (chat, composer, glass, panel, wallpaper scopes
/// above the navigator) on generated messages, from clean storage.
///
/// [start] decides whether the app opens on the chat or on the chat list, from
/// which [openChat] pushes the chat as a product does.
final class WallpaperHarness {
  WallpaperHarness._(this._tester, this._services);

  final WidgetTester _tester;
  final AppServices _services;

  /// Mounts the app. With [DemoStart.chat] it returns once the first
  /// messages are on screen and the frames have settled; with
  /// [DemoStart.chatList], once the list is up.
  static Future<WallpaperHarness> start(
    WidgetTester tester, {
    required DemoStart start,
  }) async {
    final services = await AppServices.create(
      keyValueStore: FakeKeyValueStore(),
    );
    await tester.pumpWidget(
      ChatDemoApp(
        services: services,
        start: start,
        chatDataSourceLoader: () async =>
            GeneratedChatDataSource(messageCount: kWallpaperPerfMessages),
      ),
    );
    final harness = WallpaperHarness._(tester, services);
    switch (start) {
      case DemoStart.chat:
        await harness.waitForMessages();
      case DemoStart.chatList:
        await settle(tester);
    }
    return harness;
  }

  /// The app's one wallpaper motion controller.
  ChatWallpaperMotionController get motion => ChatWallpaperMotionScope.of(
    _tester.element(find.byType(Navigator).first),
  );

  /// Pumps until a message row shows, then lets the frames settle.
  Future<void> waitForMessages() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (find.byType(DemoMessageBubble).evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the chat showed no message within 30 s');
      }
      await _tester.pump(const Duration(milliseconds: 16));
    }
    await settle(_tester);
  }

  /// Taps row [index] of the chat list and waits until the pushed chat shows
  /// messages: the transition, the chat's first frames and its first rows.
  Future<void> openChat({int index = 0}) async {
    await _tester.tap(find.byKey(ChatListScreen.tileKey(index)));
    await _tester.pump();
    await waitForMessages();
  }

  /// Pops the chat back to the list, as the system back gesture does, and
  /// waits for the transition to end.
  Future<void> closeChat() async {
    await _tester.binding.handlePopRoute();
    await _tester.pump();
    await _tester.pump(ChatPageRoute.duration);
    await settle(_tester);
  }

  /// Flings the chat towards older messages and back, [times] each way.
  Future<void> flingChat({int times = 4}) async {
    final chat = find.byType(ChatScrollView);
    for (var i = 0; i < times; i++) {
      await _tester.fling(chat, const Offset(0, 500), 4000);
      await _tester.pump(const Duration(milliseconds: 300));
    }
    await settle(_tester);
    for (var i = 0; i < times; i++) {
      await _tester.fling(chat, const Offset(0, -500), 4000);
      await _tester.pump(const Duration(milliseconds: 300));
    }
    await settle(_tester);
  }

  /// Opens the emoji panel from the composer and closes it again.
  Future<void> togglePanel() async {
    final button = find.byKey(
      const ValueKey<String>(ChatComposerActions.panel),
    );
    await _tester.tap(button);
    await _tester.pump();
    await settle(_tester);
    await _tester.pump(const Duration(milliseconds: 500));
    await _tester.tap(button);
    await _tester.pump();
    await settle(_tester);
  }

  /// Resizes the window through [sizes] (logical), one size per frame as a
  /// window drag delivers them, then holds the last size while the wallpaper
  /// settles.
  Future<void> resizeThrough(List<Size> sizes) async {
    final view = _tester.view;
    for (final size in sizes) {
      view.physicalSize = size * view.devicePixelRatio;
      await _tester.pump(const Duration(milliseconds: 16));
    }
    await _tester.pump(const Duration(milliseconds: 700));
    await settle(_tester);
  }

  /// The window's logical size now.
  Size get windowSize =>
      _tester.view.physicalSize / _tester.view.devicePixelRatio;

  /// Unmounts the app, gives the view its size back and frees the services.
  Future<void> dispose() async {
    await _tester.pumpWidget(const SizedBox.shrink());
    _tester.view.resetPhysicalSize();
    _services.dispose();
  }
}

/// The real chat screen as a perf subject: `ChatDemoApp` through
/// `chatDataSourceLoader`, production bubbles and widgets, on generated
/// messages (no backend, no network).
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'perf_host.dart';

/// A mounted real chat screen over [history] generated messages.
final class RealChatHost implements PerfHost {
  RealChatHost._(this.tester, this._services, this.history);

  /// Mounts the screen from clean storage and waits for the first messages.
  static Future<RealChatHost> mount(WidgetTester tester, int history) async {
    final services = await AppServices.create(
      keyValueStore: FakeKeyValueStore(),
    );
    await tester.pumpWidget(
      ChatDemoApp(
        services: services,
        chatDataSourceLoader: () async =>
            GeneratedChatDataSource(messageCount: history),
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (find.byType(DemoMessageBubble).evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('chat screen showed no message within 30 s');
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 500));
    return RealChatHost._(tester, services, history);
  }

  @override
  final WidgetTester tester;
  final AppServices _services;

  @override
  final int history;

  @override
  Finder get viewport => find.byType(ChatScrollView);

  @override
  ChatScrollController get controller =>
      tester.widget<ChatScrollView>(viewport).controller;

  @override
  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    _services.dispose();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

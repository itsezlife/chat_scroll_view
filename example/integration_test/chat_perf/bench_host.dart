/// The bench host: a minimal host of the public `ChatScrollView` API with
/// fixed deterministic bubble builders, so a bubble or screen change cannot
/// move engine numbers.
///
/// Public API only: the `@internal` scroll mutators are never called; scenarios
/// drive the viewport by pointer gestures and the public controller.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'corpus.dart';

/// Fixed bubble: one rounded rectangle and one paragraph, nothing else.
Widget benchBubble(
  BuildContext context,
  int id,
  IChatMessage? message,
  ChatMessageStatus status,
  MessageRunLayout runLayout,
) {
  if (message case BenchMessage(:final text)) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: id.isEven ? const Color(0xFFE3F2FD) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ),
      ),
    );
  }
  return const SizedBox(height: 60);
}

/// A mounted viewport over a seeded corpus.
final class BenchHost {
  BenchHost._(this.tester, this.source, this.controller);

  /// Mounts a fresh host over [corpus], at the newest message.
  static Future<BenchHost> mount(
    WidgetTester tester,
    BenchCorpus corpus,
  ) async {
    final source = BenchDataSource(corpus);
    final controller = ChatScrollController();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: ChatScrollView(
            reverse: true,
            dataSource: source,
            controller: controller,
            isSelfMessage: (m) => m.sender == kBenchSelf,
            messageBuilder: benchBubble,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    return BenchHost._(tester, source, controller);
  }

  final WidgetTester tester;
  final BenchDataSource source;
  final ChatScrollController controller;

  Finder get viewport => find.byType(ChatScrollView);

  /// Removes the viewport and releases its controller, between scenarios.
  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    source.dispose();
  }
}

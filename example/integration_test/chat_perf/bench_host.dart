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
import 'perf_host.dart';

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

/// The inline separator and floating date pill of the bench host.
Widget _datePill(BuildContext context, Object bucket, DateTime date) => Center(
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF455A64),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          '${date.year}-${date.month}-${date.day}',
          style: const TextStyle(fontSize: 12, color: Color(0xFFFFFFFF)),
        ),
      ),
    ),
  ),
);

/// A mounted viewport over a seeded corpus.
final class BenchHost implements PerfHost {
  BenchHost._(this.tester, this.source, this.controller);

  /// Mounts a fresh host over [corpus], at the newest message.
  static Future<BenchHost> mount(
    WidgetTester tester,
    BenchCorpus corpus, {
    bool floatingDayHeader = false,
  }) async {
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
            scrollActivityTiming: floatingDayHeader
                ? const ChatScrollActivityTiming()
                : null,
            dayHeaderDelegate: floatingDayHeader
                ? const ChatPushingDayHeader()
                : const ChatFadingDayHeader(),
            dateSeparatorBuilder: floatingDayHeader ? _datePill : null,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    return BenchHost._(tester, source, controller);
  }

  @override
  final WidgetTester tester;
  final BenchDataSource source;
  @override
  final ChatScrollController controller;

  @override
  int get history => source.corpus.count;

  @override
  Finder get viewport => find.byType(ChatScrollView);

  /// Removes the viewport, releases its controller and returns the process to
  /// a comparable state, between scenarios: image caches cleared, memory
  /// pressure signalled (the engine drops its caches) and a GC settle awaited.
  @override
  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    source.dispose();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    PaintingBinding.instance.handleMemoryPressure();
    await _gcSettle(tester);
  }

  /// Dart offers no forced collection: idle in real time with frames running
  /// so the collector finishes before the next scenario's window.
  static Future<void> _gcSettle(WidgetTester tester) async {
    final end = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

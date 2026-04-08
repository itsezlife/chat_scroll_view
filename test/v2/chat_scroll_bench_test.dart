// Headless ChatScrollView benchmarks (flutter test).
//
// Baseline results (2026-04-09, macOS, debug mode, flutter test):
//
//   Layout:
//     32 msgs:   mean=32µs  median=32µs  p95=32µs
//     256 msgs:  mean=22µs  median=22µs  p95=22µs
//     6000 msgs: mean=15µs  median=15µs  p95=15µs
//
//   Paint (scroll-only):
//     32 msgs:   mean=7.5µs  median=5µs  p95=15µs
//     256 msgs:  mean=2.3µs  median=2µs  p95=3µs
//     6000 msgs: mean=1.4µs  median=1µs  p95=3µs
//
//   Fling (frame time):
//     32 msgs:   mean=41µs  median=23µs  p95=118µs
//     256 msgs:  mean=27µs  median=15µs  p95=78µs
//     6000 msgs: mean=21µs  median=14µs  p95=48µs
//
//   Memory (static):
//     32 msgs:   attached=8   total=64   chunks=1
//     256 msgs:  attached=10  total=64   chunks=4
//     6000 msgs: attached=8   total=64   chunks=16
//
//   Leak detection (256 msgs, 50 cycles): range=0 (stable)
//   Resize stress (256 msgs, 200 frames): mean=20µs

import 'dart:ui' as ui;

import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_message_render.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../benchmark/shared/metrics.dart';
import '../benchmark/shared/test_messages.dart';

// ---------------------------------------------------------------------------
// Bench message render
// ---------------------------------------------------------------------------

class _BenchMessageRender extends ChatMessageRender {
  _BenchMessageRender(Object? message) {
    if (message is IChatMessage) _updateText(message);
  }

  static const double _padding = 12.0;
  static const double _bubblePadding = 16.0;
  static const double _bubbleRadius = 12.0;

  IChatMessage? _message;
  ui.Paragraph? _paragraph;

  void _updateText(IChatMessage message) {
    _message = message;
    dirty = true;
  }

  @override
  void update(Object? message, ChatMessageStatus status) {
    if (identical(_message, message)) return;
    if (message is! IChatMessage) {
      _message = null;
      _paragraph = null;
      dirty = true;
      return;
    }
    _updateText(message);
  }

  @override
  double performLayout(double availableWidth) {
    final message = _message;
    if (message == null) return 0.0;
    final content = switch (message) {
      ChatMessage$User(:final content) => content,
      ChatMessage$System(:final content) => content,
      _ => 'Message #${message.id}',
    };
    final textWidth = availableWidth - _bubblePadding * 2 - _padding * 2;
    final builder =
        ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 15.0, height: 1.4))
          ..pushStyle(ui.TextStyle(color: const Color(0xFF1A1A1A)))
          ..addText(content)
          ..pop();
    _paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: textWidth));
    return _paragraph!.height + _bubblePadding * 2 + _padding;
  }

  @override
  void paintMessage(Canvas canvas, Size size) {
    final paragraph = _paragraph;
    if (paragraph == null) return;
    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        _padding,
        _padding / 2,
        size.width - _padding * 2,
        size.height - _padding,
      ),
      const Radius.circular(_bubbleRadius),
    );
    final isEven = (_message?.id ?? 0).isEven;
    final bgColor = isEven ? const Color(0xFFE3F2FD) : const Color(0xFFF5F5F5);
    canvas.drawRRect(bubbleRect, Paint()..color = bgColor);
    canvas.save();
    canvas.translate(_padding + _bubblePadding, _padding / 2 + _bubblePadding);
    canvas.drawParagraph(paragraph, Offset.zero);
    canvas.restore();
  }

  @override
  void dispose() {
    _paragraph = null;
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Test data source
// ---------------------------------------------------------------------------

class _BenchDataSource extends ChatDataSource {
  _BenchDataSource(List<IChatMessage> messages) {
    upsertMessages(messages);
  }

  @override
  Future<List<IChatMessage>> fetch({
    int? from,
    int? to,
    DateTime? after,
  }) async => const [];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildCSV(_BenchDataSource dataSource, ChatScrollController controller) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 800,
          child: ChatScrollView(
            dataSource: dataSource,
            controller: controller,
            builder: _BenchMessageRender.new,
          ),
        ),
      ),
    );

RenderChatScrollView _findRender(WidgetTester tester) =>
    tester.renderObject<RenderChatScrollView>(find.byType(ChatScrollView));

// ---------------------------------------------------------------------------
// Benchmarks (mirror v1 test structure)
// ---------------------------------------------------------------------------

const _kSmall = 32;
const _kMedium = 256;
const _kLarge = 6000;

void main() {
  group('ChatScrollView benchmarks', () {
    for (final count in [_kSmall, _kMedium, _kLarge]) {
      testWidgets('layout — $count messages', (tester) async {
        final messages = generateMessages(count);
        final dataSource = _BenchDataSource(messages);
        final controller = ChatScrollController()
          ..oldestKnownId = 0
          ..newestKnownId = count - 1
          ..reachedOldest = true
          ..reachedNewest = true;
        controller.jumpTo(count - 1);

        await tester.pumpWidget(_buildCSV(dataSource, controller));
        await tester.pumpAndSettle();

        final render = _findRender(tester);
        const warmup = 10;
        const measured = 100;

        // Warmup
        for (var i = 0; i < warmup; i++) {
          tester.view.physicalSize = Size(401.0 + i % 2, 800.0);
          tester.view.devicePixelRatio = 1.0;
          await tester.pump();
        }

        // Reset to stable size
        tester.view.physicalSize = const Size(400.0, 800.0);
        tester.view.devicePixelRatio = 1.0;
        await tester.pump();

        // Measure layout
        final samples = <int>[];
        for (var i = 0; i < measured; i++) {
          tester.view.physicalSize = Size(400.0 + (i.isEven ? 0 : 1), 800.0);
          tester.view.devicePixelRatio = 1.0;
          await tester.pump();
          samples.add(render.debugLastLayoutDuration.inMicroseconds);
        }

        final metrics = BenchmarkMetrics('CSV layout ($count msgs)', samples);
        // ignore: avoid_print
        print(metrics);

        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      testWidgets('paint scroll-only — $count messages', (tester) async {
        final messages = generateMessages(count);
        final dataSource = _BenchDataSource(messages);
        final controller = ChatScrollController()
          ..oldestKnownId = 0
          ..newestKnownId = count - 1
          ..reachedOldest = true
          ..reachedNewest = true;
        controller.jumpTo(count - 1);

        await tester.pumpWidget(_buildCSV(dataSource, controller));
        await tester.pumpAndSettle();

        final render = _findRender(tester);
        const warmup = 10;
        const measured = 300;

        // Warmup: scroll via applyScrollDelta + markNeedsLayout
        // Use applyScrollDelta + markNeedsLayout to force paint
        for (var i = 0; i < warmup; i++) {
          controller.applyScrollDelta(5.0);
          render.markNeedsLayout();
          await tester.pump();
        }

        // Measure: use applyScrollDelta + markNeedsPaint to simulate scroll-only
        final samples = <int>[];
        for (var i = 0; i < measured; i++) {
          controller.applyScrollDelta(3.0);
          render.markNeedsPaint();
          await tester.pump();
          samples.add(render.debugLastPaintDuration.inMicroseconds);
        }

        final metrics = BenchmarkMetrics(
          'CSV paint scroll-only ($count msgs)',
          samples,
        );
        // ignore: avoid_print
        print(metrics);
      });

      testWidgets('fling — $count messages', (tester) async {
        final messages = generateMessages(count);
        final dataSource = _BenchDataSource(messages);
        final controller = ChatScrollController()
          ..oldestKnownId = 0
          ..newestKnownId = count - 1
          ..reachedOldest = true
          ..reachedNewest = true;
        controller.jumpTo(count - 1);

        await tester.pumpWidget(_buildCSV(dataSource, controller));
        await tester.pumpAndSettle();

        // Scroll to middle first
        controller.jumpTo(count ~/ 2);
        await tester.pumpAndSettle();

        // Measure total frame time during fling
        final samples = <int>[];
        await tester.fling(
          find.byType(ChatScrollView),
          const Offset(0, -500),
          2000.0,
        );

        for (var i = 0; i < 300; i++) {
          final sw = Stopwatch()..start();
          await tester.pump(const Duration(milliseconds: 16));
          samples.add(sw.elapsed.inMicroseconds);
        }

        final metrics = BenchmarkMetrics(
          'CSV fling frame ($count msgs)',
          samples,
        );
        // ignore: avoid_print
        print(metrics);
      });
    }

    testWidgets('memory — static counts', (tester) async {
      for (final count in [_kSmall, _kMedium, _kLarge]) {
        final messages = generateMessages(count);
        final dataSource = _BenchDataSource(messages);
        final controller = ChatScrollController()
          ..oldestKnownId = 0
          ..newestKnownId = count - 1
          ..reachedOldest = true
          ..reachedNewest = true;
        controller.jumpTo(count - 1);

        await tester.pumpWidget(_buildCSV(dataSource, controller));
        await tester.pumpAndSettle();

        final render = _findRender(tester);

        final snapshot = MemorySnapshot(
          label: 'CSV static ($count msgs)',
          attachedRenders: render.debugAttachedRenderCount,
          totalRenders: render.debugTotalRenderCount,
          chunkCount: render.debugChunkCount,
        );
        // ignore: avoid_print
        print(snapshot);

        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('memory — scroll through all (256 msgs)', (tester) async {
      final messages = generateMessages(_kMedium);
      final dataSource = _BenchDataSource(messages);
      final controller = ChatScrollController()
        ..oldestKnownId = 0
        ..newestKnownId = _kMedium - 1
        ..reachedOldest = true
        ..reachedNewest = true;
      controller.jumpTo(_kMedium - 1);

      await tester.pumpWidget(_buildCSV(dataSource, controller));
      await tester.pumpAndSettle();

      final render = _findRender(tester);

      var peakAttached = render.debugAttachedRenderCount;
      var peakTotal = render.debugTotalRenderCount;

      for (var id = _kMedium - 1; id >= 0; id -= 4) {
        controller.jumpTo(id);
        await tester.pump();
        final attached = render.debugAttachedRenderCount;
        final total = render.debugTotalRenderCount;
        if (attached > peakAttached) peakAttached = attached;
        if (total > peakTotal) peakTotal = total;
      }

      // ignore: avoid_print
      print(
        'CSV scroll-through peak: attached=$peakAttached '
        'total=$peakTotal chunks=${render.debugChunkCount}',
      );

      controller.jumpTo(_kMedium - 1);
      await tester.pumpAndSettle();

      // ignore: avoid_print
      print(
        'CSV after return: attached=${render.debugAttachedRenderCount} '
        'total=${render.debugTotalRenderCount} '
        'chunks=${render.debugChunkCount}',
      );
    });

    testWidgets('leak detection — 50 scroll cycles (256 msgs)', (tester) async {
      final messages = generateMessages(_kMedium);
      final dataSource = _BenchDataSource(messages);
      final controller = ChatScrollController()
        ..oldestKnownId = 0
        ..newestKnownId = _kMedium - 1
        ..reachedOldest = true
        ..reachedNewest = true;
      controller.jumpTo(_kMedium - 1);

      await tester.pumpWidget(_buildCSV(dataSource, controller));
      await tester.pumpAndSettle();

      final render = _findRender(tester);
      final initialAttached = render.debugAttachedRenderCount;

      final attachedCounts = <int>[];

      for (var cycle = 0; cycle < 50; cycle++) {
        controller.jumpTo(0);
        await tester.pump();
        controller.jumpTo(_kMedium - 1);
        await tester.pump();
        attachedCounts.add(render.debugAttachedRenderCount);
      }

      final maxAttached = attachedCounts.reduce((a, b) => a > b ? a : b);
      final minAttached = attachedCounts.reduce((a, b) => a < b ? a : b);

      // ignore: avoid_print
      print(
        'CSV leak test: initial=$initialAttached '
        'min=$minAttached max=$maxAttached '
        'range=${maxAttached - minAttached}',
      );

      expect(
        maxAttached - minAttached,
        lessThan(10),
        reason: 'Attached render count should be stable across cycles',
      );
    });

    testWidgets('resize stress — 200 frames', (tester) async {
      final messages = generateMessages(_kMedium);
      final dataSource = _BenchDataSource(messages);
      final controller = ChatScrollController()
        ..oldestKnownId = 0
        ..newestKnownId = _kMedium - 1
        ..reachedOldest = true
        ..reachedNewest = true;
      controller.jumpTo(_kMedium - 1);

      await tester.pumpWidget(_buildCSV(dataSource, controller));
      await tester.pumpAndSettle();

      final render = _findRender(tester);
      final samples = <int>[];

      for (var i = 0; i < 200; i++) {
        final width = 400.0 + (i < 100 ? i : 200 - i);
        tester.view.physicalSize = Size(width, 800.0);
        tester.view.devicePixelRatio = 1.0;
        await tester.pump();
        final total =
            render.debugLastLayoutDuration.inMicroseconds +
            render.debugLastPaintDuration.inMicroseconds;
        samples.add(total);
      }

      final metrics = BenchmarkMetrics('CSV resize stress', samples);
      // ignore: avoid_print
      print(metrics);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}

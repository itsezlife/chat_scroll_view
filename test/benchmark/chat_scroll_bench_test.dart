import 'dart:ui' as ui;

import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shared/metrics.dart';
import 'shared/test_messages.dart';

/// Message render identical to _DemoMessageRender in main.dart.
class _BenchMessageRender extends ChatMessageRender {
  _BenchMessageRender(IChatMessage? message) {
    if (message != null) _updateText(message);
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
  void update(IChatMessage? message, ChatMessageStatus status) {
    if (identical(_message, message)) return;
    if (message == null) {
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
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: 15.0, height: 1.4),
    )
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
          _padding, _padding / 2, size.width - _padding * 2, size.height - _padding),
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

Widget _buildCSV(BenchmarkChatController controller) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 800,
          child: ChatScrollView(
            controller: controller,
            builder: _BenchMessageRender.new,
          ),
        ),
      ),
    );

RenderChatScrollView _findRender(WidgetTester tester) =>
    tester.renderObject<RenderChatScrollView>(find.byType(ChatScrollView));

void main() {
  group('ChatScrollView benchmarks', () {
    for (final count in [kSmall, kMedium, kLarge]) {
      testWidgets('layout — $count messages', (tester) async {
        final messages = generateMessages(count);
        final controller = BenchmarkChatController(messages);

        await tester.pumpWidget(_buildCSV(controller));
        await tester.pumpAndSettle();

        final render = _findRender(tester);
        const warmup = 10;
        const measured = 100;

        // Warmup
        for (var i = 0; i < warmup; i++) {
          // Force full relayout by toggling width
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
          // Toggle width to force relayout
          tester.view.physicalSize = Size(400.0 + (i.isEven ? 0 : 1), 800.0);
          tester.view.devicePixelRatio = 1.0;
          await tester.pump();
          samples.add(render.debugLastLayoutDuration.inMicroseconds);
        }

        final metrics = BenchmarkMetrics('CSV layout ($count msgs)', samples);
        // ignore: avoid_print
        print(metrics);

        // Reset
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();

        controller.dispose();
      });

      testWidgets('paint scroll-only — $count messages', (tester) async {
        final messages = generateMessages(count);
        final controller = BenchmarkChatController(messages);

        await tester.pumpWidget(_buildCSV(controller));
        await tester.pumpAndSettle();

        final render = _findRender(tester);
        const warmup = 10;
        const measured = 300;

        // Warmup: scroll a bit
        for (var i = 0; i < warmup; i++) {
          controller.anchorPixelOffset -= 5.0;
          await tester.pump();
        }

        // Measure scroll-only paint
        final samples = <int>[];
        for (var i = 0; i < measured; i++) {
          controller.anchorPixelOffset -= 3.0;
          await tester.pump();
          samples.add(render.debugLastPaintDuration.inMicroseconds);
        }

        final metrics =
            BenchmarkMetrics('CSV paint scroll-only ($count msgs)', samples);
        // ignore: avoid_print
        print(metrics);

        controller.dispose();
      });

      testWidgets('fling — $count messages', (tester) async {
        final messages = generateMessages(count);
        final controller = BenchmarkChatController(messages);

        await tester.pumpWidget(_buildCSV(controller));
        await tester.pumpAndSettle();

        // Scroll to middle first
        controller.jumpTo(count ~/ 2);
        await tester.pumpAndSettle();

        // Measure total frame time during fling
        final samples = <int>[];
        await tester.fling(
            find.byType(ChatScrollView), const Offset(0, -500), 2000.0);

        for (var i = 0; i < 300; i++) {
          final sw = Stopwatch()..start();
          await tester.pump(const Duration(milliseconds: 16));
          samples.add(sw.elapsed.inMicroseconds);
        }

        final metrics =
            BenchmarkMetrics('CSV fling frame ($count msgs)', samples);
        // ignore: avoid_print
        print(metrics);

        controller.dispose();
      });
    }

    testWidgets('memory — static counts', (tester) async {
      for (final count in [kSmall, kMedium, kLarge]) {
        final messages = generateMessages(count);
        final controller = BenchmarkChatController(messages);

        await tester.pumpWidget(_buildCSV(controller));
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

        controller.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('memory — scroll through all (256 msgs)', (tester) async {
      final messages = generateMessages(kMedium);
      final controller = BenchmarkChatController(messages);

      await tester.pumpWidget(_buildCSV(controller));
      await tester.pumpAndSettle();

      final render = _findRender(tester);

      // Scroll from newest to oldest (upward)
      controller.jumpTo(kMedium - 1);
      await tester.pumpAndSettle();

      var peakAttached = render.debugAttachedRenderCount;
      var peakTotal = render.debugTotalRenderCount;

      // Scroll through all messages
      for (var id = kMedium - 1; id >= 0; id -= 4) {
        controller.jumpTo(id);
        await tester.pump();
        final attached = render.debugAttachedRenderCount;
        final total = render.debugTotalRenderCount;
        if (attached > peakAttached) peakAttached = attached;
        if (total > peakTotal) peakTotal = total;
      }

      // ignore: avoid_print
      print('CSV scroll-through peak: attached=$peakAttached '
          'total=$peakTotal chunks=${render.debugChunkCount}');

      // Return to start and check
      controller.jumpTo(kMedium - 1);
      await tester.pumpAndSettle();

      // ignore: avoid_print
      print('CSV after return: attached=${render.debugAttachedRenderCount} '
          'total=${render.debugTotalRenderCount} '
          'chunks=${render.debugChunkCount}');

      controller.dispose();
    });

    testWidgets('leak detection — 50 scroll cycles (256 msgs)',
        (tester) async {
      final messages = generateMessages(kMedium);
      final controller = BenchmarkChatController(messages);

      await tester.pumpWidget(_buildCSV(controller));
      await tester.pumpAndSettle();

      final render = _findRender(tester);
      final initialAttached = render.debugAttachedRenderCount;

      final attachedCounts = <int>[];

      for (var cycle = 0; cycle < 50; cycle++) {
        // Scroll to start
        controller.jumpTo(0);
        await tester.pump();
        // Scroll to end
        controller.jumpTo(kMedium - 1);
        await tester.pump();

        attachedCounts.add(render.debugAttachedRenderCount);
      }

      final maxAttached =
          attachedCounts.reduce((a, b) => a > b ? a : b);
      final minAttached =
          attachedCounts.reduce((a, b) => a < b ? a : b);

      // ignore: avoid_print
      print('CSV leak test: initial=$initialAttached '
          'min=$minAttached max=$maxAttached '
          'range=${maxAttached - minAttached}');

      // Range should be small (no growing trend)
      expect(maxAttached - minAttached, lessThan(10),
          reason: 'Attached render count should be stable across cycles');

      controller.dispose();
    });

    testWidgets('resize stress — 200 frames', (tester) async {
      final messages = generateMessages(kMedium);
      final controller = BenchmarkChatController(messages);

      await tester.pumpWidget(_buildCSV(controller));
      await tester.pumpAndSettle();

      final render = _findRender(tester);
      final samples = <int>[];

      for (var i = 0; i < 200; i++) {
        // Oscillate width 400..500..400
        final width = 400.0 + (i < 100 ? i : 200 - i);
        tester.view.physicalSize = Size(width, 800.0);
        tester.view.devicePixelRatio = 1.0;
        await tester.pump();
        final total = render.debugLastLayoutDuration.inMicroseconds +
            render.debugLastPaintDuration.inMicroseconds;
        samples.add(total);
      }

      final metrics = BenchmarkMetrics('CSV resize stress', samples);
      // ignore: avoid_print
      print(metrics);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      controller.dispose();
    });
  });
}

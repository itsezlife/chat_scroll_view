// Comparative benchmark: ChatScrollView vs ListView.builder (CustomPaint).
// Runs identical scenarios side-by-side and prints a markdown comparison table.
import 'dart:ui' as ui;

import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_scroll_view_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shared/listview_chat.dart';
import 'shared/metrics.dart';
import 'shared/test_messages.dart';

// ---------------------------------------------------------------------------
// ChatScrollView message render (identical to _DemoMessageRender)
// ---------------------------------------------------------------------------

class _BenchMessageRender extends ChatMessageRender {
  _BenchMessageRender(IChatMessage? message) {
    if (message != null) _updateText(message);
  }

  static const double _padding = 12.0;
  static const double _bubblePadding = 16.0;

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
      const Radius.circular(12.0),
    );
    final isEven = (_message?.id ?? 0).isEven;
    canvas.drawRRect(
      bubbleRect,
      Paint()
        ..color = isEven ? const Color(0xFFE3F2FD) : const Color(0xFFF5F5F5),
    );
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
// Helpers
// ---------------------------------------------------------------------------

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

Widget _buildLV(List<IChatMessage> messages, ScrollController sc) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 800,
          child: BenchmarkListViewWrapper(
            child: ListViewChatCustomPaint(
              messages: messages,
              scrollController: sc,
            ),
          ),
        ),
      ),
    );

RenderChatScrollView _findCSVRender(WidgetTester tester) =>
    tester.renderObject<RenderChatScrollView>(find.byType(ChatScrollView));

RenderBenchmarkListViewWrapper _findLVRender(WidgetTester tester) =>
    tester.renderObject<RenderBenchmarkListViewWrapper>(
      find.byType(BenchmarkListViewWrapper),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Comparative: CSV vs LV', () {
    for (final count in [kSmall, kMedium, kLarge]) {
      testWidgets('layout comparison — $count messages', (tester) async {
        const warmup = 10;
        const measured = 100;

        final messages = generateMessages(count);

        // --- ChatScrollView ---
        final csvController = BenchmarkChatController(messages);
        await tester.pumpWidget(_buildCSV(csvController));
        await tester.pumpAndSettle();
        final csvRender = _findCSVRender(tester);

        for (var i = 0; i < warmup; i++) {
          tester.view.physicalSize = Size(401.0 + i % 2, 800.0);
          tester.view.devicePixelRatio = 1.0;
          await tester.pump();
        }
        tester.view.physicalSize = const Size(400.0, 800.0);
        tester.view.devicePixelRatio = 1.0;
        await tester.pump();

        final csvLayoutSamples = <int>[];
        for (var i = 0; i < measured; i++) {
          tester.view.physicalSize = Size(400.0 + (i.isEven ? 0 : 1), 800.0);
          tester.view.devicePixelRatio = 1.0;
          await tester.pump();
          csvLayoutSamples.add(
            csvRender.debugLastLayoutDuration.inMicroseconds,
          );
        }
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        csvController.dispose();
        await tester.pumpWidget(const SizedBox.shrink());

        // --- ListView ---
        final sc = ScrollController();
        await tester.pumpWidget(_buildLV(messages, sc));
        await tester.pumpAndSettle();
        final lvRender = _findLVRender(tester);

        for (var i = 0; i < warmup; i++) {
          tester.view.physicalSize = Size(401.0 + i % 2, 800.0);
          tester.view.devicePixelRatio = 1.0;
          await tester.pump();
        }
        tester.view.physicalSize = const Size(400.0, 800.0);
        tester.view.devicePixelRatio = 1.0;
        await tester.pump();

        final lvLayoutSamples = <int>[];
        for (var i = 0; i < measured; i++) {
          tester.view.physicalSize = Size(400.0 + (i.isEven ? 0 : 1), 800.0);
          tester.view.devicePixelRatio = 1.0;
          await tester.pump();
          lvLayoutSamples.add(lvRender.debugLastLayoutDuration.inMicroseconds);
        }
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        sc.dispose();

        final csvMetrics = BenchmarkMetrics(
          'CSV layout ($count)',
          csvLayoutSamples,
        );
        final lvMetrics = BenchmarkMetrics(
          'LV layout ($count)',
          lvLayoutSamples,
        );

        // ignore: avoid_print
        print('\n=== Layout Comparison ($count messages) ===');
        // ignore: avoid_print
        print('CSV: $csvMetrics');
        // ignore: avoid_print
        print('LV:  $lvMetrics');
        // ignore: avoid_print
        print(
          'Ratio (CSV/LV): '
          '${(csvMetrics.meanUs / lvMetrics.meanUs).toStringAsFixed(3)}x',
        );
      });

      testWidgets('scroll-only paint comparison — $count messages', (
        tester,
      ) async {
        const warmup = 10;
        const measured = 300;

        final messages = generateMessages(count);

        // --- ChatScrollView ---
        final csvController = BenchmarkChatController(messages);
        await tester.pumpWidget(_buildCSV(csvController));
        await tester.pumpAndSettle();
        final csvRender = _findCSVRender(tester);

        for (var i = 0; i < warmup; i++) {
          csvController.anchorPixelOffset -= 5.0;
          await tester.pump();
        }

        final csvSamples = <int>[];
        for (var i = 0; i < measured; i++) {
          csvController.anchorPixelOffset -= 3.0;
          await tester.pump();
          csvSamples.add(csvRender.debugLastPaintDuration.inMicroseconds);
        }
        csvController.dispose();
        await tester.pumpWidget(const SizedBox.shrink());

        // --- ListView ---
        final sc = ScrollController();
        await tester.pumpWidget(_buildLV(messages, sc));
        await tester.pumpAndSettle();
        final lvRender = _findLVRender(tester);

        for (var i = 0; i < warmup; i++) {
          sc.jumpTo(sc.offset + 5.0);
          await tester.pump();
        }

        final lvSamples = <int>[];
        for (var i = 0; i < measured; i++) {
          sc.jumpTo(sc.offset + 3.0);
          await tester.pump();
          lvSamples.add(lvRender.debugLastPaintDuration.inMicroseconds);
        }
        sc.dispose();

        final csvMetrics = BenchmarkMetrics('CSV paint ($count)', csvSamples);
        final lvMetrics = BenchmarkMetrics('LV paint ($count)', lvSamples);

        // ignore: avoid_print
        print('\n=== Scroll-only Paint Comparison ($count messages) ===');
        // ignore: avoid_print
        print('CSV: $csvMetrics');
        // ignore: avoid_print
        print('LV:  $lvMetrics');
        // ignore: avoid_print
        print(
          'Ratio (CSV/LV): '
          '${(csvMetrics.meanUs / lvMetrics.meanUs).toStringAsFixed(3)}x',
        );
      });

      testWidgets('fling comparison — $count messages', (tester) async {
        final messages = generateMessages(count);

        // Measure total frame time (Stopwatch around pump) for fair comparison.
        // Internal instrumentation misses ListView's internal Viewport repaints.

        // --- ChatScrollView ---
        final csvController = BenchmarkChatController(messages);
        await tester.pumpWidget(_buildCSV(csvController));
        await tester.pumpAndSettle();

        csvController.jumpTo(count ~/ 2);
        await tester.pumpAndSettle();

        final csvSamples = <int>[];
        await tester.fling(
          find.byType(ChatScrollView),
          const Offset(0, -500),
          2000.0,
        );
        for (var i = 0; i < 300; i++) {
          final sw = Stopwatch()..start();
          await tester.pump(const Duration(milliseconds: 16));
          csvSamples.add(sw.elapsed.inMicroseconds);
        }
        csvController.dispose();
        await tester.pumpWidget(const SizedBox.shrink());

        // --- ListView ---
        final sc = ScrollController();
        await tester.pumpWidget(_buildLV(messages, sc));
        await tester.pumpAndSettle();

        sc.jumpTo(sc.position.maxScrollExtent / 2);
        await tester.pumpAndSettle();

        final lvSamples = <int>[];
        await tester.fling(
          find.byType(ListView),
          const Offset(0, -500),
          2000.0,
        );
        for (var i = 0; i < 300; i++) {
          final sw = Stopwatch()..start();
          await tester.pump(const Duration(milliseconds: 16));
          lvSamples.add(sw.elapsed.inMicroseconds);
        }
        sc.dispose();

        final csvMetrics = BenchmarkMetrics('CSV fling ($count)', csvSamples);
        final lvMetrics = BenchmarkMetrics('LV fling ($count)', lvSamples);

        // ignore: avoid_print
        print(
          '\n=== Fling Comparison — total frame time ($count messages) ===',
        );
        // ignore: avoid_print
        print('CSV: $csvMetrics');
        // ignore: avoid_print
        print('LV:  $lvMetrics');
        // ignore: avoid_print
        print(
          'Ratio (CSV/LV): '
          '${(csvMetrics.meanUs / lvMetrics.meanUs).toStringAsFixed(3)}x',
        );
      });
    }

    testWidgets('memory comparison', (tester) async {
      for (final count in [kSmall, kMedium, kLarge]) {
        final messages = generateMessages(count);

        // --- CSV ---
        final csvController = BenchmarkChatController(messages);
        await tester.pumpWidget(_buildCSV(csvController));
        await tester.pumpAndSettle();
        final csvRender = _findCSVRender(tester);

        final csvAttached = csvRender.debugAttachedRenderCount;
        final csvTotal = csvRender.debugTotalRenderCount;
        final csvChunks = csvRender.debugChunkCount;
        csvController.dispose();
        await tester.pumpWidget(const SizedBox.shrink());

        // --- LV ---
        final sc = ScrollController();
        await tester.pumpWidget(_buildLV(messages, sc));
        await tester.pumpAndSettle();

        var lvElements = 0;
        var lvRenderObjects = 0;
        void visit(Element element) {
          lvRenderObjects++;
          element.visitChildren(visit);
        }

        lvElements = tester.elementList(find.byType(CustomPaintBubble)).length;
        visit(tester.element(find.byType(MaterialApp)));
        sc.dispose();
        await tester.pumpWidget(const SizedBox.shrink());

        // ignore: avoid_print
        print('\n=== Memory Comparison ($count messages) ===');
        // ignore: avoid_print
        print('CSV: attached=$csvAttached total=$csvTotal chunks=$csvChunks');
        // ignore: avoid_print
        print(
          'LV:  visible_elements=$lvElements '
          'total_render_objects=$lvRenderObjects',
        );
      }
    });
  });
}

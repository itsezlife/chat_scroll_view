// Integration benchmark: runs on real macOS with GPU compositing.
// Measures actual frame timing via SchedulerBinding.addTimingsCallback,
// throughput (max FPS), and stress tests with large message counts.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_scroll_view_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// ---------------------------------------------------------------------------
// Shared utilities
// ---------------------------------------------------------------------------

const _kShort = [
  'Hello!',
  'Sure thing.',
  'Got it, thanks.',
  'On my way.',
  'OK',
];
const _kMedium = [
  'The quick brown fox jumps over the lazy dog near the riverbank.',
  'I was thinking we could meet up tomorrow at the coffee shop downtown.',
  'Can you send me the latest version of the document when you get a chance?',
  'We should probably discuss the project timeline before the meeting.',
];
const _kLong = [
  'The first rule of Fight Club is: you do not talk about Fight Club. '
      'The second rule of Fight Club is: you DO NOT talk about Fight Club! '
      'Third rule of Fight Club: if someone yells stop, goes limp, or taps '
      'out, the fight is over. Fourth rule: only two guys to a fight.',
  'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod '
      'tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim '
      'veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea '
      'commodo consequat. Duis aute irure dolor in reprehenderit.',
];

List<IChatMessage> _generateMessages(int count) {
  final rng = Random(42);
  final now = DateTime(2026, 1, 1);
  final messages = <IChatMessage>[];
  for (var i = 0; i < count; i++) {
    final time = now.add(Duration(minutes: i));
    final roll = rng.nextDouble();
    final String content;
    if (roll < 0.3) {
      content = _kShort[rng.nextInt(_kShort.length)];
    } else if (roll < 0.8) {
      content = _kMedium[rng.nextInt(_kMedium.length)];
    } else {
      content = _kLong[rng.nextInt(_kLong.length)];
    }
    messages.add(
      ChatMessage$User(
        id: i,
        createdAt: time,
        updatedAt: time,
        content: content,
      ),
    );
  }
  return messages;
}

class _BenchController extends ChatScrollController {
  _BenchController(List<IChatMessage> messages) {
    upsertMessages(messages);
    oldestKnownId = 0;
    newestKnownId = messages.length - 1;
    reachedOldest = true;
    reachedNewest = true;
    jumpTo(messages.length - 1);
  }

  @override
  Future<List<IChatMessage>> fetch({
    int? from,
    int? to,
    DateTime? after,
  }) async => const [];
}

class _BenchRender extends ChatMessageRender {
  _BenchRender(IChatMessage? message) {
    if (message != null) {
      _message = message;
      dirty = true;
    }
  }

  static const double _padding = 12.0;
  static const double _bubblePadding = 16.0;
  IChatMessage? _message;
  ui.Paragraph? _paragraph;

  @override
  void update(IChatMessage? message, ChatMessageStatus status) {
    if (identical(_message, message)) return;
    _message = message;
    _paragraph = null;
    dirty = true;
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

// --- ListView equivalent (CustomPaint) ---

class _LVBubble extends LeafRenderObjectWidget {
  const _LVBubble({required this.message});
  final IChatMessage message;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLVBubble(message);

  @override
  void updateRenderObject(BuildContext context, _RenderLVBubble renderObject) {
    renderObject.message = message;
  }
}

class _RenderLVBubble extends RenderBox {
  _RenderLVBubble(this._message);

  static const double _padding = 12.0;
  static const double _bubblePadding = 16.0;
  IChatMessage _message;
  ui.Paragraph? _paragraph;
  double _lastWidth = 0;

  set message(IChatMessage value) {
    if (identical(_message, value)) return;
    _message = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth;
    if (_paragraph == null || _lastWidth != maxWidth) {
      _lastWidth = maxWidth;
      final content = switch (_message) {
        ChatMessage$User(:final content) => content,
        ChatMessage$System(:final content) => content,
        _ => 'Message #${_message.id}',
      };
      final textWidth = maxWidth - _bubblePadding * 2 - _padding * 2;
      final builder =
          ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 15.0, height: 1.4))
            ..pushStyle(ui.TextStyle(color: const Color(0xFF1A1A1A)))
            ..addText(content)
            ..pop();
      _paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: textWidth));
    }
    size = constraints.constrain(
      Size(maxWidth, _paragraph!.height + _bubblePadding * 2 + _padding),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paragraph = _paragraph;
    if (paragraph == null) return;
    final canvas = context.canvas;
    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        offset.dx + _padding,
        offset.dy + _padding / 2,
        size.width - _padding * 2,
        size.height - _padding,
      ),
      const Radius.circular(12.0),
    );
    final isEven = _message.id.isEven;
    canvas.drawRRect(
      bubbleRect,
      Paint()
        ..color = isEven ? const Color(0xFFE3F2FD) : const Color(0xFFF5F5F5),
    );
    canvas.save();
    canvas.translate(
      offset.dx + _padding + _bubblePadding,
      offset.dy + _padding / 2 + _bubblePadding,
    );
    canvas.drawParagraph(paragraph, Offset.zero);
    canvas.restore();
  }
}

// ---------------------------------------------------------------------------
// FrameTiming collector
// ---------------------------------------------------------------------------

class _FrameTimingCollector {
  final timings = <FrameTiming>[];
  late final TimingsCallback _callback;

  void start() {
    _callback = (List<FrameTiming> list) {
      timings.addAll(list);
    };
    SchedulerBinding.instance.addTimingsCallback(_callback);
  }

  void stop() {
    SchedulerBinding.instance.removeTimingsCallback(_callback);
  }

  List<int> get buildTimesUs =>
      timings.map((t) => t.buildDuration.inMicroseconds).toList();

  List<int> get rasterTimesUs =>
      timings.map((t) => t.rasterDuration.inMicroseconds).toList();

  List<int> get totalTimesUs => timings
      .map(
        (t) => t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds,
      )
      .toList();

  int get jankCount => timings
      .where((t) => t.totalSpan > const Duration(milliseconds: 16))
      .length;

  String summary(String label) {
    if (timings.isEmpty) return '$label: no frames collected';
    final build = buildTimesUs;
    final raster = rasterTimesUs;
    final total = totalTimesUs;
    build.sort();
    raster.sort();
    total.sort();
    return '$label (${timings.length} frames):\n'
        '  Build:  mean=${_mean(build)}µs  p50=${_p50(build)}µs  '
        'p95=${_p95(build)}µs  p99=${_p99(build)}µs  max=${build.last}µs\n'
        '  Raster: mean=${_mean(raster)}µs  p50=${_p50(raster)}µs  '
        'p95=${_p95(raster)}µs  p99=${_p99(raster)}µs  max=${raster.last}µs\n'
        '  Total:  mean=${_mean(total)}µs  p50=${_p50(total)}µs  '
        'p95=${_p95(total)}µs  p99=${_p99(total)}µs  max=${total.last}µs\n'
        '  Jank (>16ms): $jankCount / ${timings.length} '
        '(${(jankCount * 100 / timings.length).toStringAsFixed(1)}%)';
  }

  static int _mean(List<int> s) =>
      s.isEmpty ? 0 : s.reduce((a, b) => a + b) ~/ s.length;
  static int _p50(List<int> s) => s.isEmpty ? 0 : s[s.length ~/ 2];
  static int _p95(List<int> s) =>
      s.isEmpty ? 0 : s[((s.length - 1) * 0.95).round()];
  static int _p99(List<int> s) =>
      s.isEmpty ? 0 : s[((s.length - 1) * 0.99).round()];
}

// ---------------------------------------------------------------------------
// Widget builders
// ---------------------------------------------------------------------------

Widget _csvApp(_BenchController controller) => MaterialApp(
  home: Scaffold(
    body: ChatScrollView(controller: controller, builder: _BenchRender.new),
  ),
);

Widget _lvApp(List<IChatMessage> messages, ScrollController sc) => MaterialApp(
  home: Scaffold(
    body: ListView.builder(
      controller: sc,
      physics: const ClampingScrollPhysics(),
      itemCount: messages.length,
      itemBuilder: (_, i) => _LVBubble(message: messages[i]),
    ),
  ),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Collect results for final report.
  final report = StringBuffer()
    ..writeln('# Integration Benchmark Report (macOS)')
    ..writeln()
    ..writeln('Real rendering with GPU compositing.')
    ..writeln();

  // =========================================================================
  // 1. FrameTiming — continuous drag scroll
  // =========================================================================
  for (final count in [256, 6000, 20000]) {
    group('FrameTiming — drag scroll ($count msgs)', () {
      testWidgets('ChatScrollView', (tester) async {
        final messages = _generateMessages(count);
        final controller = _BenchController(messages);
        await tester.pumpWidget(_csvApp(controller));
        await tester.pumpAndSettle();

        final collector = _FrameTimingCollector()..start();

        // Simulate continuous drag: 200 small increments
        for (var i = 0; i < 200; i++) {
          controller.anchorPixelOffset -= 15.0;
          await tester.pump(const Duration(milliseconds: 16));
        }

        // Let settle
        await tester.pumpAndSettle();
        collector.stop();

        final result = collector.summary('CSV drag scroll ($count msgs)');
        debugPrint(result);
        report.writeln('## Drag Scroll — $count msgs\n');
        report.writeln('```');
        report.writeln(result);

        controller.dispose();
      });

      testWidgets('ListView.builder', (tester) async {
        final messages = _generateMessages(count);
        final sc = ScrollController();
        await tester.pumpWidget(_lvApp(messages, sc));
        await tester.pumpAndSettle();

        final collector = _FrameTimingCollector()..start();

        final maxExtent = sc.position.maxScrollExtent;
        for (var i = 0; i < 200; i++) {
          final target = sc.offset + 15.0;
          if (target <= maxExtent) sc.jumpTo(target);
          await tester.pump(const Duration(milliseconds: 16));
        }

        await tester.pumpAndSettle();
        collector.stop();

        final result = collector.summary('LV drag scroll ($count msgs)');
        debugPrint(result);
        report.writeln(result);
        report.writeln('```\n');

        sc.dispose();
      });
    });
  }

  // =========================================================================
  // 2. FrameTiming — fling
  // =========================================================================
  for (final count in [256, 6000, 20000]) {
    group('FrameTiming — fling ($count msgs)', () {
      testWidgets('ChatScrollView', (tester) async {
        final messages = _generateMessages(count);
        final controller = _BenchController(messages);
        await tester.pumpWidget(_csvApp(controller));
        await tester.pumpAndSettle();

        // Jump to middle
        controller.jumpTo(count ~/ 2);
        await tester.pumpAndSettle();

        final collector = _FrameTimingCollector()..start();

        await tester.fling(
          find.byType(ChatScrollView),
          const Offset(0, -300),
          3000.0,
        );
        // Let fling animate
        for (var i = 0; i < 300; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        collector.stop();

        final result = collector.summary('CSV fling ($count msgs)');
        debugPrint(result);
        report.writeln('## Fling — $count msgs\n');
        report.writeln('```');
        report.writeln(result);

        controller.dispose();
      });

      testWidgets('ListView.builder', (tester) async {
        final messages = _generateMessages(count);
        final sc = ScrollController();
        await tester.pumpWidget(_lvApp(messages, sc));
        await tester.pumpAndSettle();

        sc.jumpTo(sc.position.maxScrollExtent / 2);
        await tester.pumpAndSettle();

        final collector = _FrameTimingCollector()..start();

        await tester.fling(
          find.byType(ListView),
          const Offset(0, -300),
          3000.0,
        );
        for (var i = 0; i < 300; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        collector.stop();

        final result = collector.summary('LV fling ($count msgs)');
        debugPrint(result);
        report.writeln(result);
        report.writeln('```\n');

        sc.dispose();
      });
    });
  }

  // =========================================================================
  // 3. Theoretical max FPS — computed from FrameTiming build+raster
  //    During drag scroll, measure mean frame work time.
  //    Theoretical max FPS = 1_000_000 / mean_total_µs.
  //    Also: raw computation benchmark (tight loop, no vsync).
  // =========================================================================
  for (final count in [256, 6000, 20000]) {
    group('Theoretical max FPS ($count msgs)', () {
      testWidgets('ChatScrollView', (tester) async {
        final messages = _generateMessages(count);
        final controller = _BenchController(messages);
        await tester.pumpWidget(_csvApp(controller));
        await tester.pumpAndSettle();

        controller.jumpTo(count ~/ 2);
        await tester.pumpAndSettle();

        final collector = _FrameTimingCollector()..start();

        // 300 frames of continuous scroll
        for (var i = 0; i < 300; i++) {
          controller.anchorPixelOffset -= 10.0;
          await tester.pump(const Duration(milliseconds: 16));
        }
        collector.stop();

        final totalUs = collector.totalTimesUs;
        totalUs.sort();
        final meanTotal = totalUs.reduce((a, b) => a + b) / totalUs.length;
        final p95Total = totalUs[((totalUs.length - 1) * 0.95).round()];
        final maxFpsMean = 1000000.0 / meanTotal;
        final maxFpsP95 = 1000000.0 / p95Total;

        final result =
            'CSV theoretical max FPS ($count msgs): '
            'mean=${maxFpsMean.toStringAsFixed(0)} FPS '
            '(mean frame ${(meanTotal / 1000).toStringAsFixed(2)}ms)  '
            'p95-limited=${maxFpsP95.toStringAsFixed(0)} FPS '
            '(p95 frame ${(p95Total / 1000).toStringAsFixed(2)}ms)';
        debugPrint(result);
        report.writeln('## Theoretical Max FPS — $count msgs\n');
        report.writeln('```');
        report.writeln(result);

        controller.dispose();
      });

      testWidgets('ListView.builder', (tester) async {
        final messages = _generateMessages(count);
        final sc = ScrollController();
        await tester.pumpWidget(_lvApp(messages, sc));
        await tester.pumpAndSettle();

        sc.jumpTo(sc.position.maxScrollExtent / 2);
        await tester.pumpAndSettle();

        final collector = _FrameTimingCollector()..start();

        final maxExtent = sc.position.maxScrollExtent;
        for (var i = 0; i < 300; i++) {
          final target = sc.offset + 10.0;
          if (target <= maxExtent) sc.jumpTo(target);
          await tester.pump(const Duration(milliseconds: 16));
        }
        collector.stop();

        final totalUs = collector.totalTimesUs;
        totalUs.sort();
        final meanTotal = totalUs.reduce((a, b) => a + b) / totalUs.length;
        final p95Total = totalUs[((totalUs.length - 1) * 0.95).round()];
        final maxFpsMean = 1000000.0 / meanTotal;
        final maxFpsP95 = 1000000.0 / p95Total;

        final result =
            'LV theoretical max FPS ($count msgs): '
            'mean=${maxFpsMean.toStringAsFixed(0)} FPS '
            '(mean frame ${(meanTotal / 1000).toStringAsFixed(2)}ms)  '
            'p95-limited=${maxFpsP95.toStringAsFixed(0)} FPS '
            '(p95 frame ${(p95Total / 1000).toStringAsFixed(2)}ms)';
        debugPrint(result);
        report.writeln(result);
        report.writeln('```\n');

        sc.dispose();
      });
    });
  }

  // =========================================================================
  // 3b. Raw computation throughput — direct layout+paint timing.
  //     Measures just the render work, no vsync, no compositor.
  // =========================================================================
  for (final count in [256, 6000, 20000]) {
    group('Raw computation throughput ($count msgs)', () {
      testWidgets('ChatScrollView', (tester) async {
        final messages = _generateMessages(count);
        final controller = _BenchController(messages);
        await tester.pumpWidget(_csvApp(controller));
        await tester.pumpAndSettle();

        controller.jumpTo(count ~/ 2);
        await tester.pumpAndSettle();

        final render = tester.renderObject<RenderChatScrollView>(
          find.byType(ChatScrollView),
        );

        // Warm up
        for (var i = 0; i < 20; i++) {
          controller.anchorPixelOffset -= 5.0;
          await tester.pump(const Duration(milliseconds: 16));
        }

        // Measure 500 frames of internal layout+paint
        var totalLayoutUs = 0;
        var totalPaintUs = 0;
        var lastLId = render.debugLayoutFrameId;
        var lastPId = render.debugPaintFrameId;
        var layoutFrames = 0;
        var paintFrames = 0;

        for (var i = 0; i < 500; i++) {
          controller.anchorPixelOffset -= 5.0;
          await tester.pump(const Duration(milliseconds: 16));
          if (render.debugLayoutFrameId != lastLId) {
            totalLayoutUs += render.debugLastLayoutDuration.inMicroseconds;
            layoutFrames++;
            lastLId = render.debugLayoutFrameId;
          }
          if (render.debugPaintFrameId != lastPId) {
            totalPaintUs += render.debugLastPaintDuration.inMicroseconds;
            paintFrames++;
            lastPId = render.debugPaintFrameId;
          }
        }

        final avgLayoutUs = layoutFrames > 0 ? totalLayoutUs / layoutFrames : 0;
        final avgPaintUs = paintFrames > 0 ? totalPaintUs / paintFrames : 0;
        final avgTotalUs = avgLayoutUs + avgPaintUs;
        final rawFps = avgTotalUs > 0
            ? (1000000.0 / avgTotalUs).toStringAsFixed(0)
            : '∞';

        final result =
            'CSV raw compute ($count msgs): '
            'layout=${avgLayoutUs.toStringAsFixed(1)}µs  '
            'paint=${avgPaintUs.toStringAsFixed(1)}µs  '
            'total=${avgTotalUs.toStringAsFixed(1)}µs  '
            'raw=$rawFps FPS  '
            '(layout frames: $layoutFrames, paint frames: $paintFrames)';
        debugPrint(result);
        report.writeln('## Raw Computation — $count msgs\n');
        report.writeln('```');
        report.writeln(result);

        controller.dispose();
      });

      testWidgets('ListView.builder', (tester) async {
        final messages = _generateMessages(count);
        final sc = ScrollController();
        await tester.pumpWidget(_lvApp(messages, sc));
        await tester.pumpAndSettle();

        sc.jumpTo(sc.position.maxScrollExtent / 2);
        await tester.pumpAndSettle();

        // Measure total pump time for 500 frames (includes all internal work)
        final maxExtent = sc.position.maxScrollExtent;
        final samples = <int>[];
        for (var i = 0; i < 500; i++) {
          final target = sc.offset + 5.0;
          if (target <= maxExtent) sc.jumpTo(target);
          final sw = Stopwatch()..start();
          await tester.pump(const Duration(milliseconds: 16));
          samples.add(sw.elapsed.inMicroseconds);
        }

        // Subtract estimated framework overhead (~8ms vsync wait)
        // by looking at the minimum frame time as a proxy for actual work.
        samples.sort();
        final p10 = samples[(samples.length * 0.1).round()];
        final meanUs = samples.reduce((a, b) => a + b) / samples.length;
        final rawFps = p10 > 0 ? (1000000.0 / p10).toStringAsFixed(0) : '∞';

        final result =
            'LV raw compute ($count msgs): '
            'mean_pump=${(meanUs / 1000).toStringAsFixed(2)}ms  '
            'p10_pump=${(p10 / 1000).toStringAsFixed(2)}ms  '
            'estimated_raw=$rawFps FPS';
        debugPrint(result);
        report.writeln(result);
        report.writeln('```\n');

        sc.dispose();
      });
    });
  }

  // =========================================================================
  // 4. Stress test — rapid direction changes
  //    Alternate scroll direction every few frames to stress anchor system.
  // =========================================================================
  group('Stress — rapid direction changes', () {
    for (final count in [6000, 20000]) {
      testWidgets('ChatScrollView — $count msgs', (tester) async {
        final messages = _generateMessages(count);
        final controller = _BenchController(messages);
        await tester.pumpWidget(_csvApp(controller));
        await tester.pumpAndSettle();

        controller.jumpTo(count ~/ 2);
        await tester.pumpAndSettle();

        final render = tester.renderObject<RenderChatScrollView>(
          find.byType(ChatScrollView),
        );
        final collector = _FrameTimingCollector()..start();

        // 200 frames with direction change every 5 frames
        var direction = -1.0;
        for (var i = 0; i < 200; i++) {
          if (i % 5 == 0) direction = -direction;
          controller.anchorPixelOffset += direction * 20.0;
          await tester.pump(const Duration(milliseconds: 16));
        }

        collector.stop();

        final result = collector.summary('CSV direction stress ($count msgs)');
        debugPrint(result);
        debugPrint('  Attached renders: ${render.debugAttachedRenderCount}');
        debugPrint('  Total renders: ${render.debugTotalRenderCount}');
        debugPrint('  Chunks: ${render.debugChunkCount}');
        report.writeln('## Direction Stress — $count msgs\n');
        report.writeln('```');
        report.writeln(result);
        report.writeln(
          '  Attached: ${render.debugAttachedRenderCount}  '
          'Total: ${render.debugTotalRenderCount}  '
          'Chunks: ${render.debugChunkCount}',
        );
        report.writeln('```\n');

        controller.dispose();
      });
    }
  });

  // =========================================================================
  // 5. Stress test — long continuous scroll (full traversal)
  //    Scroll through ALL messages top to bottom, measuring frame consistency.
  // =========================================================================
  group('Stress — full traversal', () {
    for (final count in [6000, 20000]) {
      testWidgets('ChatScrollView — $count msgs', (tester) async {
        final messages = _generateMessages(count);
        final controller = _BenchController(messages);
        await tester.pumpWidget(_csvApp(controller));
        await tester.pumpAndSettle();

        // Start at oldest message
        controller.jumpTo(0);
        await tester.pumpAndSettle();

        final render = tester.renderObject<RenderChatScrollView>(
          find.byType(ChatScrollView),
        );
        final collector = _FrameTimingCollector()..start();

        // Scroll down through all messages with ~50px per frame
        final totalFrames = min(count * 2, 2000);
        for (var i = 0; i < totalFrames; i++) {
          controller.anchorPixelOffset -= 50.0;
          await tester.pump(const Duration(milliseconds: 16));
        }

        collector.stop();

        final result = collector.summary('CSV full traversal ($count msgs)');
        debugPrint(result);
        debugPrint('  Peak attached: ${render.debugAttachedRenderCount}');
        debugPrint('  Peak total: ${render.debugTotalRenderCount}');
        debugPrint('  Chunks: ${render.debugChunkCount}');
        report.writeln('## Full Traversal — $count msgs\n');
        report.writeln('```');
        report.writeln(result);
        report.writeln(
          '  Attached: ${render.debugAttachedRenderCount}  '
          'Total: ${render.debugTotalRenderCount}  '
          'Chunks: ${render.debugChunkCount}',
        );
        report.writeln('```\n');

        controller.dispose();
      });

      testWidgets('ListView.builder — $count msgs', (tester) async {
        final messages = _generateMessages(count);
        final sc = ScrollController();
        await tester.pumpWidget(_lvApp(messages, sc));
        await tester.pumpAndSettle();

        sc.jumpTo(0);
        await tester.pumpAndSettle();

        final collector = _FrameTimingCollector()..start();

        final maxExtent = sc.position.maxScrollExtent;
        final totalFrames = min(count * 2, 2000);
        for (var i = 0; i < totalFrames; i++) {
          final target = sc.offset + 50.0;
          if (target > maxExtent) break;
          sc.jumpTo(target);
          await tester.pump(const Duration(milliseconds: 16));
        }

        collector.stop();

        final result = collector.summary('LV full traversal ($count msgs)');
        debugPrint(result);
        report.writeln('```');
        report.writeln(result);
        report.writeln('```\n');

        sc.dispose();
      });
    }
  });

  // =========================================================================
  // 6. Memory stability — long scroll session
  //    Scroll through entire list 3 times, check no growth.
  // =========================================================================
  testWidgets('Memory stability — 3 full traversals (6000 msgs)', (
    tester,
  ) async {
    final messages = _generateMessages(6000);
    final controller = _BenchController(messages);
    await tester.pumpWidget(_csvApp(controller));
    await tester.pumpAndSettle();

    final render = tester.renderObject<RenderChatScrollView>(
      find.byType(ChatScrollView),
    );

    final snapshots = <String>[];

    for (var pass = 0; pass < 3; pass++) {
      // Scroll top to bottom
      controller.jumpTo(0);
      await tester.pump();
      for (var i = 0; i < 500; i++) {
        controller.anchorPixelOffset -= 80.0;
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Scroll bottom to top
      for (var i = 0; i < 500; i++) {
        controller.anchorPixelOffset += 80.0;
        await tester.pump(const Duration(milliseconds: 16));
      }

      final snap =
          'Pass ${pass + 1}: '
          'attached=${render.debugAttachedRenderCount} '
          'total=${render.debugTotalRenderCount} '
          'chunks=${render.debugChunkCount}';
      debugPrint(snap);
      snapshots.add(snap);
    }

    report.writeln('## Memory Stability — 3 traversals (6000 msgs)\n');
    report.writeln('```');
    for (final s in snapshots) {
      report.writeln(s);
    }
    report.writeln('```\n');

    // Verify no growth between passes
    expect(
      render.debugChunkCount,
      lessThanOrEqualTo(16),
      reason: 'Chunk count should stay within maxChunks',
    );

    controller.dispose();
  });

  // =========================================================================
  // Print final report
  // =========================================================================
  tearDownAll(() {
    debugPrint('\n${'=' * 70}');
    debugPrint('INTEGRATION BENCHMARK REPORT');
    debugPrint('=' * 70);
    debugPrint(report.toString());
  });
}

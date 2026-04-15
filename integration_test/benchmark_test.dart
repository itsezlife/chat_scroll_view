// Integration benchmark: runs on real macOS with GPU compositing.
//
// Debug:   flutter test integration_test/benchmark_test.dart -d macos
// Profile: flutter drive --driver=test_driver/integration_test.dart \
//            --target=integration_test/benchmark_test.dart -d macos --profile
//
// Baseline results (2026-04-15, macOS, M-series, profile mode):
//
//   Drag scroll (200 frames, 15px/frame):
//     256 msgs:   Build mean=356µs  Raster mean=961µs  Jank 0.5%
//     6000 msgs:  Build mean=334µs  Raster mean=818µs  Jank 0.0%
//     20000 msgs: Build mean=338µs  Raster mean=857µs  Jank 0.5%
//
//   Fling (300 frames):
//     256 msgs:   Build mean=235µs  Raster mean=878µs  Jank 0.0%
//     6000 msgs:  Build mean=210µs  Raster mean=832µs  Jank 0.0%
//     20000 msgs: Build mean=216µs  Raster mean=871µs  Jank 0.0%
//
//   Theoretical max FPS (profile):
//     256 msgs:   815 FPS (p95: 545 FPS)
//     6000 msgs:  882 FPS (p95: 605 FPS)
//     20000 msgs: 940 FPS (p95: 624 FPS)
//
//   Memory stability (6000 msgs, 3 traversals):
//     Chunks stay ≤16 across all passes (no growth)

import 'dart:math';
import 'dart:ui' as ui;

import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_message_render.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_view.dart';
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
  return [
    for (var i = 0; i < count; i++)
      ChatMessage$User(
        id: i,
        createdAt: now.add(Duration(minutes: i)),
        updatedAt: now.add(Duration(minutes: i)),
        content: () {
          final roll = rng.nextDouble();
          if (roll < 0.3) return _kShort[rng.nextInt(_kShort.length)];
          if (roll < 0.8) return _kMedium[rng.nextInt(_kMedium.length)];
          return _kLong[rng.nextInt(_kLong.length)];
        }(),
      ),
  ];
}

// ---------------------------------------------------------------------------
// Data source + render
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

class _BenchRender extends ChatMessageRender {
  _BenchRender(IChatMessage? message) {
    if (message is IChatMessage) {
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
    if (message is! IChatMessage) {
      _message = null;
      _paragraph = null;
      dirty = true;
      return;
    }
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

// ---------------------------------------------------------------------------
// FrameTiming collector
// ---------------------------------------------------------------------------

class _FrameTimingCollector {
  final timings = <FrameTiming>[];
  late final TimingsCallback _callback;

  void start() {
    _callback = (List<FrameTiming> list) => timings.addAll(list);
    SchedulerBinding.instance.addTimingsCallback(_callback);
  }

  void stop() => SchedulerBinding.instance.removeTimingsCallback(_callback);

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
    final build = buildTimesUs..sort();
    final raster = rasterTimesUs..sort();
    final total = totalTimesUs..sort();
    return '$label (${timings.length} frames):\n'
        '  Build:  mean=${_mean(build)}µs  p50=${_p50(build)}µs  p95=${_p95(build)}µs  p99=${_p99(build)}µs  max=${build.last}µs\n'
        '  Raster: mean=${_mean(raster)}µs  p50=${_p50(raster)}µs  p95=${_p95(raster)}µs  p99=${_p99(raster)}µs  max=${raster.last}µs\n'
        '  Total:  mean=${_mean(total)}µs  p50=${_p50(total)}µs  p95=${_p95(total)}µs  p99=${_p99(total)}µs  max=${total.last}µs\n'
        '  Jank (>16ms): $jankCount / ${timings.length} (${(jankCount * 100 / timings.length).toStringAsFixed(1)}%)';
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
// Helpers
// ---------------------------------------------------------------------------

({_BenchDataSource ds, ChatScrollController ctrl}) _setup(int count) {
  final messages = _generateMessages(count);
  final ds = _BenchDataSource(messages);
  final ctrl = ChatScrollController()
    ..oldestKnownId = 0
    ..newestKnownId = count - 1
    ..reachedOldest = true
    ..reachedNewest = true;
  ctrl.jumpTo(count - 1);
  return (ds: ds, ctrl: ctrl);
}

Widget _csvApp(_BenchDataSource ds, ChatScrollController ctrl) => MaterialApp(
  home: Scaffold(
    body: ChatScrollView(
      dataSource: ds,
      controller: ctrl,
      builder: _BenchRender.new,
    ),
  ),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 1. Drag scroll
  for (final count in [256, 6000, 20000]) {
    testWidgets('drag scroll — $count msgs', (tester) async {
      final (:ds, :ctrl) = _setup(count);
      await tester.pumpWidget(_csvApp(ds, ctrl));
      await tester.pumpAndSettle();

      final collector = _FrameTimingCollector()..start();
      for (var i = 0; i < 200; i++) {
        ctrl.applyScrollDelta(15.0);
        tester
            .renderObject<RenderChatScrollView>(find.byType(ChatScrollView))
            .markNeedsLayout();
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      collector.stop();

      debugPrint(collector.summary('CSV drag scroll ($count msgs)'));
    });
  }

  // 2. Fling
  for (final count in [256, 6000, 20000]) {
    testWidgets('fling — $count msgs', (tester) async {
      final (:ds, :ctrl) = _setup(count);
      await tester.pumpWidget(_csvApp(ds, ctrl));
      await tester.pumpAndSettle();

      ctrl.jumpTo(count ~/ 2);
      await tester.pumpAndSettle();

      final collector = _FrameTimingCollector()..start();
      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, -300),
        3000.0,
      );
      for (var i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      collector.stop();

      debugPrint(collector.summary('CSV fling ($count msgs)'));
    });
  }

  // 3. Theoretical max FPS
  for (final count in [256, 6000, 20000]) {
    testWidgets('theoretical FPS — $count msgs', (tester) async {
      final (:ds, :ctrl) = _setup(count);
      await tester.pumpWidget(_csvApp(ds, ctrl));
      await tester.pumpAndSettle();

      ctrl.jumpTo(count ~/ 2);
      await tester.pumpAndSettle();

      final collector = _FrameTimingCollector()..start();
      for (var i = 0; i < 300; i++) {
        ctrl.applyScrollDelta(-10.0);
        tester
            .renderObject<RenderChatScrollView>(find.byType(ChatScrollView))
            .markNeedsLayout();
        await tester.pump(const Duration(milliseconds: 16));
      }
      collector.stop();

      final totalUs = collector.totalTimesUs..sort();
      final meanTotal = totalUs.reduce((a, b) => a + b) / totalUs.length;
      final p95Total = totalUs[((totalUs.length - 1) * 0.95).round()];
      debugPrint(
        'CSV theoretical max FPS ($count msgs): '
        'mean=${(1000000.0 / meanTotal).toStringAsFixed(0)} FPS '
        '(mean frame ${(meanTotal / 1000).toStringAsFixed(2)}ms)  '
        'p95-limited=${(1000000.0 / p95Total).toStringAsFixed(0)} FPS '
        '(p95 frame ${(p95Total / 1000).toStringAsFixed(2)}ms)',
      );
    });
  }

  // 4. Raw computation throughput
  for (final count in [256, 6000, 20000]) {
    testWidgets('raw compute — $count msgs', (tester) async {
      final (:ds, :ctrl) = _setup(count);
      await tester.pumpWidget(_csvApp(ds, ctrl));
      await tester.pumpAndSettle();

      ctrl.jumpTo(count ~/ 2);
      await tester.pumpAndSettle();

      final render = tester.renderObject<RenderChatScrollView>(
        find.byType(ChatScrollView),
      );

      // Warm up
      for (var i = 0; i < 20; i++) {
        ctrl.applyScrollDelta(-5.0);
        render.markNeedsPaint();
        await tester.pump(const Duration(milliseconds: 16));
      }

      var totalLayoutUs = 0;
      var totalPaintUs = 0;
      var lastLId = render.debugLayoutFrameId;
      var lastPId = render.debugPaintFrameId;
      var layoutFrames = 0;
      var paintFrames = 0;

      for (var i = 0; i < 500; i++) {
        ctrl.applyScrollDelta(-5.0);
        render.markNeedsPaint();
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

      final avgLayoutUs = layoutFrames > 0 ? totalLayoutUs / layoutFrames : 0.0;
      final avgPaintUs = paintFrames > 0 ? totalPaintUs / paintFrames : 0.0;
      final avgTotalUs = avgLayoutUs + avgPaintUs;
      final rawFps = avgTotalUs > 0
          ? (1000000.0 / avgTotalUs).toStringAsFixed(0)
          : '∞';

      debugPrint(
        'CSV raw compute ($count msgs): '
        'layout=${avgLayoutUs.toStringAsFixed(1)}µs  '
        'paint=${avgPaintUs.toStringAsFixed(1)}µs  '
        'total=${avgTotalUs.toStringAsFixed(1)}µs  '
        'raw=$rawFps FPS  '
        '(layout frames: $layoutFrames, paint frames: $paintFrames)',
      );
    });
  }

  // 5. Stress — direction changes
  for (final count in [6000, 20000]) {
    testWidgets('direction stress — $count msgs', (tester) async {
      final (:ds, :ctrl) = _setup(count);
      await tester.pumpWidget(_csvApp(ds, ctrl));
      await tester.pumpAndSettle();

      ctrl.jumpTo(count ~/ 2);
      await tester.pumpAndSettle();

      final render = tester.renderObject<RenderChatScrollView>(
        find.byType(ChatScrollView),
      );
      final collector = _FrameTimingCollector()..start();

      var direction = -1.0;
      for (var i = 0; i < 200; i++) {
        if (i % 5 == 0) direction = -direction;
        ctrl.applyScrollDelta(direction * 20.0);
        render.markNeedsLayout();
        await tester.pump(const Duration(milliseconds: 16));
      }
      collector.stop();

      debugPrint(collector.summary('CSV direction stress ($count msgs)'));
      debugPrint(
        '  Attached: ${render.debugAttachedRenderCount}  '
        'Total: ${render.debugTotalRenderCount}  Chunks: ${render.debugChunkCount}',
      );
    });
  }

  // 6. Full traversal
  for (final count in [6000, 20000]) {
    testWidgets('full traversal — $count msgs', (tester) async {
      final (:ds, :ctrl) = _setup(count);
      await tester.pumpWidget(_csvApp(ds, ctrl));
      await tester.pumpAndSettle();

      ctrl.jumpTo(0);
      await tester.pumpAndSettle();

      final render = tester.renderObject<RenderChatScrollView>(
        find.byType(ChatScrollView),
      );
      final collector = _FrameTimingCollector()..start();

      final totalFrames = min(count * 2, 2000);
      for (var i = 0; i < totalFrames; i++) {
        ctrl.applyScrollDelta(-50.0);
        render.markNeedsLayout();
        await tester.pump(const Duration(milliseconds: 16));
      }
      collector.stop();

      debugPrint(collector.summary('CSV full traversal ($count msgs)'));
      debugPrint(
        '  Attached: ${render.debugAttachedRenderCount}  '
        'Total: ${render.debugTotalRenderCount}  Chunks: ${render.debugChunkCount}',
      );
    });
  }

  // 7. Memory stability
  testWidgets('memory stability — 3 traversals (6000 msgs)', (tester) async {
    final (:ds, :ctrl) = _setup(6000);
    await tester.pumpWidget(_csvApp(ds, ctrl));
    await tester.pumpAndSettle();

    final render = tester.renderObject<RenderChatScrollView>(
      find.byType(ChatScrollView),
    );

    for (var pass = 0; pass < 3; pass++) {
      ctrl.jumpTo(0);
      await tester.pump();
      for (var i = 0; i < 500; i++) {
        ctrl.applyScrollDelta(-80.0);
        render.markNeedsLayout();
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 500; i++) {
        ctrl.applyScrollDelta(80.0);
        render.markNeedsLayout();
        await tester.pump(const Duration(milliseconds: 16));
      }

      debugPrint(
        'Pass ${pass + 1}: '
        'attached=${render.debugAttachedRenderCount} '
        'total=${render.debugTotalRenderCount} '
        'chunks=${render.debugChunkCount}',
      );
    }

    expect(render.debugChunkCount, lessThanOrEqualTo(16));
  });
}

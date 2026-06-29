import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shared/listview_chat.dart';
import 'shared/metrics.dart';
import 'shared/test_messages.dart';

Widget _buildLV(
  List<dynamic> messages,
  ScrollController sc, {
  bool useTextWidget = false,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 400,
      height: 800,
      child: BenchmarkListViewWrapper(
        child: useTextWidget
            ? ListViewChatText(
                messages: messages.cast<IChatMessage>(),
                scrollController: sc,
              )
            : ListViewChatCustomPaint(
                messages: messages.cast<IChatMessage>(),
                scrollController: sc,
              ),
      ),
    ),
  ),
);

RenderBenchmarkListViewWrapper _findRender(WidgetTester tester) =>
    tester.renderObject<RenderBenchmarkListViewWrapper>(
      find.byType(BenchmarkListViewWrapper),
    );

int _countElements(WidgetTester tester, Type type) =>
    tester.elementList(find.byType(type, skipOffstage: false)).length;

int _countRenderObjects(WidgetTester tester) {
  var count = 0;
  void visit(Element element) {
    if (element.renderObject != null) count++;
    element.visitChildren(visit);
  }

  final root = tester.element(find.byType(MaterialApp));
  visit(root);
  return count;
}

void main() {
  group('ListView.builder (CustomPaint) benchmarks', () {
    for (final count in [kSmall, kMedium, kLarge]) {
      testWidgets('layout — $count messages', (tester) async {
        final messages = generateMessages(count);
        final sc = ScrollController();

        await tester.pumpWidget(_buildLV(messages, sc));
        await tester.pumpAndSettle();

        final render = _findRender(tester);
        const warmup = 10;
        const measured = 100;

        // Warmup
        for (var i = 0; i < warmup; i++) {
          tester.view.physicalSize = Size(401.0 + i % 2, 800);
          tester.view.devicePixelRatio = 1.0;
          await tester.pump();
        }

        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        await tester.pump();

        // Measure layout
        final samples = <int>[];
        for (var i = 0; i < measured; i++) {
          tester.view.physicalSize = Size(400.0 + (i.isEven ? 0 : 1), 800);
          tester.view.devicePixelRatio = 1.0;
          await tester.pump();
          samples.add(render.debugLastLayoutDuration.inMicroseconds);
        }

        final metrics = BenchmarkMetrics('LV-CP layout ($count msgs)', samples);
        // ignore: avoid_print
        print(metrics);

        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        sc.dispose();
      });

      testWidgets('paint scroll-only — $count messages', (tester) async {
        final messages = generateMessages(count);
        final sc = ScrollController();

        await tester.pumpWidget(_buildLV(messages, sc));
        await tester.pumpAndSettle();

        final render = _findRender(tester);
        const warmup = 10;
        const measured = 300;

        // Warmup
        for (var i = 0; i < warmup; i++) {
          sc.jumpTo(sc.offset + 5.0);
          await tester.pump();
        }

        // Measure
        final samples = <int>[];
        for (var i = 0; i < measured; i++) {
          sc.jumpTo(sc.offset + 3.0);
          await tester.pump();
          samples.add(render.debugLastPaintDuration.inMicroseconds);
        }

        final metrics = BenchmarkMetrics(
          'LV-CP paint scroll ($count msgs)',
          samples,
        );
        // ignore: avoid_print
        print(metrics);

        sc.dispose();
      });

      testWidgets('fling — $count messages', (tester) async {
        final messages = generateMessages(count);
        final sc = ScrollController();

        await tester.pumpWidget(_buildLV(messages, sc));
        await tester.pumpAndSettle();

        // Scroll to middle
        sc.jumpTo(sc.position.maxScrollExtent / 2);
        await tester.pumpAndSettle();

        // Fling — total frame time
        final samples = <int>[];
        await tester.fling(
          find.byType(ListView),
          const Offset(0, -500),
          2000,
        );

        for (var i = 0; i < 300; i++) {
          final sw = Stopwatch()..start();
          await tester.pump(const Duration(milliseconds: 16));
          samples.add(sw.elapsed.inMicroseconds);
        }

        final metrics = BenchmarkMetrics(
          'LV-CP fling frame ($count msgs)',
          samples,
        );
        // ignore: avoid_print
        print(metrics);

        sc.dispose();
      });
    }

    testWidgets('memory — static counts', (tester) async {
      for (final count in [kSmall, kMedium, kLarge]) {
        final messages = generateMessages(count);
        final sc = ScrollController();

        await tester.pumpWidget(_buildLV(messages, sc));
        await tester.pumpAndSettle();

        final bubbleCount = _countElements(tester, CustomPaintBubble);
        final roCount = _countRenderObjects(tester);

        final snapshot = MemorySnapshot(
          label: 'LV-CP static ($count msgs)',
          elementCount: bubbleCount,
          renderObjectCount: roCount,
        );
        // ignore: avoid_print
        print(snapshot);

        sc.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('memory — scroll through all (256 msgs)', (tester) async {
      final messages = generateMessages(kMedium);
      final sc = ScrollController();

      await tester.pumpWidget(_buildLV(messages, sc));
      await tester.pumpAndSettle();

      var peakElements = 0;
      var peakRO = 0;

      // Scroll through everything
      final maxExtent = sc.position.maxScrollExtent;
      final step = maxExtent / 64;
      for (var offset = 0.0; offset <= maxExtent; offset += step) {
        sc.jumpTo(offset);
        await tester.pump();
        final elements = _countElements(tester, CustomPaintBubble);
        final ro = _countRenderObjects(tester);
        if (elements > peakElements) peakElements = elements;
        if (ro > peakRO) peakRO = ro;
      }

      // ignore: avoid_print
      print(
        'LV-CP scroll-through peak: elements=$peakElements '
        'renderObjects=$peakRO',
      );

      // Return to start
      sc.jumpTo(0);
      await tester.pumpAndSettle();

      final elementsAfter = _countElements(tester, CustomPaintBubble);
      // ignore: avoid_print
      print('LV-CP after return: elements=$elementsAfter');

      sc.dispose();
    });

    testWidgets('leak detection — 50 scroll cycles (256 msgs)', (tester) async {
      final messages = generateMessages(kMedium);
      final sc = ScrollController();

      await tester.pumpWidget(_buildLV(messages, sc));
      await tester.pumpAndSettle();

      final maxExtent = sc.position.maxScrollExtent;
      final initialElements = _countElements(tester, CustomPaintBubble);
      final elementCounts = <int>[];

      for (var cycle = 0; cycle < 50; cycle++) {
        sc.jumpTo(0);
        await tester.pump();
        sc.jumpTo(maxExtent);
        await tester.pump();
        elementCounts.add(_countElements(tester, CustomPaintBubble));
      }

      final maxEl = elementCounts.reduce((a, b) => a > b ? a : b);
      final minEl = elementCounts.reduce((a, b) => a < b ? a : b);

      // ignore: avoid_print
      print(
        'LV-CP leak test: initial=$initialElements '
        'min=$minEl max=$maxEl range=${maxEl - minEl}',
      );

      expect(
        maxEl - minEl,
        lessThan(10),
        reason: 'Element count should be stable across scroll cycles',
      );

      sc.dispose();
    });

    testWidgets('resize stress �� 200 frames', (tester) async {
      final messages = generateMessages(kMedium);
      final sc = ScrollController();

      await tester.pumpWidget(_buildLV(messages, sc));
      await tester.pumpAndSettle();

      final render = _findRender(tester);
      final samples = <int>[];

      for (var i = 0; i < 200; i++) {
        final width = 400.0 + (i < 100 ? i : 200 - i);
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        await tester.pump();
        final total =
            render.debugLastLayoutDuration.inMicroseconds +
            render.debugLastPaintDuration.inMicroseconds;
        samples.add(total);
      }

      final metrics = BenchmarkMetrics('LV-CP resize stress', samples);
      // ignore: avoid_print
      print(metrics);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      sc.dispose();
    });
  });

  // ----- Text widget variant -----

  group('ListView.builder (Text widget) benchmarks', () {
    for (final count in [kSmall, kMedium, kLarge]) {
      testWidgets('layout — $count messages', (tester) async {
        final messages = generateMessages(count);
        final sc = ScrollController();

        await tester.pumpWidget(_buildLV(messages, sc, useTextWidget: true));
        await tester.pumpAndSettle();

        final render = _findRender(tester);
        const measured = 100;

        // Warmup
        for (var i = 0; i < 10; i++) {
          tester.view.physicalSize = Size(401.0 + i % 2, 800);
          tester.view.devicePixelRatio = 1.0;
          await tester.pump();
        }

        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        await tester.pump();

        final samples = <int>[];
        for (var i = 0; i < measured; i++) {
          tester.view.physicalSize = Size(400.0 + (i.isEven ? 0 : 1), 800);
          tester.view.devicePixelRatio = 1.0;
          await tester.pump();
          samples.add(render.debugLastLayoutDuration.inMicroseconds);
        }

        final metrics = BenchmarkMetrics(
          'LV-Text layout ($count msgs)',
          samples,
        );
        // ignore: avoid_print
        print(metrics);

        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        sc.dispose();
      });

      testWidgets('fling — $count messages', (tester) async {
        final messages = generateMessages(count);
        final sc = ScrollController();

        await tester.pumpWidget(_buildLV(messages, sc, useTextWidget: true));
        await tester.pumpAndSettle();

        sc.jumpTo(sc.position.maxScrollExtent / 2);
        await tester.pumpAndSettle();

        final samples = <int>[];
        await tester.fling(
          find.byType(ListView),
          const Offset(0, -500),
          2000,
        );

        for (var i = 0; i < 300; i++) {
          final sw = Stopwatch()..start();
          await tester.pump(const Duration(milliseconds: 16));
          samples.add(sw.elapsed.inMicroseconds);
        }

        final metrics = BenchmarkMetrics(
          'LV-Text fling frame ($count msgs)',
          samples,
        );
        // ignore: avoid_print
        print(metrics);

        sc.dispose();
      });
    }
  });
}

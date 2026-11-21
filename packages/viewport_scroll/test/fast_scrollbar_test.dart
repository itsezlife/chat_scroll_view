import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viewport_scroll/testing.dart';
import 'package:viewport_scroll/viewport_scroll.dart';

const _style = FastScrollbarStyle(
  thumbColor: Color(0xFFEEEEEE),
  thumbIconColor: Color(0xFF000000),
  labelColor: Color(0xFFFFFFFF),
  labelTextStyle: TextStyle(fontSize: 13, color: Color(0xFF000000)),
);

const _thumb = ValueKey('fast-scrollbar-thumb');
const _label = ValueKey('fast-scrollbar-label');

// A 300 x 400 list of 100 rows 50 tall: 5000 of content, 4600 of range.
const _width = 300.0;
const _height = 400.0;
const _range = 4600.0;

void main() {
  late ScrollController controller;
  late List<int> tapped;

  setUp(() {
    controller = ScrollController();
    tapped = [];
  });

  tearDown(() => controller.dispose());

  // Labels a 500-pixel band of the list: "Band 0" for 0..499 and so on.
  String? bands(double offset) => 'Band ${offset ~/ 500}';

  Future<void> pump(
    WidgetTester tester, {
    FastScrollbarPolicy policy = FastScrollbarPolicy.$Android,
    String? Function(double offset)? labelAt = _noLabel,
    bool enabled = true,
    TextDirection direction = TextDirection.ltr,
    int rows = 100,
  }) async {
    tester.view
      ..physicalSize = const Size(_width, _height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: direction,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(_width, _height)),
          child: FastScrollbar(
            target: ScrollControllerFastScrollTarget(controller),
            policy: policy,
            style: _style,
            labelAt: switch (identical(labelAt, _noLabel) ? bands : labelAt) {
              final byOffset? => (progress) => byOffset(
                ScrollControllerFastScrollTarget(controller).offsetAt(progress),
              ),
              null => null,
            },
            enabled: enabled,
            child: ListView.builder(
              controller: controller,
              itemCount: rows,
              itemExtent: 50,
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => tapped.add(index),
                child: Text('$index'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // A frame to start what the last change set off, then time for it to run.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Rect thumb(WidgetTester tester) => tester.getRect(find.byKey(_thumb));

  // The thumb's centre row, just in from the edge: inside every preset's
  // hit area.
  Offset grip(WidgetTester tester, {double fromEdge = 4}) {
    final rect = thumb(tester);
    return Offset(_width - fromEdge, rect.center.dy);
  }

  group('drag', () {
    testWidgets(r'$Android: the thumb travels the track, 12 in from each '
        'end, as the content scrolls its range', (tester) async {
      await pump(tester);
      expect(thumb(tester).top, 12);
      expect(thumb(tester).height, 30);
      controller.jumpTo(_range);
      await tester.pump();
      expect(thumb(tester).bottom, _height - 12);
      controller.jumpTo(_range / 2);
      await tester.pump();
      expect(thumb(tester).top, closeTo(12 + (_height - 54) / 2, 0.01));
    });

    testWidgets(r'$Android: a drag of the whole travel scrolls end to end, '
        'and half of it half way', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(grip(tester));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, (_height - 54) / 2 - 20));
      await tester.pump();
      expect(controller.offset, closeTo(_range / 2, 0.5));
      await gesture.moveBy(const Offset(0, (_height - 54) / 2));
      await tester.pump();
      expect(controller.offset, _range);
      await gesture.up();
    });

    testWidgets('its diagnostic lines carry one prefix: the press, the drag '
        'against the offset, its end', (tester) async {
      final lines = <String>[];
      final print = debugPrint;
      debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
      await pump(tester);
      final gesture = await tester.startGesture(grip(tester));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(lines, everyElement(startsWith('[fastscroll] ')));
      expect(lines.where((l) => l.contains('down at y')), hasLength(1));
      expect(lines.where((l) => l.contains('drag to y')), isNotEmpty);
      expect(lines.where((l) => l.contains('drag end')), hasLength(1));

      lines.clear();
      FastScrollbar.debugLog = false;
      addTearDown(() => FastScrollbar.debugLog = true);
      final again = await tester.startGesture(grip(tester));
      await tester.pump();
      await again.up();
      // Given back before the test ends: the binding checks it.
      debugPrint = print;
      expect(lines, isEmpty);
    });

    testWidgets('a press keeps the content where it is, wherever it lands '
        'on the thumb, and the drag goes on from there', (tester) async {
      await pump(tester);
      controller.jumpTo(1000);
      await tester.pump();
      final low = Offset(_width - 4, thumb(tester).bottom - 2);
      final gesture = await tester.startGesture(low);
      await tester.pump();
      expect(controller.offset, 1000);
      await gesture.moveBy(const Offset(0, 30));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(controller.offset, closeTo(1000 + 60 * _range / 346, 0.5));
      await gesture.up();
    });

    testWidgets('past an end the content holds there until the finger '
        'comes back', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(grip(tester));
      await gesture.moveBy(const Offset(0, -20));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(controller.offset, 0);
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();
      expect(controller.offset, 0);
      await gesture.up();
    });

    testWidgets(r'$IOS: the thin thumb travels 3 in from each end and maps '
        'the drag the same way', (tester) async {
      await pump(tester, policy: FastScrollbarPolicy.$IOS);
      controller.jumpTo(1);
      await tester.pump();
      expect(thumb(tester).height, 44);
      expect(thumb(tester).width, 3);
      expect(thumb(tester).right, _width - 3);
      final gesture = await tester.startGesture(grip(tester, fromEdge: 5));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, (_height - 50) / 2 - 20));
      await tester.pump();
      expect(controller.offset, closeTo(1 + _range / 2, 0.5));
      await tester.pump(const Duration(milliseconds: 150));
      expect(thumb(tester).width, 6);
      await gesture.up();
    });

    testWidgets('a press away from the thumb reaches the content', (
      tester,
    ) async {
      await pump(tester);
      await tester.tapAt(const Offset(20, 75));
      expect(tapped, [1]);
      await tester.tapAt(Offset(_width - 4, thumb(tester).bottom + 40));
      expect(tapped, [1, 1]);
    });
  });

  group('label', () {
    testWidgets('follows the finger: centred on the thumb, it reads the '
        'label of the offset the drag reached', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(grip(tester));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 100));
      await settle(tester);
      final offset = controller.offset;
      expect(find.text('Band ${offset ~/ 500}'), findsOneWidget);
      final label = tester.getRect(find.byKey(_label));
      expect(label.center.dy, closeTo(thumb(tester).center.dy, 0.5));
      // Dragged, it stands 35 + 30 from the edge, clear of the finger.
      expect(label.right, closeTo(_width - 65, 0.5));
      await gesture.moveBy(const Offset(0, 120));
      await settle(tester);
      expect(find.text('Band ${controller.offset ~/ 500}'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(_label)).center.dy,
        closeTo(thumb(tester).center.dy, 0.5),
      );
      await gesture.up();
      await settle(tester);
      expect(
        tester.getRect(find.byKey(_label)).right,
        closeTo(_width - 35, 0.5),
      );
    });

    testWidgets('no labeller, no label: the thumb still drags', (tester) async {
      await pump(tester, labelAt: null);
      final gesture = await tester.startGesture(grip(tester));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 100));
      await settle(tester);
      expect(find.byKey(_label), findsNothing);
      expect(controller.offset, greaterThan(0));
      await gesture.up();
    });

    testWidgets('an offset the content cannot label yet keeps the last '
        'label up: no flicker while rows load', (tester) async {
      // Answers every other band only, as rows still loading do.
      await pump(
        tester,
        labelAt: (offset) =>
            (offset ~/ 100).isEven ? 'Band ${offset ~/ 1000}' : null,
      );
      controller.jumpTo(400);
      await settle(tester);
      expect(find.text('Band 0'), findsOneWidget);
      for (final offset in [500.0, 650.0, 720.0]) {
        controller.jumpTo(offset);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(_opacity(tester, _label), 1, reason: 'at $offset');
        expect(find.text('Band 0'), findsOneWidget, reason: 'at $offset');
      }
    });

    testWidgets('a null label shows none', (tester) async {
      await pump(tester, labelAt: (offset) => offset < 1000 ? null : 'Late');
      controller.jumpTo(500);
      await settle(tester);
      expect(find.byKey(_label), findsNothing);
      controller.jumpTo(2000);
      await settle(tester);
      expect(find.text('Late'), findsOneWidget);
    });

    testWidgets('a change rolls the shared last word in place', (tester) async {
      await pump(
        tester,
        labelAt: (offset) => offset < 1000 ? 'March 2024' : 'April 2024',
      );
      controller.jumpTo(10);
      await settle(tester);
      // Where the text sits in the label, top to top.
      double inLabel(String text) =>
          tester.getRect(find.text(text)).top -
          tester.getRect(find.byKey(_label)).top;
      final rest = inLabel('March 2024');
      controller.jumpTo(2000);
      await tester.pump(const Duration(milliseconds: 50));
      // Mid roll: both months, one year that has not moved vertically.
      expect(find.text('March'), findsOneWidget);
      expect(find.text('April'), findsOneWidget);
      expect(find.text('2024'), findsOneWidget);
      expect(inLabel('2024'), closeTo(rest, 0.01));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('March'), findsNothing);
      expect(find.text('April 2024'), findsOneWidget);
    });
  });

  group('show and hide', () {
    testWidgets(r'$Android: the thumb shows while enabled; the label shows '
        'on scroll and hides 2 s after it', (tester) async {
      await pump(tester);
      expect(find.byKey(_thumb), findsOneWidget);
      expect(find.byKey(_label), findsNothing);
      controller.jumpTo(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(_label), findsOneWidget);
      expect(_opacity(tester, _label), 1);
      await tester.pump(const Duration(milliseconds: 1800));
      expect(_opacity(tester, _label), 1);
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump(const Duration(milliseconds: 60));
      expect(_opacity(tester, _label), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(_label), findsNothing);
      // The thumb stays.
      await tester.pump(const Duration(seconds: 5));
      expect(_opacity(tester, _thumb), 1);
    });

    testWidgets(r'$Android: disabled, there is no thumb and a press there '
        'reaches the content', (tester) async {
      await pump(tester, enabled: false);
      expect(_opacity(tester, _thumb), 0);
      await tester.tapAt(const Offset(_width - 4, 27));
      expect(tapped, [0]);
    });

    testWidgets(r'$IOS: the thumb shows on scroll and hides 2 s after; '
        'nothing hides while dragging', (tester) async {
      await pump(tester, policy: FastScrollbarPolicy.$IOS);
      expect(_opacity(tester, _thumb), 0);
      controller.jumpTo(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_opacity(tester, _thumb), 1);
      expect(_opacity(tester, _label), 1);
      final gesture = await tester.startGesture(grip(tester, fromEdge: 5));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(seconds: 5));
      expect(_opacity(tester, _thumb), 1);
      expect(_opacity(tester, _label), 1);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 1900));
      expect(_opacity(tester, _thumb), 1);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_opacity(tester, _thumb), 0);
      expect(find.byKey(_label), findsNothing);
    });

    testWidgets(r'$IOS: a hidden thumb takes no press', (tester) async {
      await pump(tester, policy: FastScrollbarPolicy.$IOS);
      await tester.tapAt(const Offset(_width - 5, 25));
      expect(tapped, [0]);
    });

    testWidgets(r'$IOS: hidden while the viewport shows 55 % of the content '
        'or more', (tester) async {
      // 15 rows: 750 of content, 400 of it in view (53 %).
      await pump(tester, policy: FastScrollbarPolicy.$IOS, rows: 15);
      controller.jumpTo(10);
      await settle(tester);
      expect(_opacity(tester, _thumb), 1);
      // 14 rows: 700, 57 % in view.
      await pump(tester, policy: FastScrollbarPolicy.$IOS, rows: 14);
      controller.jumpTo(20);
      await settle(tester);
      await settle(tester);
      expect(_opacity(tester, _thumb), 0);
    });

    testWidgets('content that does not scroll has no thumb', (tester) async {
      await pump(tester, rows: 5);
      expect(_opacity(tester, _thumb), 0);
    });
  });

  group('haptics', () {
    late List<String> haptics;

    setUp(() {
      haptics = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments as String);
            }
            return null;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    testWidgets(r'$IOS: a 200 ms hold starts the drag with an impact, and '
        'each label change ticks', (tester) async {
      await pump(tester, policy: FastScrollbarPolicy.$IOS);
      controller.jumpTo(1);
      await tester.pump(const Duration(milliseconds: 300));
      final gesture = await tester.startGesture(grip(tester, fromEdge: 5));
      await tester.pump(const Duration(milliseconds: 150));
      expect(haptics, isEmpty);
      await tester.pump(const Duration(milliseconds: 60));
      expect(haptics, ['HapticFeedbackType.mediumImpact']);
      // One band is 500 of range: 350 / 4600 of the track per band.
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();
      expect(haptics, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.selectionClick',
      ]);
      await gesture.up();
    });

    testWidgets(r'$Android: none', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(grip(tester));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      expect(haptics, isEmpty);
    });
  });

  group('direction', () {
    for (final policy in [
      FastScrollbarPolicy.$Android,
      FastScrollbarPolicy.$IOS,
    ]) {
      testWidgets(
        'right to left keeps the date presets on the right '
        '(${identical(policy, FastScrollbarPolicy.$IOS) ? 'iOS' : 'Android'})',
        (tester) async {
          await pump(tester, policy: policy, direction: TextDirection.rtl);
          controller.jumpTo(100);
          await settle(tester);
          expect(thumb(tester).right, greaterThan(_width - 10));
          expect(tester.getRect(find.byKey(_label)).right, lessThan(_width));
        },
      );
    }

    testWidgets('a mirroring policy goes to the left edge in right to left', (
      tester,
    ) async {
      const ios = FastScrollbarPolicy.$IOS;
      const mirrored = FastScrollbarPolicy(
        thumb: FastScrollThumb.line(),
        thumbExtent: 44,
        trackInset: 3,
        hitWidth: 13,
        hitSlop: 2,
        thumbIdleHide: Duration(seconds: 2),
        thumbShow: FastScrollMotion(Duration(milliseconds: 300)),
        thumbHide: FastScrollMotion(Duration(milliseconds: 300)),
        labelIdleHide: Duration(seconds: 2),
        labelShow: FastScrollMotion(Duration(milliseconds: 200)),
        labelHide: FastScrollMotion(Duration(milliseconds: 200)),
        labelScaleFrom: 1,
        labelGap: 12,
        labelPadding: EdgeInsets.symmetric(horizontal: 13),
        labelHeight: 32,
        labelRadius: 16,
        dragShift: 80,
        dragShiftIn: FastScrollMotion(Duration(milliseconds: 100)),
        dragShiftOut: FastScrollMotion(Duration(milliseconds: 200)),
        labelChange: FastScrollMotion(Duration(milliseconds: 200)),
        labelChangeSlide: 12,
        holdToDrag: Duration(milliseconds: 200),
        dragStartHaptic: false,
        labelChangeHaptic: false,
        maxViewportFraction: 0.55,
        mirrorsInRtl: true,
      );
      expect(mirrored.thumbExtent, ios.thumbExtent);
      await pump(tester, policy: mirrored, direction: TextDirection.rtl);
      controller.jumpTo(100);
      await settle(tester);
      expect(thumb(tester).left, 3);
      expect(tester.getRect(find.byKey(_label)).left, 12);
      final gesture = await tester.startGesture(
        Offset(5, thumb(tester).center.dy),
      );
      await gesture.moveBy(const Offset(0, 30));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(controller.offset, greaterThan(100));
      await gesture.up();
    });
  });

  group('any target', () {
    Future<FakeFastScrollTarget> pumpFake(
      WidgetTester tester, {
      double? progress = 0,
      String? Function(double progress)? labelAt,
    }) async {
      tester.view
        ..physicalSize = const Size(_width, _height)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final target = FakeFastScrollTarget(progress: progress);
      addTearDown(target.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(_width, _height)),
            child: FastScrollbar(
              target: target,
              policy: FastScrollbarPolicy.$Android,
              style: _style,
              labelAt: labelAt,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump();
      return target;
    }

    testWidgets('the thumb stands at the target\'s progress', (tester) async {
      final target = await pumpFake(tester, progress: 0.5);
      await tester.pump();
      expect(thumb(tester).top, closeTo(12 + (_height - 54) / 2, 0.01));
      target.progress = 1;
      await tester.pump();
      expect(thumb(tester).bottom, _height - 12);
    });

    testWidgets('a press stops the target; a drag is bracketed and moves it '
        'by the share of the travel', (tester) async {
      final target = await pumpFake(tester);
      final gesture = await tester.startGesture(grip(tester));
      expect(target.stops, 1);
      expect(target.dragsStarted, 0);
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, (_height - 54) / 4 - 20));
      await tester.pump();
      expect(target.dragsStarted, 1);
      expect(target.jumps.last, closeTo(0.25, 1e-6));
      await gesture.up();
      await tester.pump();
      expect(target.dragsEnded, 1);
    });

    testWidgets('content that cannot scroll shows no thumb', (tester) async {
      await pumpFake(tester, progress: null);
      await settle(tester);
      expect(find.byKey(_thumb), findsNothing);
    });

    testWidgets('labels are asked by progress', (tester) async {
      final asked = <double>[];
      await pumpFake(
        tester,
        progress: 0.75,
        labelAt: (p) {
          asked.add(p);
          return 'At $p';
        },
      );
      await settle(tester);
      expect(asked.last, 0.75);
    });
  });

  group('ScrollControllerFastScrollTarget', () {
    FastScrollTargetContract.run((tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListView.builder(
            controller: controller,
            itemCount: 100,
            itemExtent: 50,
            itemBuilder: (context, index) => Text('$index'),
          ),
        ),
      );
      return FastScrollTargetHarness(
        target: ScrollControllerFastScrollTarget(controller),
        settle: tester.pump,
      );
    });
  });
}

// The harness's default: stands for the band labeller (null is no label).
String? _noLabel(double offset) => null;

double _opacity(WidgetTester tester, Key key) {
  final finder = find.byKey(key);
  if (finder.evaluate().isEmpty) return 0;
  var opacity = 1.0;
  for (final widget in tester.widgetList<Opacity>(
    find.ancestor(of: finder, matching: find.byType(Opacity)),
  )) {
    opacity *= widget.opacity;
  }
  return opacity;
}

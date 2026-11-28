import 'dart:ui' show PointerDeviceKind;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChromeInputClass.forPlatform', () {
    test('phone and tablet systems are touch, the rest mouse', () {
      expect(
        {
          for (final platform in TargetPlatform.values)
            platform: ChromeInputClass.forPlatform(platform),
        },
        {
          TargetPlatform.android: ChromeInputClass.touch,
          TargetPlatform.iOS: ChromeInputClass.touch,
          TargetPlatform.fuchsia: ChromeInputClass.mouse,
          TargetPlatform.linux: ChromeInputClass.mouse,
          TargetPlatform.macOS: ChromeInputClass.mouse,
          TargetPlatform.windows: ChromeInputClass.mouse,
        },
      );
    });
  });

  group('ChromeInputClass.fromPointerKind', () {
    test('a finger or a pen is touch, a mouse or a trackpad mouse', () {
      expect(
        {
          for (final kind in PointerDeviceKind.values)
            kind: ChromeInputClass.fromPointerKind(kind),
        },
        {
          PointerDeviceKind.touch: ChromeInputClass.touch,
          PointerDeviceKind.stylus: ChromeInputClass.touch,
          PointerDeviceKind.invertedStylus: ChromeInputClass.touch,
          PointerDeviceKind.mouse: ChromeInputClass.mouse,
          PointerDeviceKind.trackpad: ChromeInputClass.mouse,
          PointerDeviceKind.unknown: null,
        },
      );
    });

    test('the class reads as touch or not', () {
      expect(ChromeInputClass.touch.isTouch, isTrue);
      expect(ChromeInputClass.mouse.isTouch, isFalse);
    });
  });

  group('ChromeInputClass.of', () {
    late List<ChromeInputClass> seen;

    setUp(() => seen = []);

    Widget reader() => Builder(
      builder: (context) {
        seen.add(ChromeInputClass.of(context));
        return const SizedBox.expand();
      },
    );

    testWidgets('without a scope it is the platform default', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(reader());
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.pumpWidget(Center(child: reader()));
      debugDefaultTargetPlatformOverride = null;

      expect(seen, [ChromeInputClass.touch, ChromeInputClass.mouse]);
    });

    testWidgets('a scope starts at the platform default or the host value', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(ChromeInputClassScope(child: reader()));
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(
        ChromeInputClassScope(
          key: UniqueKey(),
          initial: ChromeInputClass.mouse,
          child: reader(),
        ),
      );

      expect(seen, [ChromeInputClass.touch, ChromeInputClass.mouse]);
    });

    testWidgets('follows the pointer kind of the last event', (tester) async {
      await tester.pumpWidget(
        ChromeInputClassScope(initial: ChromeInputClass.touch, child: reader()),
      );
      expect(seen.last, ChromeInputClass.touch);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(const Offset(20, 20));
      await tester.pump();
      expect(seen.last, ChromeInputClass.mouse);

      await tester.tapAt(const Offset(30, 30));
      await tester.pump();
      expect(seen.last, ChromeInputClass.touch);

      final pen = await tester.startGesture(
        const Offset(40, 40),
        kind: PointerDeviceKind.stylus,
      );
      await pen.up();
      await tester.pump();
      expect(seen.last, ChromeInputClass.touch);

      final trackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await trackpad.panZoomStart(const Offset(50, 50));
      await trackpad.panZoomEnd();
      await tester.pump();
      expect(seen.last, ChromeInputClass.mouse);
    });

    testWidgets('readers rebuild only when the class changes', (tester) async {
      await tester.pumpWidget(
        ChromeInputClassScope(initial: ChromeInputClass.touch, child: reader()),
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(seen, [ChromeInputClass.touch]);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(const Offset(20, 20));
      await mouse.moveTo(const Offset(30, 30));
      await tester.pump();
      expect(seen, [ChromeInputClass.touch, ChromeInputClass.mouse]);
    });

    testWidgets('sees events that land outside its subtree', (tester) async {
      await tester.pumpWidget(
        Stack(
          textDirection: TextDirection.ltr,
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: 10,
              height: 10,
              child: ChromeInputClassScope(
                initial: ChromeInputClass.mouse,
                child: reader(),
              ),
            ),
          ],
        ),
      );

      await tester.tapAt(const Offset(300, 300));
      await tester.pump();

      expect(seen.last, ChromeInputClass.touch);
    });

    testWidgets('stops listening once removed', (tester) async {
      await tester.pumpWidget(
        ChromeInputClassScope(initial: ChromeInputClass.mouse, child: reader()),
      );
      await tester.pumpWidget(const SizedBox());

      // A removed scope that still listened would set state on a defunct
      // element and fail here.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}

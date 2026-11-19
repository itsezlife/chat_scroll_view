import 'package:attach_sheet/attach_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pages_rig.dart';

void main() {
  const android = AttachSheetPolicy.android();
  const ios = AttachSheetPolicy.ios();

  group('Android widths', () {
    test('a label plus 16 a side, 8 a side from 56, at most 84', () {
      expect(android.tabWidths([30], 0), [62]);
      expect(android.tabWidths([48], 0), [48 + 2 * 12]);
      expect(android.tabWidths([56], 0), [72]);
      expect(android.tabWidths([80], 0), [84]);
    });

    test('room left over is shared evenly', () {
      expect(android.tabWidths([30, 30], 200), [100, 100]);
    });
  });

  group('iOS widths', () {
    test('160 for two tabs, 240 for three, 300 for four, else the screen', () {
      double bar(int n, double available) =>
          ios
              .tabWidths(List.filled(n, 30), available)
              .fold<double>(0, (a, b) => a + b) +
          2 * ios.tabBar.innerPadding;
      expect(bar(2, 346), 160);
      expect(bar(3, 346), 240);
      expect(bar(4, 346), 300);
      expect(bar(5, 346), 346);
    });
  });

  group('Android pop-in', () {
    const popIn = AttachTabPopIn(
      delay: Duration(milliseconds: 20),
      step: Duration(milliseconds: 32),
      anchorIndex: 3,
      overshoot: 1.1,
      grow: Duration(milliseconds: 200),
      growCurve: Cubic(0, 0, 0.58, 1),
      fadeCurve: Cubic(0.42, 0, 0.58, 1),
      settle: Duration(milliseconds: 100),
      settleCurve: Cubic(0.42, 0, 1, 1),
    );

    test('is the policy\'s', () {
      final style = android.tabBar.popIn!;
      expect(style.step, popIn.step);
      expect(style.overshoot, 1.1);
      expect(style.grow, const Duration(milliseconds: 200));
      expect(style.settle, const Duration(milliseconds: 100));
      expect(ios.tabBar.popIn, isNull);
    });

    test('the last of four tabs starts first, 32 ms apart', () {
      expect(popIn.startOf(3), Duration.zero);
      expect(popIn.startOf(0), const Duration(milliseconds: 96));
      expect(popIn.at(0, const Duration(milliseconds: 96)).scale, 0);
      expect(
        popIn.at(3, const Duration(milliseconds: 200)).scale,
        closeTo(1.1, 1e-9),
      );
      expect(popIn.at(3, const Duration(milliseconds: 300)).scale, 1);
      expect(popIn.at(0, const Duration(milliseconds: 396)).scale, 1);
    });

    testWidgets('tabs pop in staggered and settle at full size', (
      tester,
    ) async {
      await PagesRig.open(
        tester,
        policy: android,
        settle: false,
        pages: [
          rowsPage('gallery'),
          rowsPage('files'),
          rowsPage('music'),
          rowsPage('contact'),
        ],
      );
      double scaleOf(String id) => tester
          .widget<Transform>(find.byKey(ValueKey('attach-tab-pop-$id')))
          .transform
          .storage[0];

      await tester.pump(const Duration(milliseconds: 100));
      expect(scaleOf('contact'), greaterThan(scaleOf('gallery')));

      await tester.pumpAndSettle();
      for (final id in ['gallery', 'files', 'music', 'contact']) {
        expect(scaleOf(id), closeTo(1, 1e-6));
      }
    });
  });

  group('switch', () {
    testWidgets('Android: the old page drops 78 and fades over 180 ms, the '
        'new one springs up', (tester) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery'), rowsPage('files')],
      );
      final sheetTop = rig.top;
      double rowTop(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('$id-row-0'))).dy - sheetTop;

      await tester.tap(rig.tab('files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(rowTop('gallery'), inExclusiveRange(0, 78));

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(rowTop('files'), inInclusiveRange(1, 78));

      await tester.pumpAndSettle();
      expect(rowTop('files'), closeTo(0, 0.5));
      expect(rig.shows('gallery'), isFalse);
    });

    testWidgets('a tap during a switch waits (Android)', (tester) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery'), rowsPage('files'), rowsPage('music')],
      );
      await tester.tap(rig.tab('files'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(rig.tab('music'));
      await tester.pumpAndSettle();
      expect(rig.shows('files'), isTrue);
      expect(rig.shows('music'), isFalse);
    });

    testWidgets('iOS: a 0.23 s cross-fade as the new page rises 10', (
      tester,
    ) async {
      final rig = await PagesRig.open(
        tester,
        policy: ios,
        pages: [rowsPage('gallery'), rowsPage('files')],
      );
      final sheetTop = rig.top;
      await tester.tap(rig.tab('files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final rise =
          tester.getTopLeft(find.byKey(const ValueKey('files-row-0'))).dy -
          sheetTop;
      expect(rise, inExclusiveRange(0, 10));
      expect(
        find.byKey(const ValueKey('gallery-row-0')).evaluate(),
        isNotEmpty,
      );

      await tester.pumpAndSettle();
      expect(rig.shows('gallery'), isFalse);
    });
  });

  test('Android: the bar drops 36 as it leaves; iOS: it shrinks to 0.85', () {
    expect(android.tabBar.hideDrop, 36);
    expect(
      android.tabBar.hideMotion,
      const MotionSpec(Duration(milliseconds: 180), Curves.decelerate),
    );
    expect(ios.tabBar.hideScale, 0.85);
    expect(
      ios.tabBar.hideMotion,
      const MotionSpec(Duration(milliseconds: 100), Curves.linear),
    );
  });
}

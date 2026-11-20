import 'dart:async';

import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sheet_rig.dart';

void main() {
  const policy = AttachSheetPolicy.android();
  // 400 x 800 with a 24 status bar.
  final rest = policy.collapsedTop(
    const Size(400, 800),
    const EdgeInsets.only(top: 24),
  );
  const pinned = 24.0;

  group('open', () {
    testWidgets('springs up from the bottom edge to its rest', (tester) async {
      final rig = await SheetRig.open(tester, policy: policy, settle: false);
      expect(rig.top, 800);

      // The open starts on the frame after the sheet's first layout.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.top, inExclusiveRange(rest, 800));

      await tester.pumpAndSettle();
      expect(rig.top, closeTo(rest, 0.5));
    });

    testWidgets('the spring overshoots the rest (damping 0.75)', (
      tester,
    ) async {
      final rig = await SheetRig.open(tester, policy: policy, settle: false);
      var highest = 800.0;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (rig.top < highest) highest = rig.top;
      }
      expect(highest, lessThan(rest - 1));
    });

    testWidgets('the scrim waits 20 ms, then overshoots to 51/255 by 420', (
      tester,
    ) async {
      final rig = await SheetRig.open(tester, policy: policy, settle: false);
      await tester.pump(const Duration(milliseconds: 19));
      expect(rig.dim, 0);

      var peak = 0.0;
      for (var t = 0; t < 420; t += 10) {
        await tester.pump(const Duration(milliseconds: 10));
        if (rig.dim > peak) peak = rig.dim;
      }
      expect(peak, greaterThan(51 / 255 + 0.001));
      await tester.pumpAndSettle();
      expect(rig.dim, closeTo(51 / 255, 0.002));
    });

    testWidgets('tells the host it opened', (tester) async {
      final host = RecordingHost();
      await SheetRig.open(tester, policy: policy, host: host);
      expect(host.calls, ['opened']);
    });
  });

  group('expand', () {
    testWidgets('a drag up raises the sheet, then scrolls the page', (
      tester,
    ) async {
      final rig = await SheetRig.open(tester, policy: policy);

      await rig.drag(-100);
      await tester.pump();
      expect(rig.top, closeTo(rest - 100, 1));
      expect(rig.scrolled, 0);

      await rig.drag(-(rest - pinned) + 100 - 150);
      await tester.pumpAndSettle();
      expect(rig.top, pinned);
      expect(rig.scrolled, closeTo(150, 1));
    });

    testWidgets('the header fades in over 380 ms once pinned', (tester) async {
      final rig = await SheetRig.open(
        tester,
        policy: policy,
        header: const SizedBox(height: 56),
      );
      Opacity header() => tester.widget<Opacity>(
        find.byKey(const ValueKey('attach-sheet-header')),
      );
      expect(header().opacity, 0);

      await rig.drag(-(rest - pinned) - 10);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 190));
      expect(header().opacity, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(header().opacity, 1);
    });

    testWidgets('left just below the top it stays there: no top snap', (
      tester,
    ) async {
      final rig = await SheetRig.open(tester, policy: policy);

      await rig.drag(-(rest - pinned) + 40);
      await tester.pumpAndSettle();

      expect(rig.top, closeTo(pinned + 40, 1));
    });

    testWidgets('a fling down from the top goes to the rest, not past it', (
      tester,
    ) async {
      final rig = await SheetRig.open(tester, policy: policy);
      rig.controller.expand().ignore();
      await tester.pumpAndSettle();

      await rig.fling(300, 3000);
      await tester.pumpAndSettle();
      expect(rig.closed, isFalse);
      expect(rig.top, closeTo(rest, 1));
    });

    testWidgets('left below the header line it stays where it is', (
      tester,
    ) async {
      final rig = await SheetRig.open(tester, policy: policy);

      await rig.drag(-120);
      await tester.pumpAndSettle();

      expect(rig.top, closeTo(rest - 120, 1));
    });

    testWidgets('the controller expands it', (tester) async {
      final rig = await SheetRig.open(tester, policy: policy);
      rig.controller.expand().ignore();
      await tester.pumpAndSettle();
      expect(rig.top, pinned);
    });
  });

  group('dismiss', () {
    testWidgets('a pull past 0.8 cm dismisses', (tester) async {
      final host = RecordingHost();
      final rig = await SheetRig.open(tester, policy: policy, host: host);

      await rig.drag(52);
      await tester.pumpAndSettle();

      expect(rig.outcome, const AttachOutcome.cancelled());
      expect(host.calls, ['opened', 'closed']);
      expect(find.byKey(const ValueKey('attach-sheet')), findsNothing);
    });

    testWidgets('a shorter pull springs back over 250 ms per 0.8 cm', (
      tester,
    ) async {
      final rig = await SheetRig.open(tester, policy: policy);

      await rig.drag(40);
      await tester.pump();
      expect(rig.top, closeTo(rest + 40, 1));
      // 250 * 40 / 50.39 is about 198 ms.
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.top, inExclusiveRange(rest, rest + 40));
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.top, closeTo(rest, 0.5));
      expect(rig.closed, isFalse);
    });

    // A fling needs a long gesture to be measured, so the page is first
    // scrolled 60 into its rows (the sheet pinned); the fling takes the page
    // back to its start and lowers the sheet the last 40, short of 0.8 cm.
    Future<SheetRig> scrolledIn(WidgetTester tester) async {
      final rig = await SheetRig.open(tester, policy: policy);
      await rig.drag(-(rest - pinned) - 60);
      await tester.pumpAndSettle();
      expect(rig.scrolled, closeTo(60, 1));
      return rig;
    }

    testWidgets('a fling at 3500 physical px/s dismisses', (tester) async {
      final rig = await scrolledIn(tester);
      rig.controller.collapse().ignore();
      await tester.pumpAndSettle();
      await rig.fling(100, 3600 / 3);
      await tester.pumpAndSettle();

      expect(rig.closed, isTrue);
    });

    testWidgets('a slower fling over a short pull springs back', (
      tester,
    ) async {
      final rig = await scrolledIn(tester);
      rig.controller.collapse().ignore();
      await tester.pumpAndSettle();
      await rig.fling(100, 3000 / 3);
      await tester.pumpAndSettle();

      expect(rig.closed, isFalse);
      expect(rig.top, closeTo(rest, 0.5));
    });

    testWidgets('closes in 250 ms off the bottom edge', (tester) async {
      final rig = await SheetRig.open(tester, policy: policy);

      await rig.tapAbove();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      expect(rig.top, inExclusiveRange(rest, 810));
      await tester.pump(const Duration(milliseconds: 130));
      await tester.pump();
      expect(rig.closed, isTrue);
    });

    testWidgets('a tap above dismisses unless a page turned it off', (
      tester,
    ) async {
      final rig = await SheetRig.open(tester, policy: policy);
      rig.controller.dismissesOnTapAbove = false;

      await rig.tapAbove();
      await tester.pumpAndSettle();
      expect(rig.closed, isFalse);

      rig.controller.dismissesOnTapAbove = true;
      await rig.tapAbove();
      await tester.pumpAndSettle();
      expect(rig.closed, isTrue);
    });
  });

  group('discard guard', () {
    testWidgets('a selection asks "Discard selection?" first', (tester) async {
      final rig = await SheetRig.open(tester, policy: policy);
      rig.selection.toggle(AttachItems.photo('p'));

      await rig.tapAbove();
      await tester.pumpAndSettle();
      expect(find.text('Discard selection?'), findsOneWidget);
      expectChromeText(tester, within: find.byType(AttachDiscardQuestion));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(rig.closed, isFalse);
      expect(find.text('Discard selection?'), findsNothing);

      await rig.tapAbove();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(rig.closed, isTrue);
    });

    testWidgets('a pull to dismiss with a selection springs back and asks', (
      tester,
    ) async {
      final rig = await SheetRig.open(tester, policy: policy);
      rig.selection.toggle(AttachItems.photo('p'));

      await rig.drag(80);
      await tester.pumpAndSettle();

      expect(rig.closed, isFalse);
      expect(rig.top, closeTo(rest, 0.5));
      expect(find.text('Discard selection?'), findsOneWidget);
    });

    testWidgets('Back asks too', (tester) async {
      final rig = await SheetRig.open(tester, policy: policy);
      rig.selection.toggle(AttachItems.photo('p'));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard selection?'), findsOneWidget);
      expect(rig.closed, isFalse);
    });
  });

  group('keyboard', () {
    testWidgets('a keyboard that was up returns 200 ms after close', (
      tester,
    ) async {
      final host = RecordingHost();
      final rig = await SheetRig.open(
        tester,
        policy: policy,
        host: host,
        opening: const AttachSheetOpening(keyboardWasUp: true),
      );

      await rig.tapAbove();
      while (!host.calls.contains('closed')) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(host.calls, ['opened', 'closed']);

      await tester.pump(const Duration(milliseconds: 199));
      expect(host.calls, isNot(contains('restoreKeyboard')));
      await tester.pump(const Duration(milliseconds: 1));
      expect(host.calls.last, 'restoreKeyboard');
    });

    testWidgets('no keyboard at open, none after', (tester) async {
      final host = RecordingHost();
      final rig = await SheetRig.open(tester, policy: policy, host: host);
      await rig.tapAbove();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(host.calls, ['opened', 'closed']);
    });
  });

  testWidgets('the bottom bar stays at the bottom and leaves with the sheet', (
    tester,
  ) async {
    final rig = await SheetRig.open(
      tester,
      policy: policy,
      bottomBar: const SizedBox(key: ValueKey('bar'), height: 60),
    );
    final bar = find.byKey(const ValueKey('bar'));
    expect(tester.getBottomLeft(bar).dy, closeTo(800, 0.01));

    await rig.drag(-100);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(bar).dy, closeTo(800, 0.01));

    await rig.drag(130);
    await tester.pump();
    expect(tester.getBottomLeft(bar).dy, closeTo(830, 1));
  });

  testWidgets('reduce motion opens and closes at once', (tester) async {
    final rig = await SheetRig.open(
      tester,
      policy: policy,
      speed: ChromeMotionSpeed.instant,
      settle: false,
    );
    await tester.pump();
    expect(rig.top, closeTo(rest, 0.5));
  });

  testWidgets('at its top the sheet fills the status bar band and meets the '
      "screen's top square, as the pack sheet's frame does", (tester) async {
    final rig = await SheetRig.open(tester, policy: policy);
    final band = find.byKey(const ValueKey('attach-sheet-band'));
    // At rest, far from the top: no band.
    expect(tester.getSize(band).height, 0);

    unawaited(rig.controller.expand());
    await tester.pumpAndSettle();
    expect(rig.top, 24);
    expect(tester.getRect(band), const Rect.fromLTWH(0, 0, 400, 24));
    final clip = tester.widget<ClipRRect>(
      find
          .descendant(
            of: find.byKey(const ValueKey('attach-sheet')),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    expect(clip.borderRadius, BorderRadius.zero);
  });
}

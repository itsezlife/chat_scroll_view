import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sheet_rig.dart';

void main() {
  const policy = AttachSheetPolicy.ios();
  const size = Size(390, 844);
  const padding = EdgeInsets.only(top: 47);
  // floor(844 * 0.2488) = 209; half the inset is (209 - 47) / 2 = 81.
  const rest = 209.0;
  const top = 47.0;

  Future<SheetRig> open(
    WidgetTester tester, {
    Size size = size,
    EdgeInsets padding = padding,
    EdgeInsets viewInsets = EdgeInsets.zero,
    AttachSheetOpening opening = const AttachSheetOpening(),
    bool settle = true,
  }) => SheetRig.open(
    tester,
    policy: policy,
    size: size,
    padding: padding,
    viewInsets: viewInsets,
    opening: opening,
    settle: settle,
  );

  group('geometry', () {
    testWidgets('rests at 0.2488 of the long side', (tester) async {
      final rig = await open(tester);
      expect(rig.top, rest);
    });

    testWidgets('fills the screen in landscape, with square corners', (
      tester,
    ) async {
      final rig = await open(
        tester,
        size: const Size(844, 390),
        padding: EdgeInsets.zero,
      );
      expect(rig.top, 0);
      final clip = tester.widget<ClipRRect>(
        find.descendant(
          of: find.byKey(const ValueKey('attach-sheet')),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(clip.borderRadius, BorderRadius.zero);
    });

    testWidgets('radius 38 and a 36 x 5 grabber 5 below the edge', (
      tester,
    ) async {
      final rig = await open(tester);
      final clip = tester.widget<ClipRRect>(
        find.descendant(
          of: find.byKey(const ValueKey('attach-sheet')),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(
        clip.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(38)),
      );
      final grabber = find.byKey(const ValueKey('attach-sheet-grabber'));
      expect(tester.getSize(grabber), const Size(36, 5));
      expect(tester.getTopLeft(grabber).dy, rig.top + 5);
      expect(tester.getCenter(grabber).dx, 195);
    });
  });

  group('open', () {
    testWidgets('the scrim fades in linearly to 25 % over 0.3 s', (
      tester,
    ) async {
      final rig = await open(tester, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(rig.dim, closeTo(0.125, 0.01));
      await tester.pump(const Duration(milliseconds: 150));
      expect(rig.dim, closeTo(0.25, 0.002));
    });

    testWidgets('slides up on a spring to its rest', (tester) async {
      final rig = await open(tester, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(rig.top, inExclusiveRange(rest, 844));
      await tester.pumpAndSettle();
      expect(rig.top, closeTo(rest, 0.5));
    });
  });

  group('pan release', () {
    testWidgets('past 60 down dismisses', (tester) async {
      final rig = await open(tester);
      await rig.drag(61);
      await tester.pumpAndSettle();
      expect(rig.closed, isTrue);
    });

    testWidgets('short of 60 returns over 0.3 s', (tester) async {
      final rig = await open(tester);
      await rig.drag(59);
      await tester.pump();
      expect(rig.top, closeTo(rest + 59, 1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(rig.top, inExclusiveRange(rest, rest + 59));
      await tester.pump(const Duration(milliseconds: 160));
      expect(rig.top, closeTo(rest, 0.5));
      expect(rig.closed, isFalse);
    });

    testWidgets('up past half the inset expands', (tester) async {
      final rig = await open(tester);
      await rig.drag(-90);
      await tester.pumpAndSettle();
      expect(rig.top, top);
    });

    testWidgets('up short of half the inset falls back', (tester) async {
      final rig = await open(tester);
      await rig.drag(-70);
      await tester.pumpAndSettle();
      expect(rig.top, closeTo(rest, 0.5));
    });

    testWidgets('from the top, down past half the inset collapses', (
      tester,
    ) async {
      final rig = await open(tester);
      rig.controller.expand().ignore();
      await tester.pumpAndSettle();
      expect(rig.top, top);

      await rig.drag(100);
      await tester.pumpAndSettle();
      expect(rig.top, closeTo(rest, 0.5));
      expect(rig.closed, isFalse);
    });

    testWidgets('from the top, a fling at over 1800 pt/s dismisses', (
      tester,
    ) async {
      final rig = await open(tester);
      rig.controller.expand().ignore();
      await tester.pumpAndSettle();

      await rig.fling(100, 2000);
      await tester.pumpAndSettle();
      expect(rig.closed, isTrue);
    });
  });

  testWidgets('the sheet does not follow drags while the keyboard is up', (
    tester,
  ) async {
    final rig = await open(
      tester,
      viewInsets: const EdgeInsets.only(bottom: 300),
    );
    await rig.drag(100);
    await tester.pumpAndSettle();
    expect(rig.top, rest);
    expect(rig.closed, isFalse);
  });

  testWidgets('a pan past 40 with a selection is cancelled into the question', (
    tester,
  ) async {
    final rig = await open(tester);
    rig.selection.toggle(AttachItems.photo('p'));

    await rig.drag(100);
    await tester.pumpAndSettle();

    expect(find.text('Cancel selection?'), findsOneWidget);
    expect(rig.top, greaterThan(rest), reason: 'stays where the pan left it');

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(rig.closed, isFalse);
    expect(rig.top, closeTo(rest, 0.5));

    await rig.tapAbove();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(rig.closed, isTrue);
  });

  testWidgets('a pan short of 40 with a selection asks nothing', (
    tester,
  ) async {
    final rig = await open(tester);
    rig.selection.toggle(AttachItems.photo('p'));

    await rig.drag(30);
    await tester.pumpAndSettle();

    expect(find.text('Cancel selection?'), findsNothing);
    expect(rig.top, closeTo(rest, 0.5));
  });

  testWidgets('a keyboard that was up is not brought back', (tester) async {
    final host = RecordingHost();
    final rig = await SheetRig.open(
      tester,
      policy: policy,
      size: size,
      padding: padding,
      host: host,
      opening: const AttachSheetOpening(keyboardWasUp: true),
    );
    await rig.tapAbove();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(host.calls, ['opened', 'closed']);
  });

  group('regular width', () {
    testWidgets('a 390 x 670 card above the attach button, scrim at 10 %', (
      tester,
    ) async {
      final rig = await open(
        tester,
        size: const Size(1024, 768),
        padding: EdgeInsets.zero,
        opening: const AttachSheetOpening(
          anchor: Rect.fromLTWH(20, 700, 44, 44),
        ),
      );
      final card = find.byKey(const ValueKey('attach-sheet-card'));
      expect(tester.getRect(card), const Rect.fromLTWH(28, 30, 390, 670));
      expect(rig.dim, closeTo(0.1, 0.002));
    });

    testWidgets('a tap outside the card dismisses it', (tester) async {
      final rig = await open(
        tester,
        size: const Size(1024, 768),
        padding: EdgeInsets.zero,
        opening: const AttachSheetOpening(
          anchor: Rect.fromLTWH(20, 700, 44, 44),
        ),
      );
      await tester.tapAt(const Offset(800, 300));
      await tester.pumpAndSettle();
      expect(rig.closed, isTrue);
    });
  });
}

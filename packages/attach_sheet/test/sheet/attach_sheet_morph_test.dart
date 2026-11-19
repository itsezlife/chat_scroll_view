import 'package:attach_sheet/attach_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sheet_rig.dart';

void main() {
  const anchor = Rect.fromLTWH(8, 790, 44, 44);
  const size = Size(390, 844);
  const padding = EdgeInsets.only(top: 47);
  const rest = 209.0;

  Rect sheet(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('attach-sheet')));

  test('the iOS morph is the reference springs', () {
    final morph = const AttachSheetPolicy.ios().morph!;
    expect(morph.openPosition.damping, 110);
    expect(morph.openPositionVelocity, 1.1);
    expect(morph.openBounds.damping, 110);
    expect(morph.openCorners.duration, const Duration(milliseconds: 200));
    expect(morph.openContent.duration, const Duration(milliseconds: 200));
    expect(morph.closePosition.damping, 110);
    expect(morph.closeBounds.damping, 124);
    expect(morph.closeCorners.damping, 124);
    expect(morph.closeContent.duration, const Duration(milliseconds: 120));
    expect(const AttachSheetPolicy.android().morph, isNull);
  });

  testWidgets('iOS grows out of the attach button and back into it', (
    tester,
  ) async {
    final rig = await SheetRig.open(
      tester,
      policy: const AttachSheetPolicy.ios(),
      size: size,
      padding: padding,
      opening: const AttachSheetOpening(anchor: anchor),
      settle: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final early = sheet(tester);
    expect(early.width, lessThan(200));
    expect(early.center.dx, lessThan(195));

    await tester.pump(const Duration(milliseconds: 84));
    final content = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('row-0')),
            matching: find.byType(Opacity),
          )
          .last,
    );
    expect(content.opacity, closeTo(0.5, 0.1));

    await tester.pumpAndSettle();
    expect(sheet(tester), const Rect.fromLTWH(0, rest, 390, 844 - rest));

    await rig.tapAbove();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(sheet(tester).width, lessThan(390));
    await tester.pumpAndSettle();
    expect(rig.closed, isTrue);
  });

  testWidgets('without a button rect iOS slides up from the bottom', (
    tester,
  ) async {
    await SheetRig.open(
      tester,
      policy: const AttachSheetPolicy.ios(),
      size: size,
      padding: padding,
      settle: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(sheet(tester).width, 390);
  });

  testWidgets('Android slides up even with a button rect', (tester) async {
    await SheetRig.open(
      tester,
      policy: const AttachSheetPolicy.android(),
      size: size,
      padding: padding,
      opening: const AttachSheetOpening(anchor: anchor),
      settle: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(sheet(tester).width, 390);
  });
}

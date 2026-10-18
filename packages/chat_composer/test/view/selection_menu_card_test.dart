import 'package:chat_composer/src/menu/selection_menu_card.dart';
import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_layout.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// How long the card takes to reshape itself into the overflow page.
///
/// **Seam:** `SelectionMenuCard` alone, given placements whose morph diagonal
/// falls on each side of the reference's 150 and 300 dp thresholds.
void main() {
  List<SelectionMenuItem> items(int count, [String prefix = 'item']) => [
    for (var i = 0; i < count; i++)
      SelectionMenuItem(
        kind: SelectionMenuItemKind.values[i % 8],
        label: '$prefix$i',
        onSelected: () {},
      ),
  ];

  Future<SelectionMenuCardState> pumpCard(
    WidgetTester tester, {
    required double mainWidth,
    required double overflowWidth,
    required int overflowCount,
    ChromeMotionData motion = ChromeMotionData.standard,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final placement = SelectionMenuLayout.place(
      viewport: const Rect.fromLTWH(0, 0, 800, 900),
      content: const Rect.fromLTWH(380, 500, 40, 20),
      main: Size(mainWidth, 48),
      overflowWidth: overflowWidth,
      overflowCount: overflowCount,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Stack(
            children: [
              SelectionMenuCard(
                placement: placement,
                mainItems: items(1, 'row'),
                mainWidths: [mainWidth - 56],
                overflowItems: items(overflowCount),
                itemStyle: const TextStyle(fontSize: 14),
                tokens: SelectionMenuTokens.fromPalette(
                  ChromePalette.forBrightness(Brightness.light),
                ),
                strings: ChromeStringsPresets.english.formatting,
                motion: motion,
                opacity: const AlwaysStoppedAnimation(1),
                onSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    return tester.state<SelectionMenuCardState>(find.byType(SelectionMenuCard));
  }

  // The time, in whole milliseconds, the morph runs for after a tap on More.
  Future<int> morphMilliseconds(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('selection_menu_back')));
    await tester.pump();
    final state = tester.state<SelectionMenuCardState>(
      find.byType(SelectionMenuCard),
    );
    var elapsed = 0;
    while (state.isAnimating && elapsed < 1000) {
      await tester.pump(const Duration(milliseconds: 1));
      elapsed++;
    }
    return elapsed;
  }

  testWidgets('a small morph is 200 ms', (tester) async {
    // Diagonal: hypot(20, 144), under 150.
    await pumpCard(
      tester,
      mainWidth: 120,
      overflowWidth: 100,
      overflowCount: 3,
    );

    expect(await morphMilliseconds(tester), closeTo(200, 2));
  });

  testWidgets('a mid-size morph is 250 ms', (tester) async {
    // Diagonal: hypot(100, 216), between 150 and 300.
    await pumpCard(
      tester,
      mainWidth: 300,
      overflowWidth: 200,
      overflowCount: 8,
    );

    expect(await morphMilliseconds(tester), closeTo(250, 2));
  });

  testWidgets('a large morph is 300 ms', (tester) async {
    // Diagonal: hypot(344, 216), over 300.
    await pumpCard(tester, mainWidth: 400, overflowWidth: 56, overflowCount: 8);

    expect(await morphMilliseconds(tester), closeTo(300, 2));
  });

  testWidgets('closing takes as long as opening', (tester) async {
    final state = await pumpCard(
      tester,
      mainWidth: 300,
      overflowWidth: 200,
      overflowCount: 8,
    );
    final opening = await morphMilliseconds(tester);
    expect(state.isOpen, isTrue);

    final closing = await morphMilliseconds(tester);

    expect(state.isOpen, isFalse);
    expect(closing, closeTo(opening, 2));
  });

  testWidgets('instant motion opens the page at once', (tester) async {
    final state = await pumpCard(
      tester,
      mainWidth: 300,
      overflowWidth: 200,
      overflowCount: 8,
      motion: const ChromeMotionData(speed: ChromeMotionSpeed.instant),
    );

    await tester.tap(find.byKey(const ValueKey<String>('selection_menu_back')));
    await tester.pump();
    await tester.pump();

    expect(state.isAnimating, isFalse);
    expect(tester.getSize(find.byType(SelectionMenuCard)).height, 264);
  });

  testWidgets('a card with no page has no More button', (tester) async {
    await pumpCard(tester, mainWidth: 200, overflowWidth: 0, overflowCount: 0);

    expect(
      find.byKey(const ValueKey<String>('selection_menu_back')),
      findsNothing,
    );
  });
}

import 'package:chat_composer/src/menu/selection_menu_card.dart';
import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_layout.dart';
import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/material_icons.dart';
import '../support/tolerant_golden_comparator.dart';

// Regenerate with `flutter test --update-goldens test/view/composer_selection_menu_golden_test.dart`.
// The cards are drawn on the pinned platform (macOS) with the test font, so
// they check geometry, mirroring and the token colours; rounded anti-aliased
// edges get a 1% pixel tolerance.
const _tolerance = 0.01;

const _cell = Size(360, 330);

List<SelectionMenuItem> _items(List<(SelectionMenuItemKind, String)> kinds) => [
  for (final (kind, label) in kinds)
    SelectionMenuItem(
      kind: kind,
      label: label,
      onSelected: () {},
      labelStyle: switch (kind) {
        SelectionMenuItemKind.italic => SelectionMenuLabelStyle.italic,
        SelectionMenuItemKind.mono => SelectionMenuLabelStyle.mono,
        SelectionMenuItemKind.strikethrough => SelectionMenuLabelStyle.strike,
        SelectionMenuItemKind.underline => SelectionMenuLabelStyle.underline,
        _ => SelectionMenuLabelStyle.plain,
      },
    ),
];

final _main = _items([
  (SelectionMenuItemKind.cut, 'Cut'),
  (SelectionMenuItemKind.copy, 'Copy'),
  (SelectionMenuItemKind.paste, 'Paste'),
]);

final _overflow = _items([
  (SelectionMenuItemKind.selectAll, 'Select all'),
  (SelectionMenuItemKind.quote, 'Quote'),
  (SelectionMenuItemKind.spoiler, 'Spoiler'),
  (SelectionMenuItemKind.bold, 'Bold'),
  (SelectionMenuItemKind.italic, 'Italic'),
  (SelectionMenuItemKind.mono, 'Mono'),
  (SelectionMenuItemKind.strikethrough, 'Strikethrough'),
  (SelectionMenuItemKind.underline, 'Underline'),
]);

// One cell: the card at rest on its row, or with the page open, placed by the
// same arithmetic the menu uses over a selection at [selection].
class _Cell extends StatefulWidget {
  const _Cell({
    required this.brightness,
    required this.direction,
    required this.open,
    required this.selection,
  });

  final Brightness brightness;
  final TextDirection direction;
  final bool open;
  final Rect selection;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  final _card = GlobalKey<SelectionMenuCardState>();

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      // Opens the page once the card is built.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _card.currentState?.open(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = widget.brightness;
    final direction = widget.direction;
    final selection = widget.selection;
    final palette = ChromePalette.forBrightness(brightness);
    final tokens = SelectionMenuTokens.fromPalette(palette);
    final style = TextStyle(
      inherit: false,
      color: tokens.text,
      fontSize: SelectionMenuMetrics.itemTextSize,
      fontWeight: FontWeight.w500,
    );
    double width(String label) => (TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: direction,
    )..layout()).width;
    final all = [..._main, ..._overflow];
    final widths = [for (final item in all) width(item.label)];
    final row = SelectionMenuLayout.mainRow(
      textWidths: widths,
      budget: SelectionMenuLayout.budget(_cell.width),
    );
    final mainWidths = [
      for (var i = 0; i < row.count; i++)
        SelectionMenuLayout.mainItemWidth(
          widths[i],
          first: i == 0,
          last: false,
        ),
    ];
    final placement = SelectionMenuLayout.place(
      viewport: Offset.zero & _cell,
      content: selection,
      main: Size(row.width, SelectionMenuMetrics.rowHeight),
      overflowWidth: SelectionMenuLayout.overflowWidth(
        widths.sublist(row.count),
      ),
      overflowCount: all.length - row.count,
      rtl: direction == TextDirection.rtl,
    );
    return SizedBox.fromSize(
      size: _cell,
      child: Directionality(
        textDirection: direction,
        child: ColoredBox(
          color: palette.surfaceDim,
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: selection,
                child: ColoredBox(color: palette.accent.withAlpha(0x40)),
              ),
              SelectionMenuCard(
                key: _card,
                placement: placement,
                mainItems: all.sublist(0, row.count),
                mainWidths: mainWidths,
                overflowItems: all.sublist(row.count),
                itemStyle: style,
                tokens: tokens,
                strings: ChromeStringsPresets.english.formatting,
                motion: ChromeMotionData.standard,
                opacity: const AlwaysStoppedAnimation(1),
                onSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    await loadMaterialIcons();
    goldenFileComparator = TolerantGoldenComparator(
      Uri.file('test/view/composer_selection_menu_golden_test.dart'),
      tolerance: _tolerance,
    );
  });

  Future<void> check(
    WidgetTester tester,
    String name, {
    required bool open,
    required Rect selection,
  }) async {
    await tester.binding.setSurfaceSize(
      Size(_cell.width * 2, _cell.height * 2),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: const ValueKey('golden'),
          child: Column(
            children: [
              for (final direction in TextDirection.values)
                Row(
                  children: [
                    for (final brightness in Brightness.values)
                      _Cell(
                        brightness: brightness,
                        direction: direction,
                        open: open,
                        selection: selection,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await expectLater(
      find.byKey(const ValueKey('golden')),
      matchesGoldenFile('../goldens/selection_menu_$name.png'),
    );
  }

  testWidgets('the main row, light and dark, LTR and RTL', (tester) async {
    await check(
      tester,
      'row',
      open: false,
      selection: const Rect.fromLTWH(140, 200, 80, 20),
    );
  });

  testWidgets('the page open upwards, light and dark, LTR and RTL', (
    tester,
  ) async {
    await check(
      tester,
      'page_up',
      open: true,
      selection: const Rect.fromLTWH(140, 280, 80, 20),
    );
  });

  testWidgets('the page open downwards, light and dark, LTR and RTL', (
    tester,
  ) async {
    await check(
      tester,
      'page_down',
      open: true,
      selection: const Rect.fromLTWH(140, 20, 80, 20),
    );
  });
}

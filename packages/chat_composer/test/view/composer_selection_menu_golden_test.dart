import 'dart:math' as math;

import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_overflow.dart';
import 'package:chat_composer/src/menu/selection_menu_pages.dart';
import 'package:chat_composer/src/menu/selection_menu_position.dart';
import 'package:chat_composer/src/menu/selection_menu_shell.dart';
import 'package:chat_composer/src/menu/selection_menu_swipe_back.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/material_icons.dart';
import '../support/tolerant_golden_comparator.dart';

// Regenerate with `flutter test --update-goldens test/view/composer_selection_menu_golden_test.dart`.
// The cards are drawn on the pinned platform (macOS) with the test font, so
// they check geometry, mirroring and the token colours; rounded anti-aliased
// edges and shadows get a 1% pixel tolerance. The test font draws every glyph
// as a square of the font size, so these cards are far wider than a real
// font's; what they pin is the rule: rows 48 dp, the page as wide as its
// widest label, four rows and the peek of a fifth, a 48 dp Back row.
const _tolerance = 0.01;

const _cell = Size(360, 400);

SelectionMenuItem _item(
  SelectionMenuItemKind kind,
  String label, {
  SelectionMenuLabelStyle style = SelectionMenuLabelStyle.plain,
  bool enabled = true,
}) => SelectionMenuItem(
  kind: kind,
  label: label,
  labelStyle: style,
  enabled: enabled,
  onSelected: () {},
);

final _clipboard = [
  _item(SelectionMenuItemKind.cut, 'Cut'),
  _item(SelectionMenuItemKind.copy, 'Copy'),
  _item(SelectionMenuItemKind.paste, 'Paste'),
  _item(SelectionMenuItemKind.selectAll, 'All'),
];

// The formatting page of a composer with lists on, over a selection that can
// hold most things: Strikethrough and Spoiler cannot apply, and are greyed.
final _formatting = [
  _item(
    SelectionMenuItemKind.bold,
    'Bold',
    style: SelectionMenuLabelStyle.bold,
  ),
  _item(
    SelectionMenuItemKind.italic,
    'Italic',
    style: SelectionMenuLabelStyle.italic,
  ),
  _item(
    SelectionMenuItemKind.underline,
    'Underline',
    style: SelectionMenuLabelStyle.underline,
  ),
  _item(
    SelectionMenuItemKind.strikethrough,
    'Strikethrough',
    style: SelectionMenuLabelStyle.strike,
    enabled: false,
  ),
  _item(
    SelectionMenuItemKind.mono,
    'Monospace',
    style: SelectionMenuLabelStyle.mono,
  ),
  _item(SelectionMenuItemKind.spoiler, 'Spoiler', enabled: false),
  _item(SelectionMenuItemKind.quote, 'Quote'),
  _item(SelectionMenuItemKind.codeBlock, 'Code block'),
  _item(SelectionMenuItemKind.createLink, 'Create link'),
  _item(SelectionMenuItemKind.bulletList, 'Bullet list'),
  _item(SelectionMenuItemKind.numberedList, 'Numbered list'),
  _item(SelectionMenuItemKind.clearFormatting, 'Clear formatting'),
];

// One cell: the card on its row, or with the More page open, placed by the
// same arithmetic the menu uses over a selection at [selection].
class _Cell extends StatelessWidget {
  const _Cell({
    required this.brightness,
    required this.direction,
    required this.open,
    required this.selection,
    required this.cell,
    required this.formatting,
    required this.clipboard,
    required this.backLabel,
  });

  final Brightness brightness;
  final TextDirection direction;
  final bool open;
  final Rect selection;
  final Size cell;
  final List<SelectionMenuItem> formatting;
  final List<SelectionMenuItem> clipboard;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final palette = ChromePalette.forBrightness(brightness);
    final tokens = SelectionMenuTokens.fromPalette(palette);
    final theme = ThemeData(brightness: brightness);
    final label = selectionMenuLabelStyle(theme, tokens);
    final backStyle = selectionMenuBackStyle(theme, tokens);
    final placement = computeSelectionMenuPlacement(
      screen: cell,
      safe: EdgeInsets.zero,
      keyboardInset: 0,
      anchors: TextSelectionToolbarAnchors(
        primaryAnchor: Offset(selection.center.dx, selection.top),
        secondaryAnchor: Offset(selection.center.dx, selection.bottom),
      ),
    );
    final split = splitSelectionMenuRow(
      labels: [for (final item in clipboard) item.label],
      style: label,
      maxWidth: placement.maxWidth,
      moreFollows: formatting.isNotEmpty,
      textDirection: direction,
    );
    final page = [...clipboard.skip(split.count), ...formatting];
    final pageSize = sizeSelectionMenuPage(
      items: page,
      style: label,
      backLabel: backLabel,
      backStyle: backStyle,
      maxWidth: placement.pageMaxWidth,
      maxHeight: placement.maxHeight,
      textScaler: TextScaler.noScaling,
      textDirection: direction,
    );
    return SizedBox.fromSize(
      size: cell,
      child: Directionality(
        textDirection: direction,
        child: Theme(
          data: theme,
          child: ColoredBox(
            color: palette.surfaceDim,
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: selection,
                  child: ColoredBox(color: palette.accent.withAlpha(0x40)),
                ),
                SelectionMenuPositioned(
                  placement: placement,
                  referenceWidth: math.max(split.rowWidth, pageSize.width),
                  child: SelectionMenuCard(
                    tokens: tokens,
                    maxWidth: placement.pageMaxWidth,
                    child: SelectionMenuSwipeBack(
                      controller: SelectionMenuPageController(),
                      initialProgress: open ? 1 : 0,
                      pageColor: tokens.background,
                      dim: tokens.pageDim,
                      duration: Duration.zero,
                      curve: Curves.linear,
                      borderRadius: SelectionMenuTokens.cornerRadius,
                      root: SelectionMenuRootPage(
                        items: clipboard.sublist(0, split.count),
                        tokens: tokens,
                        labelStyle: label,
                        moreLabel: 'More',
                        maxWidth: placement.maxWidth,
                        onSelected: (_) {},
                        onOpenMore: split.hasMore ? () {} : null,
                      ),
                      foreground: SelectionMenuMorePage(
                        items: page,
                        tokens: tokens,
                        labelStyle: label,
                        backStyle: backStyle,
                        backLabel: backLabel,
                        backPlacement: placement.fitsAbove
                            ? SelectionMenuBackPlacement.bottom
                            : SelectionMenuBackPlacement.top,
                        size: pageSize,
                        onSelected: (_) {},
                        onBack: () {},
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
    Size cell = _cell,
    List<SelectionMenuItem>? formatting,
    List<SelectionMenuItem>? clipboard,
    String backLabel = 'Back',
  }) async {
    await tester.binding.setSurfaceSize(Size(cell.width * 2, cell.height * 2));
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
                        cell: cell,
                        formatting: formatting ?? _formatting,
                        clipboard: clipboard ?? _clipboard,
                        backLabel: backLabel,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byKey(const ValueKey('golden')),
      matchesGoldenFile('../goldens/selection_menu_$name.png'),
    );
  }

  testWidgets('the main row with its More button, light and dark, LTR and '
      'RTL', (tester) async {
    await check(
      tester,
      'row',
      open: false,
      selection: const Rect.fromLTWH(140, 300, 80, 20),
    );
  });

  testWidgets('the main row of a narrow screen: what does not fit is on the '
      'page, light and dark, LTR and RTL', (tester) async {
    await check(
      tester,
      'row_narrow',
      open: false,
      cell: const Size(260, 400),
      selection: const Rect.fromLTWH(90, 300, 80, 20),
    );
  });

  testWidgets('the page above the selection: Back at the bottom, light and '
      'dark, LTR and RTL', (tester) async {
    await check(
      tester,
      'page_up',
      open: true,
      selection: const Rect.fromLTWH(140, 350, 80, 20),
    );
  });

  testWidgets('the page below the selection: Back at the top, light and dark, '
      'LTR and RTL', (tester) async {
    await check(
      tester,
      'page_down',
      open: true,
      selection: const Rect.fromLTWH(140, 20, 80, 20),
    );
  });

  testWidgets('the page of a narrow screen: the overflowed clipboard rows '
      'above the formatting, light and dark, LTR and RTL', (tester) async {
    await check(
      tester,
      'page_overflow',
      open: true,
      cell: const Size(260, 400),
      selection: const Rect.fromLTWH(90, 350, 80, 20),
      formatting: [
        _item(
          SelectionMenuItemKind.bold,
          'Bold',
          style: SelectionMenuLabelStyle.bold,
        ),
        _item(SelectionMenuItemKind.bulletList, 'Bullet list'),
        _item(SelectionMenuItemKind.numberedList, 'Numbered list'),
      ],
    );
  });

  // The two screenshots of the report: the English row, and the Russian page
  // whose labels were ellipsized under the fixed 150 dp width.
  testWidgets('the row of "Cut Copy Paste" and a More button, light and dark, '
      'LTR and RTL', (tester) async {
    await check(
      tester,
      'row_english',
      open: false,
      cell: const Size(400, 400),
      selection: const Rect.fromLTWH(140, 300, 80, 20),
      formatting: _formatting,
    );
  });

  testWidgets('the Russian page: the long labels whole, four rows and a half, '
      'light and dark, LTR and RTL', (tester) async {
    await check(
      tester,
      'page_russian',
      open: true,
      cell: const Size(480, 400),
      selection: const Rect.fromLTWH(180, 350, 80, 20),
      backLabel: 'Назад',
      clipboard: [
        _item(SelectionMenuItemKind.cut, 'Вырезать'),
        _item(SelectionMenuItemKind.copy, 'Копировать'),
        _item(SelectionMenuItemKind.paste, 'Вставить'),
        _item(SelectionMenuItemKind.pastePlain, 'Вставить без форматирования'),
        _item(SelectionMenuItemKind.selectAll, 'Выделить всё'),
      ],
      formatting: [
        _item(
          SelectionMenuItemKind.bold,
          'Жирный',
          style: SelectionMenuLabelStyle.bold,
        ),
        _item(
          SelectionMenuItemKind.italic,
          'Курсив',
          style: SelectionMenuLabelStyle.italic,
        ),
        _item(
          SelectionMenuItemKind.underline,
          'Подчёркнутый',
          style: SelectionMenuLabelStyle.underline,
        ),
        _item(
          SelectionMenuItemKind.strikethrough,
          'Зачёркнутый',
          style: SelectionMenuLabelStyle.strike,
        ),
        _item(
          SelectionMenuItemKind.mono,
          'Моноширинный',
          style: SelectionMenuLabelStyle.mono,
        ),
        _item(SelectionMenuItemKind.spoiler, 'Спойлер'),
      ],
    );
  });
}

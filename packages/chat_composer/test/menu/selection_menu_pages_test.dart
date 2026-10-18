/// The menu's two pages and the controls they are made of: the 42 dp main row
/// with its More button, and the 150 dp More page with its tiles, list
/// markers and Back tile.
///
/// **Seam:** `SelectionMenuRootPage` and `SelectionMenuMorePage` inside a
/// `SelectionMenuCard`, read through laid-out rects, the text styles they draw
/// and the semantics tree.
library;

import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_pages.dart';
import 'package:chat_composer/src/menu/selection_menu_shell.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tokens = SelectionMenuTokens.fromPalette(const ChromePalette.light());
  final tapped = <SelectionMenuItemKind>[];
  var backs = 0;
  var opened = 0;

  setUp(() {
    tapped.clear();
    backs = 0;
    opened = 0;
  });

  SelectionMenuItem item(
    SelectionMenuItemKind kind,
    String label, {
    bool enabled = true,
    bool selected = false,
    SelectionMenuLabelStyle style = SelectionMenuLabelStyle.plain,
  }) => SelectionMenuItem(
    kind: kind,
    label: label,
    enabled: enabled,
    selected: selected,
    labelStyle: style,
    onSelected: () => tapped.add(kind),
  );

  TextStyle labelStyle(BuildContext context) =>
      selectionMenuLabelStyle(Theme.of(context), tokens);

  Future<void> pumpPage(
    WidgetTester tester,
    Widget Function(BuildContext context) page, {
    Brightness brightness = Brightness.light,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Align(
        alignment: Alignment.topLeft,
        child: Builder(
          builder: (context) => SelectionMenuCard(
            tokens: tokens,
            maxWidth: 400,
            child: page(context),
          ),
        ),
      ),
    ),
  );

  Widget root(
    BuildContext context,
    List<SelectionMenuItem> items, {
    bool more = true,
  }) => SelectionMenuRootPage(
    items: items,
    tokens: tokens,
    labelStyle: labelStyle(context),
    moreLabel: 'More',
    onSelected: (item) => tapped.add(item.kind),
    onOpenMore: more ? () => opened++ : null,
  );

  Widget more(
    BuildContext context,
    List<SelectionMenuItem> items, {
    SelectionMenuBackPlacement placement = SelectionMenuBackPlacement.bottom,
    double? maxHeight,
  }) => SizedBox(
    width: 150,
    child: SelectionMenuMorePage(
      items: items,
      tokens: tokens,
      labelStyle: labelStyle(context),
      backLabel: 'Back',
      backPlacement: placement,
      onSelected: (item) => tapped.add(item.kind),
      onBack: () => backs++,
      maxHeight: maxHeight,
    ),
  );

  List<SelectionMenuItem> formatting(int count) {
    const kinds = [
      SelectionMenuItemKind.bold,
      SelectionMenuItemKind.italic,
      SelectionMenuItemKind.underline,
      SelectionMenuItemKind.strikethrough,
      SelectionMenuItemKind.mono,
      SelectionMenuItemKind.spoiler,
      SelectionMenuItemKind.quote,
      SelectionMenuItemKind.codeBlock,
      SelectionMenuItemKind.createLink,
    ];
    return [for (final kind in kinds.take(count)) item(kind, kind.name)];
  }

  final cut = item(SelectionMenuItemKind.cut, 'Cut');
  final copy = item(SelectionMenuItemKind.copy, 'Copy');

  group('the main row', () {
    testWidgets('is 42 dp tall', (tester) async {
      await pumpPage(tester, (c) => root(c, [cut, copy]));

      expect(tester.getSize(find.byType(SelectionMenuRootPage)).height, 42);
      expect(
        tester.getSize(find.byKey(const ValueKey(SelectionMenuItemKind.cut))),
        isA<Size>().having((s) => s.height, 'height', 42),
      );
    });

    testWidgets('a button is its label and 12 dp each side', (tester) async {
      await pumpPage(tester, (c) => root(c, [cut, copy]));

      final label = tester.getSize(find.text('Copy')).width;
      expect(
        tester
            .getSize(find.byKey(const ValueKey(SelectionMenuItemKind.copy)))
            .width,
        label + 24,
      );
      // The buttons sit flush: Copy starts where Cut ends.
      expect(
        tester
            .getRect(find.byKey(const ValueKey(SelectionMenuItemKind.cut)))
            .right,
        tester
            .getRect(find.byKey(const ValueKey(SelectionMenuItemKind.copy)))
            .left,
      );
    });

    testWidgets(
      'the label is the theme\'s body-large at 16, in the text token',
      (tester) async {
        await pumpPage(tester, (c) => root(c, [copy]));

        final style = tester
            .widget<DefaultTextStyle>(
              find
                  .ancestor(
                    of: find.text('Copy'),
                    matching: find.byType(DefaultTextStyle),
                  )
                  .first,
            )
            .style;
        final theme = Theme.of(tester.element(find.text('Copy')));
        expect(style.fontSize, 16);
        expect(style.fontWeight, theme.textTheme.bodyLarge!.fontWeight);
        expect(style.height, theme.textTheme.bodyLarge!.height);
        expect(style.color, tokens.text);
      },
    );

    testWidgets(
      'the More button is 46 by 42 with a 24 dp more_vert and no tooltip',
      (tester) async {
        await pumpPage(tester, (c) => root(c, [cut]));

        final button = find.byKey(SelectionMenuRootPage.moreKey);
        expect(tester.getSize(button), const Size(46, 42));
        final icon = tester.widget<Icon>(find.byIcon(Icons.more_vert));
        expect(icon.size, 24);
        expect(find.byType(Tooltip), findsNothing);
        // 4 dp are kept from the card's end.
        expect(
          tester.getRect(find.byType(IconButton)).right,
          tester.getRect(button).right - 4,
        );
      },
    );

    testWidgets('there is no More button without a page to open', (
      tester,
    ) async {
      await pumpPage(tester, (c) => root(c, [cut], more: false));

      expect(find.byKey(SelectionMenuRootPage.moreKey), findsNothing);
    });

    testWidgets('a tap runs the item; the More button opens the page', (
      tester,
    ) async {
      await pumpPage(tester, (c) => root(c, [cut, copy]));

      await tester.tap(find.text('Copy'));
      await tester.tap(find.byKey(SelectionMenuRootPage.moreKey));

      expect(tapped, [SelectionMenuItemKind.copy]);
      expect(opened, 1);
    });

    testWidgets('a disabled item takes no tap and is drawn at 0.38', (
      tester,
    ) async {
      await pumpPage(
        tester,
        (c) =>
            root(c, [item(SelectionMenuItemKind.cut, 'Cut', enabled: false)]),
      );

      await tester.tap(find.text('Cut'));

      expect(tapped, isEmpty);
      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(button.onPressed, isNull);
      final foreground = button.style!.foregroundColor!.resolve({
        WidgetState.disabled,
      });
      expect(foreground, tokens.text.withValues(alpha: 0.38));
    });

    testWidgets('items are spoken with their label, selected and enabled', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpPage(
        tester,
        (c) => root(c, [
          item(SelectionMenuItemKind.bold, 'Bold', selected: true),
          item(SelectionMenuItemKind.cut, 'Cut', enabled: false),
        ]),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('Bold')),
        isSemantics(
          label: 'Bold',
          isButton: true,
          isSelected: true,
          isEnabled: true,
          hasEnabledState: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Cut')),
        isSemantics(
          label: 'Cut',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasSelectedState: true,
        ),
      );
      expect(find.bySemanticsLabel('More'), findsOneWidget);
      handle.dispose();
    });
  });

  group('the More page', () {
    testWidgets('a tile is 42 dp tall with 18 dp each side', (tester) async {
      await pumpPage(tester, (c) => more(c, formatting(2)));

      final tile = find.byKey(const ValueKey(SelectionMenuItemKind.bold));
      expect(tester.getSize(tile), const Size(150, 42));
      expect(
        tester.getRect(find.text('bold')).left - tester.getRect(tile).left,
        18,
      );
    });

    testWidgets('the Back tile has its arrow at 18 and its label at 54', (
      tester,
    ) async {
      await pumpPage(tester, (c) => more(c, formatting(2)));

      final back = tester.getRect(find.byKey(SelectionMenuMorePage.backKey));
      expect(back.height, 42);
      expect(
        tester.getRect(find.byIcon(Icons.arrow_back)).left - back.left,
        18,
      );
      expect(tester.getRect(find.text('Back')).left - back.left, 54);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('Back sits under the list when the card is above', (
      tester,
    ) async {
      await pumpPage(tester, (c) => more(c, formatting(2)));

      final list = tester.getRect(
        find.byKey(const ValueKey(SelectionMenuItemKind.italic)),
      );
      final back = tester.getRect(find.byKey(SelectionMenuMorePage.backKey));
      expect(back.top, greaterThan(list.bottom));
    });

    testWidgets('and above it when the card is below', (tester) async {
      await pumpPage(
        tester,
        (c) =>
            more(c, formatting(2), placement: SelectionMenuBackPlacement.top),
      );

      final first = tester.getRect(
        find.byKey(const ValueKey(SelectionMenuItemKind.bold)),
      );
      final back = tester.getRect(find.byKey(SelectionMenuMorePage.backKey));
      expect(back.bottom, lessThan(first.top));
      expect(back.top, 0);
    });

    testWidgets(
      'one 1 dp divider in the outline token separates list and Back',
      (tester) async {
        await pumpPage(tester, (c) => more(c, formatting(2)));

        final divider = find.byType(Divider);
        expect(divider, findsOneWidget);
        expect(tester.getSize(divider).height, 1);
        final widget = tester.widget<Divider>(divider);
        expect(widget.color, tokens.divider);
        expect(widget.thickness, 1);
        final list = tester.getRect(
          find.byKey(const ValueKey(SelectionMenuItemKind.italic)),
        );
        expect(tester.getRect(divider).top, list.bottom);
      },
    );

    testWidgets('is the list, the divider and Back tall: 43 + 42 per item', (
      tester,
    ) async {
      await pumpPage(tester, (c) => more(c, formatting(5), maxHeight: 320));

      // 42 (Back) + 1 (divider) + 5 * 42.
      expect(tester.getSize(find.byType(SelectionMenuMorePage)).height, 253);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('with nine items it is 313 tall and the list scrolls', (
      tester,
    ) async {
      await pumpPage(tester, (c) => more(c, formatting(9), maxHeight: 320));

      // 43 + (320 - 50).
      expect(tester.getSize(find.byType(SelectionMenuMorePage)).height, 313);
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('the room of a cramped side limits the list', (tester) async {
      await pumpPage(tester, (c) => more(c, formatting(9), maxHeight: 140));

      // 43 + (140 - 50).
      expect(tester.getSize(find.byType(SelectionMenuMorePage)).height, 133);
    });

    testWidgets('a tap runs the item, and Back goes back', (tester) async {
      await pumpPage(tester, (c) => more(c, formatting(2)));

      await tester.tap(find.text('italic'));
      await tester.tap(find.text('Back'));

      expect(tapped, [SelectionMenuItemKind.italic]);
      expect(backs, 1);
    });

    testWidgets('a disabled tile takes no tap and its label is at 0.38', (
      tester,
    ) async {
      await pumpPage(
        tester,
        (c) =>
            more(c, [item(SelectionMenuItemKind.bold, 'Bold', enabled: false)]),
      );

      await tester.tap(find.text('Bold'));

      expect(tapped, isEmpty);
      expect(
        tester.widget<Text>(find.text('Bold')).style!.color,
        tokens.text.withValues(alpha: 0.38),
      );
    });

    testWidgets('formatting rows preview their own effect', (tester) async {
      await pumpPage(
        tester,
        (c) => more(c, [
          item(
            SelectionMenuItemKind.bold,
            'Bold',
            style: SelectionMenuLabelStyle.bold,
          ),
          item(
            SelectionMenuItemKind.italic,
            'Italic',
            style: SelectionMenuLabelStyle.italic,
          ),
          item(
            SelectionMenuItemKind.underline,
            'Underline',
            style: SelectionMenuLabelStyle.underline,
          ),
          item(
            SelectionMenuItemKind.strikethrough,
            'Strike',
            style: SelectionMenuLabelStyle.strike,
          ),
          item(
            SelectionMenuItemKind.mono,
            'Mono',
            style: SelectionMenuLabelStyle.mono,
          ),
          item(SelectionMenuItemKind.spoiler, 'Spoiler'),
        ]),
      );

      TextStyle styleOf(String label) =>
          tester.widget<Text>(find.text(label)).style!;
      expect(styleOf('Bold').fontWeight, FontWeight.bold);
      expect(styleOf('Italic').fontStyle, FontStyle.italic);
      expect(styleOf('Underline').decoration, TextDecoration.underline);
      expect(styleOf('Strike').decoration, TextDecoration.lineThrough);
      expect(styleOf('Mono').fontFamily, 'monospace');
      expect(styleOf('Spoiler').fontWeight, isNot(FontWeight.bold));
      expect(styleOf('Spoiler').decoration, anyOf(isNull, TextDecoration.none));
    });

    testWidgets('list rows carry a bullet or a number in a 16 dp column', (
      tester,
    ) async {
      await pumpPage(
        tester,
        (c) => more(c, [
          item(SelectionMenuItemKind.bulletList, 'Bullet list'),
          item(SelectionMenuItemKind.numberedList, 'Numbered list'),
        ]),
      );

      expect(find.text('•'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      final tile = tester.getRect(
        find.byKey(const ValueKey(SelectionMenuItemKind.bulletList)),
      );
      final marker = tester.getRect(find.text('•'));
      final column = tester.getRect(
        find
            .ancestor(of: find.text('•'), matching: find.byType(SizedBox))
            .first,
      );
      expect(column.width, 16);
      expect(column.left - tile.left, 18);
      expect(marker.left, column.left);
      // 8 dp between the column and the label, the same for both rows.
      expect(tester.getRect(find.text('Bullet list')).left, column.right + 8);
      expect(
        tester.getRect(find.text('Numbered list')).left,
        tester.getRect(find.text('Bullet list')).left,
      );
    });

    testWidgets('tiles are spoken with their label and selected state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpPage(
        tester,
        (c) => more(c, [
          item(SelectionMenuItemKind.bold, 'Bold', selected: true),
          item(SelectionMenuItemKind.bulletList, 'Bullet list'),
        ]),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('Bold')),
        isSemantics(
          label: 'Bold',
          isButton: true,
          isSelected: true,
          isEnabled: true,
          hasEnabledState: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      // The marker is decoration: the row is spoken by its label alone.
      expect(find.bySemanticsLabel('Bullet list'), findsOneWidget);
      expect(find.bySemanticsLabel('•'), findsNothing);
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      handle.dispose();
    });
  });

  testWidgets(
    'the card is a Material of elevation 3, radius 12 and the tokens',
    (tester) async {
      await pumpPage(tester, (c) => root(c, [cut]));

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(SelectionMenuCard),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.elevation, 3);
      expect(material.color, tokens.background);
      expect(material.shadowColor, tokens.shadow);
      expect(
        material.borderRadius,
        const BorderRadius.all(Radius.circular(12)),
      );
      expect(material.clipBehavior, Clip.antiAlias);
    },
  );

  testWidgets('the card hugs its page', (tester) async {
    await pumpPage(tester, (c) => root(c, [cut]));

    final card = tester.getSize(find.byType(Material).first);
    final page = tester.getSize(find.byType(SelectionMenuRootPage));
    expect(card, page);
  });
}

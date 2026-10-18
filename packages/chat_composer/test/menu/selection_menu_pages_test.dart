/// The menu's two pages and the controls they are made of, at the sizes of
/// Telegram's floating toolbar: the 48 dp main row with its 56 dp More button,
/// and the More page with 42 dp tiles, list markers, a list that shows four
/// rows and a half, and a 48 dp Back row.
///
/// **Seam:** `SelectionMenuRootPage` and `SelectionMenuMorePage` inside a
/// `SelectionMenuCard`, read through laid-out rects, the text styles they draw
/// and the semantics tree.
library;

import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_overflow.dart';
import 'package:chat_composer/src/menu/selection_menu_pages.dart';
import 'package:chat_composer/src/menu/selection_menu_shell.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  TextStyle backStyle(BuildContext context) =>
      selectionMenuBackStyle(Theme.of(context), tokens);

  Future<void> pumpPage(
    WidgetTester tester,
    Widget Function(BuildContext context) page, {
    Brightness brightness = Brightness.light,
    double devicePixelRatio = 1,
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) =>
            Directionality(textDirection: textDirection, child: child!),
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
  }

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
    double maxWidth = 400,
  }) => SelectionMenuMorePage(
    items: items,
    tokens: tokens,
    labelStyle: labelStyle(context),
    backStyle: backStyle(context),
    backLabel: 'Back',
    backPlacement: placement,
    onSelected: (item) => tapped.add(item.kind),
    onBack: () => backs++,
    size: sizeSelectionMenuPage(
      items: items,
      style: labelStyle(context),
      backLabel: 'Back',
      backStyle: backStyle(context),
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
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

  Finder key(SelectionMenuItemKind kind) => find.byKey(ValueKey(kind));

  // The menu measures a label up to the next whole pixel, so a width built
  // from the drawn label is at most one pixel short.
  Matcher wholePixelAbove(double width) => inInclusiveRange(width, width + 1);
  Rect cardRect(WidgetTester tester) =>
      tester.getRect(find.byType(Material).first);

  final cut = item(SelectionMenuItemKind.cut, 'Cut');
  final copy = item(SelectionMenuItemKind.copy, 'Copy');
  final paste = item(SelectionMenuItemKind.paste, 'Paste');

  group('the main row', () {
    testWidgets('is 48 dp tall, and so is a button', (tester) async {
      await pumpPage(tester, (c) => root(c, [cut, copy]));

      expect(tester.getSize(find.byType(SelectionMenuRootPage)).height, 48);
      expect(tester.getSize(key(SelectionMenuItemKind.cut)).height, 48);
    });

    testWidgets('a button is its label and 16 dp each side', (tester) async {
      await pumpPage(tester, (c) => root(c, [cut, copy, paste]));

      final label = tester.getSize(find.text('Copy')).width;
      final button = tester.getRect(key(SelectionMenuItemKind.copy));
      expect(button.width, wholePixelAbove(label + 32));
      expect(tester.getRect(find.text('Copy')).left - button.left, 16);
      // The buttons sit flush: Copy starts where Cut ends.
      expect(tester.getRect(key(SelectionMenuItemKind.cut)).right, button.left);
    });

    testWidgets('the first button keeps 24 dp at its start', (tester) async {
      await pumpPage(tester, (c) => root(c, [cut, copy]));

      final button = tester.getRect(key(SelectionMenuItemKind.cut));
      expect(tester.getRect(find.text('Cut')).left - button.left, 24);
      expect(
        button.width,
        wholePixelAbove(tester.getSize(find.text('Cut')).width + 24 + 16),
      );
    });

    testWidgets('the last button keeps 24 dp at its end while no More button '
        'follows', (tester) async {
      await pumpPage(tester, (c) => root(c, [cut, copy], more: false));

      final button = tester.getRect(key(SelectionMenuItemKind.copy));
      expect(button.right - tester.getRect(find.text('Copy')).right, 24);
      expect(
        button.width,
        wholePixelAbove(16 + tester.getSize(find.text('Copy')).width + 24),
      );
    });

    testWidgets('a button is 48 dp wide at least', (tester) async {
      await pumpPage(
        tester,
        (c) => root(c, [cut, item(SelectionMenuItemKind.copy, 'I'), paste]),
      );

      expect(tester.getSize(key(SelectionMenuItemKind.copy)).width, 48);
    });

    testWidgets('the label is 14 dp medium with no letter spacing, in the '
        'text token', (tester) async {
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
      expect(style.fontSize, 14);
      expect(style.fontWeight, FontWeight.w500);
      expect(style.letterSpacing, 0);
      expect(style.color, tokens.text);
    });

    testWidgets('the More button is 56 by 48, flush, with a 24 dp more_vert, a '
        'no tooltip', (tester) async {
      await pumpPage(tester, (c) => root(c, [cut]));

      final button = find.byKey(SelectionMenuRootPage.moreKey);
      expect(tester.getSize(button), const Size(56, 48));
      // Flush with the card's end: the row is the buttons and this.
      expect(tester.getRect(button).right, cardRect(tester).right);
      expect(tester.widget<Icon>(find.byIcon(Icons.more_vert)).size, 24);
      expect(
        tester.getCenter(find.byIcon(Icons.more_vert)),
        tester.getCenter(button),
      );
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('pressing the More button washes it in the icon colour at the '
        'Material pressed opacity', (tester) async {
      await pumpPage(tester, (c) => root(c, [cut, copy]));
      final ink = find
          .ancestor(
            of: find.byKey(SelectionMenuRootPage.moreKey),
            matching: find.byWidgetPredicate(
              (widget) => widget.runtimeType.toString() == '_InkFeatures',
            ),
          )
          .first;

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(SelectionMenuRootPage.moreKey)),
      );
      // The press shows after the tap-down delay, then fades in over the next
      // frames.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // M3's pressed state layer is 10% of the foreground; a theme's own
      // splash and highlight are transparent, which left the button dead.
      expect(
        tester.renderObject(ink),
        paints..something((method, arguments) {
          final paint = arguments.whereType<Paint>().firstOrNull;
          if (paint == null) return false;
          // Ink quantizes the alpha to a byte.
          final drawn = paint.color;
          final wash = tokens.text.withValues(alpha: 0.1);
          return (drawn.a - wash.a).abs() < 1 / 255 &&
              drawn.r == wash.r &&
              drawn.g == wash.g &&
              drawn.b == wash.b;
        }),
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });

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

    testWidgets('right-to-left puts the first button, and its 24 dp, at the '
        'right and the More button at the left', (tester) async {
      await pumpPage(
        tester,
        (c) => root(c, [cut, copy]),
        textDirection: TextDirection.rtl,
      );

      final first = tester.getRect(key(SelectionMenuItemKind.cut));
      final more = tester.getRect(find.byKey(SelectionMenuRootPage.moreKey));
      expect(first.right, cardRect(tester).right);
      expect(first.right - tester.getRect(find.text('Cut')).right, 24);
      expect(more.left, cardRect(tester).left);
    });
  });

  group('the More page', () {
    testWidgets('is as wide as its widest row and 18 dp each side', (
      tester,
    ) async {
      await pumpPage(
        tester,
        (c) => more(c, [
          item(SelectionMenuItemKind.bold, 'bold'),
          item(SelectionMenuItemKind.italic, 'A longer label'),
        ]),
      );

      final longest = tester
          .renderObject<RenderParagraph>(find.text('A longer label'))
          .getMaxIntrinsicWidth(double.infinity);
      final tile = tester.getRect(key(SelectionMenuItemKind.italic));
      expect(tile.width, wholePixelAbove(longest + 36));
      expect(
        tester.getRect(find.byType(SelectionMenuMorePage)).width,
        tile.width,
      );
      expect(tester.getRect(find.text('A longer label')).left - tile.left, 18);
      expect(tester.getSize(key(SelectionMenuItemKind.bold)).width, tile.width);
    });

    testWidgets('a tile is 42 dp tall', (tester) async {
      await pumpPage(tester, (c) => more(c, formatting(2)));

      expect(tester.getSize(key(SelectionMenuItemKind.bold)).height, 42);
    });

    testWidgets('the label is 14 dp medium, as on the main row', (
      tester,
    ) async {
      await pumpPage(tester, (c) => more(c, formatting(1)));

      final style = tester.widget<Text>(find.text('bold')).style!;
      expect(style.fontSize, 14);
      expect(style.fontWeight, FontWeight.w500);
      expect(style.letterSpacing, 0);
    });

    testWidgets('the Back row is 48 dp with its arrow at 16 and its label at '
        '56 in 16 dp regular', (tester) async {
      await pumpPage(tester, (c) => more(c, formatting(2)));

      final back = tester.getRect(find.byKey(SelectionMenuMorePage.backKey));
      expect(back.height, 48);
      expect(
        tester.getRect(find.byIcon(Icons.arrow_back)).left - back.left,
        16,
      );
      expect(tester.getSize(find.byIcon(Icons.arrow_back)).width, 24);
      expect(tester.getRect(find.text('Back')).left - back.left, 56);
      final style = tester.widget<Text>(find.text('Back')).style!;
      expect(style.fontSize, 16);
      expect(style.fontWeight, FontWeight.w400);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('the Back row is mirrored in right-to-left', (tester) async {
      await pumpPage(
        tester,
        (c) => more(c, formatting(2)),
        textDirection: TextDirection.rtl,
      );

      final back = tester.getRect(find.byKey(SelectionMenuMorePage.backKey));
      expect(
        back.right - tester.getRect(find.byIcon(Icons.arrow_back)).right,
        16,
      );
      expect(back.right - tester.getRect(find.text('Back')).right, 56);
    });

    testWidgets('Back sits under the list when the card is above', (
      tester,
    ) async {
      await pumpPage(tester, (c) => more(c, formatting(2)));

      final list = tester.getRect(key(SelectionMenuItemKind.italic));
      final back = tester.getRect(find.byKey(SelectionMenuMorePage.backKey));
      expect(back.top, greaterThan(list.bottom));
      expect(back.bottom, cardRect(tester).bottom);
    });

    testWidgets('and above it when the card is below', (tester) async {
      await pumpPage(
        tester,
        (c) =>
            more(c, formatting(2), placement: SelectionMenuBackPlacement.top),
      );

      final first = tester.getRect(key(SelectionMenuItemKind.bold));
      final back = tester.getRect(find.byKey(SelectionMenuMorePage.backKey));
      expect(back.bottom, lessThan(first.top));
      expect(back.top, 0);
    });

    testWidgets('the list keeps 4 dp above its first row', (tester) async {
      await pumpPage(tester, (c) => more(c, formatting(2)));

      expect(tester.getRect(key(SelectionMenuItemKind.bold)).top, 4);
      expect(tester.getRect(key(SelectionMenuItemKind.italic)).top, 4 + 42);
    });

    testWidgets('a hairline of one device pixel is the top edge of the Back '
        'row', (tester) async {
      await pumpPage(
        tester,
        (c) => more(c, formatting(2)),
        devicePixelRatio: 3,
      );

      final divider = find.byType(SelectionMenuDivider);
      expect(divider, findsOneWidget);
      final back = tester.getRect(find.byKey(SelectionMenuMorePage.backKey));
      expect(tester.getSize(divider).height, closeTo(1 / 3, 1e-9));
      expect(tester.getRect(divider).top, back.top);
      expect(
        tester.widget<SelectionMenuDivider>(divider).color,
        tokens.divider,
      );
    });

    testWidgets('with Back above the list the hairline is the card\'s top '
        'edge', (tester) async {
      await pumpPage(
        tester,
        (c) =>
            more(c, formatting(2), placement: SelectionMenuBackPlacement.top),
      );

      expect(tester.getRect(find.byType(SelectionMenuDivider)).top, 0);
      expect(tester.getSize(find.byType(SelectionMenuDivider)).height, 1);
    });

    testWidgets('three rows are 3 x 48 and the Back row tall, with no scroll', (
      tester,
    ) async {
      await pumpPage(tester, (c) => more(c, formatting(3), maxHeight: 400));

      expect(tester.getSize(find.byType(SelectionMenuMorePage)).height, 192);
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.padding, const EdgeInsets.only(top: 4, bottom: 2));
    });

    testWidgets('nine rows show four and half of the next: 264 tall, and the '
        'list scrolls', (tester) async {
      await pumpPage(tester, (c) => more(c, formatting(9), maxHeight: 400));

      expect(tester.getSize(find.byType(SelectionMenuMorePage)).height, 264);
      expect(find.byType(ListView), findsOneWidget);
      // The fifth row starts at 4 + 4 * 42 = 172 and the list ends at 216: it
      // is cut where the peek ends.
      final list = tester.getRect(find.byType(ListView));
      expect(list.height, 4 * 48 + 24);
      expect(tester.getRect(key(SelectionMenuItemKind.mono)).top, 4 + 4 * 42);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      // At the end the last row rests 2 dp above the list's end.
      expect(
        tester.getRect(key(SelectionMenuItemKind.createLink)).bottom,
        closeTo(list.bottom - 2, 0.1),
      );
    });

    testWidgets('the room of a cramped side leaves two rows at least', (
      tester,
    ) async {
      await pumpPage(tester, (c) => more(c, formatting(9), maxHeight: 60));

      // 2 x 48 + 24 + 48.
      expect(tester.getSize(find.byType(SelectionMenuMorePage)).height, 168);
    });

    testWidgets('the list edges fade over 16 dp', (tester) async {
      await pumpPage(tester, (c) => more(c, formatting(9), maxHeight: 400));

      final fade = find.descendant(
        of: find.byType(SelectionMenuMorePage),
        matching: find.byType(ShaderMask),
      );
      expect(fade, findsOneWidget);
      expect(tester.widget<ShaderMask>(fade).blendMode, BlendMode.dstIn);
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
      // The row of the reference is medium weight: a plain row keeps it.
      expect(styleOf('Spoiler').fontWeight, FontWeight.w500);
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
      final tile = tester.getRect(key(SelectionMenuItemKind.bulletList));
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

    testWidgets('no label of the page is ellipsized', (tester) async {
      await pumpPage(
        tester,
        (c) => more(c, [
          item(SelectionMenuItemKind.bulletList, 'Bullet list'),
          item(SelectionMenuItemKind.bold, 'A longer label'),
          item(
            SelectionMenuItemKind.mono,
            'Monospaced label',
            style: SelectionMenuLabelStyle.mono,
          ),
          item(
            SelectionMenuItemKind.italic,
            'Italic label',
            style: SelectionMenuLabelStyle.italic,
          ),
        ]),
      );

      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final render = tester.renderObject<RenderParagraph>(
          find.byWidget(text),
        );
        expect(render.didExceedMaxLines, isFalse, reason: text.data);
      }
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

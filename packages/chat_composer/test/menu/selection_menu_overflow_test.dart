/// Which clipboard buttons fit the main row, by the rule of Telegram's floating
/// toolbar: the rest go to the top of the More page.
///
/// **Seam:** `splitSelectionMenuRow` and `sizeSelectionMenuPage` over labels, a
/// text style and the room.
///
/// Every expected width is a worked example of `FloatingToolbar.java`: a
/// button is its text and 16 dp each side (24 at the row's outer ends, 1.5 x),
/// 48 dp at least, and an item stays on the row while it fits beside the 56 dp
/// More button (the last item of the whole menu may take that room instead).
library;

import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:chat_composer/src/menu/selection_menu_overflow.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Ahem draws every glyph as a square of the font size, so a label is
  // `characters * 10` wide.
  const style = TextStyle(fontFamily: 'Ahem', fontSize: 10);

  SelectionMenuRowSplit split(
    List<String> labels,
    double maxWidth, {
    bool moreFollows = false,
    TextScaler scaler = TextScaler.noScaling,
    TextDirection direction = TextDirection.ltr,
  }) => splitSelectionMenuRow(
    labels: labels,
    style: style,
    maxWidth: maxWidth,
    moreFollows: moreFollows,
    textScaler: scaler,
    textDirection: direction,
  );

  double button(
    String label, {
    bool first = false,
    bool last = false,
    TextScaler scaler = TextScaler.noScaling,
  }) => selectionMenuButtonWidth(
    label: label,
    style: style,
    textScaler: scaler,
    textDirection: TextDirection.ltr,
    isFirst: first,
    isLast: last,
  );

  group('a button', () {
    testWidgets('is its label and 16 dp each side', (tester) async {
      expect(button('Copy'), 4 * 10 + 32);
    });

    testWidgets('keeps 24 dp, 1.5 times 16, at the start of the row', (
      tester,
    ) async {
      expect(button('Cut', first: true), 24 + 3 * 10 + 16);
    });

    testWidgets('and at the end of the row when nothing follows it', (
      tester,
    ) async {
      expect(button('Copy', last: true), 16 + 4 * 10 + 24);
      expect(button('A', first: true, last: true), 24 + 10 + 24);
    });

    testWidgets('is 48 dp wide at least', (tester) async {
      expect(button('A'), 48);
    });

    testWidgets('widens with the text scale', (tester) async {
      // A label is measured up to the next whole pixel, and a float step at
      // 1.5 times can tip an exact 60 to 61: one pixel is the tolerance.
      expect(
        button('Copy', scaler: const TextScaler.linear(1.5)),
        inInclusiveRange(4 * 15 + 32, 4 * 15 + 32 + 1),
      );
    });
  });

  group('the split', () {
    testWidgets('keeps every button when the row has the room for them', (
      tester,
    ) async {
      // Cut 24+30+16 = 70, Copy 16+40+16 = 72, Paste 16+50+24 = 90: 232, with
      // nothing after Paste the row needs no More button.
      final result = split(['Cut', 'Copy', 'Paste'], 232);

      expect(result.count, 3);
      expect(result.width, 232);
      expect(result.hasMore, isFalse);
      expect(result.rowWidth, 232);
    });

    testWidgets('the last button may take the More button\'s room', (
      tester,
    ) async {
      // Paste is last (24 at the end): it needs 90 and the row has 90 left
      // after Cut and Copy; beside a More button it would need 56 more.
      expect(split(['Cut', 'Copy', 'Paste'], 231).count, 2);
      expect(split(['Cut', 'Copy', 'Paste'], 232).count, 3);
    });

    testWidgets('formatting after the labels makes every one beside the More '
        'button', (tester) async {
      // Paste is no longer the last item, so it has 16 at the end (82) and
      // must fit with 56 to spare: 70 + 72 + 82 + 56 = 280.
      final tight = split(['Cut', 'Copy', 'Paste'], 279, moreFollows: true);
      final enough = split(['Cut', 'Copy', 'Paste'], 280, moreFollows: true);

      expect(tight.count, 2);
      expect(tight.hasMore, isTrue);
      expect(enough.count, 3);
      expect(enough.hasMore, isTrue);
      expect(enough.width, 70 + 72 + 82);
      expect(enough.rowWidth, 70 + 72 + 82 + 56);
    });

    testWidgets(
      'the first button that does not fit and all after it overflow',
      (tester) async {
        // Cut 70 + Copy 72 = 142 and the More button 56 fit in 198; Paste would
        // make 142 + 82 = 224 beside More.
        final result = split(['Cut', 'Copy', 'Paste', 'All'], 198);

        expect(result.count, 2);
        expect(result.width, 142);
        expect(result.hasMore, isTrue);
      },
    );

    testWidgets('a short button after an overflowed one stays on the page', (
      tester,
    ) async {
      // Cut fits; Paste does not; Go would fit alone but follows Paste.
      final result = split(['Cut', 'Paste', 'Go'], 70 + 56 + 20);

      expect(result.count, 1);
    });

    testWidgets('the row can hold nothing but the More button', (tester) async {
      final result = split(['Select all'], 50, moreFollows: true);

      expect(result.count, 0);
      expect(result.width, 0);
      expect(result.hasMore, isTrue);
      expect(result.rowWidth, 56);
    });

    testWidgets('a button wider than the row is cut to the row', (
      tester,
    ) async {
      // Telegram: min(measured, toolbarWidth). It then cannot sit beside the
      // More button, but as the only and last item it may take the row.
      final result = split(['a very long label indeed'], 120);

      expect(result.count, 1);
      expect(result.width, 120);
    });

    testWidgets('the text scale widens the buttons', (tester) async {
      // Copy first with More after it: 24 + 40 + 16 = 80 <= 150 - 56, and
      // 24 + 60 + 16 = 100 at 1.5.
      expect(split(['Copy'], 150, moreFollows: true).count, 1);
      expect(
        split(
          ['Copy'],
          150,
          moreFollows: true,
          scaler: const TextScaler.linear(1.5),
        ).count,
        0,
      );
    });

    testWidgets('nothing to split is an empty row without a More button', (
      tester,
    ) async {
      final result = split([], 200);

      expect(result.count, 0);
      expect(result.hasMore, isFalse);
      expect(result.rowWidth, 0);
    });
  });

  group('the page', () {
    SelectionMenuItem row(
      String label, {
      SelectionMenuItemKind kind = SelectionMenuItemKind.bold,
      SelectionMenuLabelStyle labelStyle = SelectionMenuLabelStyle.plain,
    }) => SelectionMenuItem(
      kind: kind,
      label: label,
      labelStyle: labelStyle,
      onSelected: () {},
    );

    List<SelectionMenuItem> rows(int count, {String label = 'Row'}) => [
      for (var i = 0; i < count; i++)
        row(label, kind: SelectionMenuItemKind.values[i]),
    ];

    SelectionMenuPageSize size(
      List<SelectionMenuItem> items, {
      double maxWidth = 1000,
      double? maxHeight,
      String back = 'Back',
      TextScaler scaler = TextScaler.noScaling,
    }) => sizeSelectionMenuPage(
      items: items,
      style: style,
      backLabel: back,
      backStyle: style,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      textScaler: scaler,
      textDirection: TextDirection.ltr,
    );

    testWidgets('is as wide as its widest row and its 18 dp each side', (
      tester,
    ) async {
      // 18 + 100 + 18; the Back row (56 + 40 + 16 = 112) is narrower.
      final result = size([row('Row'), row('Longest row')]);

      expect(result.width, 18 + 11 * 10 + 18);
    });

    testWidgets('is never narrower than its Back row', (tester) async {
      // A row of 18 + 30 + 18 = 66 against Back's 56 + 40 + 16 = 112: the
      // reference clips the label, the port widens the page.
      expect(size([row('Row')]).width, 56 + 4 * 10 + 16);
    });

    testWidgets('counts a list row\'s marker column and gap', (tester) async {
      // 18 + 16 + 8 + 12 * 10 + 18.
      final result = size([
        row('Bullet list!', kind: SelectionMenuItemKind.bulletList),
      ]);

      expect(result.width, 18 + 16 + 8 + 120 + 18);
    });

    testWidgets('measures a row in the style it is given', (tester) async {
      final wide = sizeSelectionMenuPage(
        items: [row('Row')],
        style: style.copyWith(fontSize: 20),
        backLabel: '',
        backStyle: style,
        maxWidth: 1000,
        textScaler: TextScaler.noScaling,
        textDirection: TextDirection.ltr,
      );

      expect(wide.width, 18 + 3 * 20 + 18);
    });

    testWidgets('follows the text scale', (tester) async {
      final result = size(
        [row('Row')],
        back: '',
        scaler: const TextScaler.linear(1.5),
      );

      // Whole-pixel measuring, as above.
      expect(
        result.width,
        inInclusiveRange(18 + 3 * 15 + 18, 18 + 3 * 15 + 18 + 1),
      );
    });

    testWidgets('is cut to the room across', (tester) async {
      expect(size(rows(2, label: 'Long label'), maxWidth: 90).width, 90);
    });

    testWidgets('shows every row of a short list, 48 dp each', (tester) async {
      // The reference counts a 42 dp row as 48: lines * 48 + the Back row.
      final one = size(rows(1));
      final three = size(rows(3));

      expect(one.listHeight, 48);
      expect(one.height, 48 + 48);
      expect(one.scrolls, isFalse);
      expect(three.listHeight, 3 * 48);
      expect(three.height, 3 * 48 + 48);
      expect(three.scrolls, isFalse);
    });

    testWidgets('shows four rows and half of the next of a long list', (
      tester,
    ) async {
      final result = size(rows(7));

      expect(result.listHeight, 4 * 48 + 24);
      expect(result.height, 4 * 48 + 24 + 48);
      expect(result.scrolls, isTrue);
    });

    testWidgets('four rows exactly do not scroll and have no peek', (
      tester,
    ) async {
      final result = size(rows(4));

      expect(result.listHeight, 4 * 48);
      expect(result.scrolls, isFalse);
    });

    testWidgets('shows fewer rows where the room is short, two at least', (
      tester,
    ) async {
      // (200 - 48) ~/ 48 = 3 rows; (100 - 48) ~/ 48 = 1, kept at 2; the
      // room under the Back row's height still gives 2.
      expect(size(rows(7), maxHeight: 200).listHeight, 3 * 48 + 24);
      expect(size(rows(7), maxHeight: 100).listHeight, 2 * 48 + 24);
      expect(size(rows(7), maxHeight: 0).listHeight, 2 * 48 + 24);
      expect(size(rows(7), maxHeight: 1000).listHeight, 4 * 48 + 24);
    });

    testWidgets('never shows more rows than it has', (tester) async {
      expect(size(rows(1), maxHeight: 400).listHeight, 48);
    });

    testWidgets('the tallest menu is 4 rows, the Back row and the peek', (
      tester,
    ) async {
      expect(SelectionMenuMetrics.maxHeight, 264);
      expect(size(rows(9)).height, SelectionMenuMetrics.maxHeight);
    });
  });
}

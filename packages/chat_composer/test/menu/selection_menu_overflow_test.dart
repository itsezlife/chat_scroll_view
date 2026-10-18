/// Which clipboard buttons fit the main row: the rest go to the top of the
/// More page.
///
/// **Seam:** `splitSelectionMenuRow` over labels, a text style and a width.
library;

import 'package:chat_composer/src/menu/selection_menu_overflow.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Ahem draws every glyph as a square of the font size, so a label is
  // `characters * 10` wide and a button that plus 24.
  const style = TextStyle(fontFamily: 'Ahem', fontSize: 10);

  SelectionMenuRowSplit split(
    List<String> labels,
    double maxWidth, {
    TextScaler scaler = TextScaler.noScaling,
    TextDirection direction = TextDirection.ltr,
  }) => splitSelectionMenuRow(
    labels: labels,
    style: style,
    maxWidth: maxWidth,
    textScaler: scaler,
    textDirection: direction,
  );

  testWidgets('a button is its label and 12 dp each side', (tester) async {
    expect(
      selectionMenuButtonWidth(
        label: 'Copy',
        style: style,
        textScaler: TextScaler.noScaling,
        textDirection: TextDirection.ltr,
      ),
      4 * 10 + 24,
    );
  });

  testWidgets('everything fits when the row has the room and the More button', (
    tester,
  ) async {
    // Cut 54 + Copy 64 + Paste 74 = 192; the More button takes 46.
    final result = split(['Cut', 'Copy', 'Paste'], 192 + 46);

    expect(result.count, 3);
    expect(result.width, 192);
  });

  testWidgets('the first button that does not fit and all after it overflow', (
    tester,
  ) async {
    // 54 + 64 fit in 118; Paste would make 192 > 118.
    final result = split(['Cut', 'Copy', 'Paste', 'All'], 118 + 46);

    expect(result.count, 2);
    expect(result.width, 118);
  });

  testWidgets('a short button after an overflowed one stays on the page', (
    tester,
  ) async {
    // Cut fits; Paste does not; Go would fit alone but follows Paste.
    final result = split(['Cut', 'Paste', 'Go'], 54 + 20 + 46);

    expect(result.count, 1);
  });

  testWidgets('the row can hold nothing', (tester) async {
    final result = split(['Select all'], 50);

    expect(result.count, 0);
    expect(result.width, 0);
  });

  testWidgets('the text scale widens the buttons', (tester) async {
    final result = split(
      ['Copy'],
      4 * 10 + 24 + 46,
      scaler: const TextScaler.linear(1.5),
    );

    // 4 * 15 + 24 = 84 > 64.
    expect(result.count, 0);
  });
}

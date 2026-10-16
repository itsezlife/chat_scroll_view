/// What each arrangement turns on: the flags a page reads instead of asking
/// which arrangement it is.
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';

void main() {
  test('only the pointer arrangement answers a right click with a menu', () {
    expect(PanelArrangement.pointer.usesContextMenu, isTrue);
    expect(PanelArrangement.touch.usesContextMenu, isFalse);
  });

  test('the pointer arrangement keeps the bar where it is', () {
    expect(PanelArrangement.pointer.barHidesOnScroll, isFalse);
    expect(PanelArrangement.touch.barHidesOnScroll, isTrue);
  });

  test('only touch offers backspace, and every arrangement the rest', () {
    const other = PageAction(
      id: 'other',
      icon: ChromeIconId.attach,
      semanticLabel: _label,
    );

    expect(
      PanelArrangement.touch.offersAction(const PageAction.backspace()),
      isTrue,
    );
    expect(
      PanelArrangement.pointer.offersAction(const PageAction.backspace()),
      isFalse,
    );
    for (final arrangement in PanelArrangement.values) {
      expect(arrangement.offersAction(other), isTrue, reason: '$arrangement');
    }
  });
}

String _label(ChromeStrings strings) => 'other';

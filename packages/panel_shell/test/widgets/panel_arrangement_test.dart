/// What each arrangement turns on: the flags a page reads instead of asking
/// which arrangement it is.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';

void main() {
  test('only the pointer arrangement answers a right click with a menu', () {
    expect(PanelArrangement.pointer.usesContextMenu, isTrue);
    expect(PanelArrangement.touch.usesContextMenu, isFalse);
  });

  test('the pointer arrangement keeps the bar and the whole grid', () {
    expect(PanelArrangement.pointer.barHidesOnScroll, isFalse);
    expect(PanelArrangement.pointer.narrowsEmptySearch, isFalse);
    expect(PanelArrangement.touch.barHidesOnScroll, isTrue);
    expect(PanelArrangement.touch.narrowsEmptySearch, isTrue);
  });
}

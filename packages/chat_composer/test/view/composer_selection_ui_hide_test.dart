/// A host takes the field's selection UI down: the handle and the menu a
/// tap or a long press left do not stay up while a panel types into the
/// field in the keyboard's place.
///
/// **Seam:** the field with its selection menu up ([MenuRig]), then
/// [ComposerController.hideSelectionUi], observed through the menu and the
/// field's selection overlay.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/selection_menu_harness.dart';

void main() {
  testWidgets('hideSelectionUi takes the menu and the handles down', (
    tester,
  ) async {
    final rig = await MenuRig.show(tester);
    expect(MenuRig.card, findsOneWidget);

    rig.composer.hideSelectionUi();
    await tester.pumpAndSettle();
    expect(MenuRig.card, findsNothing);
    expect(rig.editable.selectionOverlay?.handlesAreVisible ?? false, isFalse);
  });
}

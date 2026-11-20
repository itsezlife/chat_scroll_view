/// The attach sheet's text style: the sheet opens in a popup route with no
/// `Material` above its content, where the inherited text style is the
/// framework's debug one (underlined, yellow); the sheet's root gives every
/// page, the tab bar and the panel the chrome face instead.
///
/// **Seams:** the sheet shown with [AttachSheet.show] (the rig), read through
/// the effective style of every text it lays out.
library;

import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../page/pages_rig.dart';

AttachPage _textPage(String id) => AttachPage(
  id: AttachPageId(id),
  label: id,
  icon: const SizedBox(width: 24, height: 24),
  kind: AttachPageKind.selection,
  builder: (context, scope) => ListView(
    controller: scope.scrollController,
    children: const [Text('page text', key: ValueKey('page-text'))],
  ),
);

void main() {
  testWidgets('no text in the sheet takes the fallback style', (tester) async {
    final rig = await PagesRig.open(
      tester,
      policy: const AttachSheetPolicy.android(),
      pages: [_textPage('gallery'), _textPage('files')],
    );
    // A selection brings the panel (caption and send) in.
    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AttachSheet),
        matching: find.byKey(const ValueKey('page-text')),
      ),
      findsOneWidget,
    );
    expectChromeText(tester, within: find.byType(AttachSheet));
  });
}

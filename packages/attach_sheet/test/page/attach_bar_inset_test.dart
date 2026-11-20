/// The bar at the sheet's bottom floats over the page: the page's last row
/// scrolls clear of it, the tab bar's and then the panel's as it swaps in.
///
/// **Seams:** the paged sheet ([PagesRig]) with a page of rows, read through
/// the rects of its last row and of the bar.
library;

import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pages_rig.dart';

void main() {
  testWidgets("the last row ends at the floating bar's top, whichever bar "
      'is up', (tester) async {
    final rig = await PagesRig.open(
      tester,
      policy: const AttachSheetPolicy.android(),
      pages: [rowsPage('a'), rowsPage('b')],
    );
    final bar = find.byKey(const ValueKey('attach-sheet-bar'));
    final last = find.byKey(const ValueKey('a-row-59'));

    Future<void> toTheEnd() async {
      for (var i = 0; i < 6; i++) {
        await tester.dragFrom(const Offset(200, 600), const Offset(0, -600));
        await tester.pumpAndSettle();
      }
    }

    await toTheEnd();
    expect(last, findsOneWidget);
    expect(
      tester.getRect(last).bottom,
      closeTo(tester.getRect(bar).top, 0.5),
      reason: 'the tab bar',
    );

    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();
    await toTheEnd();
    expect(
      tester.getRect(last).bottom,
      closeTo(tester.getRect(bar).top, 0.5),
      reason: 'the panel',
    );
  });
}

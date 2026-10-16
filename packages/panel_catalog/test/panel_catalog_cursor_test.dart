/// The pointer cursor over the catalog: the click cursor where a press would do
/// something, the surrounding one everywhere else.
///
/// **Seam:** [PanelCatalogViewport] with a mouse hovering it, observed through
/// the cursor the mouse tracker activated for that device.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/asset_scopes.dart';

// 4 columns of 80 x 40 cells under a 24 px header in a 320 x 480 viewport; the
// action "More" is 60 px wide with an 8 px inset, so its hit area is the last
// 76 px of the header band.
const _span = 4;

// The device id of the mouse `TestGesture` simulates.
const _mouse = 1;

CatalogSection _section(String id, {bool action = true, int leaves = 8}) =>
    CatalogSection(
      id: id,
      title: id,
      action: action
          ? const CatalogSectionAction(id: 'more', label: 'More')
          : null,
      leaves: [
        for (var i = 0; i < leaves; i++)
          CatalogLeaf.unicode(String.fromCharCode(0x1F600 + i)),
      ],
    );

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource(sections: [_section('a')]);
    controller = PanelCatalogController();
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
  });

  Future<void> pumpViewport(
    WidgetTester tester, {
    bool tap = true,
    bool longPress = false,
    bool action = true,
    TextDirection direction = TextDirection.ltr,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: PanelCatalogTheme(
          data: PanelCatalogThemeData.light,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              height: 480,
              child: PanelCatalogViewport(
                snapshots: snapshots,
                assets: textGlyphScope(),
                controller: controller,
                spanCount: _span,
                cellExtent: 40,
                headerExtent: 24,
                onLeafTap: tap ? (hit) {} : null,
                onLeafLongPressStart: longPress ? (hit, details) {} : null,
                onSectionAction: action ? (section, id) {} : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// A mouse that hovers the viewport (placed at the origin), and the cursor
  /// the mouse tracker has active for it.
  Future<({TestGesture mouse, MouseCursor? Function() cursor})> hover(
    WidgetTester tester,
    Offset start,
  ) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    addTearDown(gesture.removePointer);
    await tester.pump();
    return (
      mouse: gesture,
      cursor: () =>
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(_mouse),
    );
  }

  /// The cursor over [position].
  Future<MouseCursor?> cursorAt(WidgetTester tester, Offset position) async {
    final pointer = await hover(tester, position);
    return pointer.cursor();
  }

  testWidgets('a leaf the shell can tap shows the click cursor', (
    tester,
  ) async {
    await pumpViewport(tester);

    expect(
      await cursorAt(tester, const Offset(100, 40)),
      SystemMouseCursors.click,
    );
  });

  testWidgets('a leaf with only a long-press shows it too', (tester) async {
    await pumpViewport(tester, tap: false, longPress: true);

    expect(
      await cursorAt(tester, const Offset(100, 40)),
      SystemMouseCursors.click,
    );
  });

  testWidgets('a leaf the shell cannot act on does not', (tester) async {
    await pumpViewport(tester, tap: false);

    expect(
      await cursorAt(tester, const Offset(100, 40)),
      isNot(SystemMouseCursors.click),
    );
  });

  testWidgets('the header title is not clickable', (tester) async {
    await pumpViewport(tester);

    expect(
      await cursorAt(tester, const Offset(20, 12)),
      isNot(SystemMouseCursors.click),
    );
  });

  testWidgets('the header action is, at the end of the band', (tester) async {
    await pumpViewport(tester);

    expect(
      await cursorAt(tester, const Offset(300, 12)),
      SystemMouseCursors.click,
    );
  });

  testWidgets('the header action is at the other end right to left', (
    tester,
  ) async {
    await pumpViewport(tester, direction: TextDirection.rtl);
    final pointer = await hover(tester, const Offset(30, 12));

    expect(pointer.cursor(), SystemMouseCursors.click);
    await pointer.mouse.moveTo(const Offset(300, 12));
    await tester.pump();
    expect(pointer.cursor(), isNot(SystemMouseCursors.click));
  });

  testWidgets('an action nobody listens to is not clickable', (tester) async {
    await pumpViewport(tester, action: false);

    expect(
      await cursorAt(tester, const Offset(300, 12)),
      isNot(SystemMouseCursors.click),
    );
  });

  testWidgets('follows the pointer from a leaf to the header', (tester) async {
    await pumpViewport(tester);
    final pointer = await hover(tester, const Offset(100, 40));

    expect(pointer.cursor(), SystemMouseCursors.click);
    await pointer.mouse.moveTo(const Offset(20, 12));
    await tester.pump();
    expect(pointer.cursor(), isNot(SystemMouseCursors.click));
    await pointer.mouse.moveTo(const Offset(100, 40));
    await tester.pump();
    expect(pointer.cursor(), SystemMouseCursors.click);
  });

  testWidgets('follows the content when it scrolls under a still pointer', (
    tester,
  ) async {
    // 80 leaves: 20 rows, so the catalogue scrolls.
    snapshots.replaceSections([
      _section('a', leaves: 80),
      _section('b', leaves: 80),
    ]);
    await pumpViewport(tester);
    final pointer = await hover(tester, const Offset(100, 40));
    expect(pointer.cursor(), SystemMouseCursors.click);

    // a's rows end at 24 + 20 * 40 = 824; b's header band is 824..848. Put its
    // title under the pointer.
    controller.jumpTo(836 - 40);
    await tester.pump();
    await tester.pump();

    expect(pointer.cursor(), isNot(SystemMouseCursors.click));
  });
}

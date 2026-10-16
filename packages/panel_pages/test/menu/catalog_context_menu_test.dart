/// The context menu a page opens at the pointer.
///
/// **Seam:** [CatalogContextMenuHost] around a button in an overlay, driven
/// through its controller and observed through what is on screen, the
/// callbacks it makes, the focus and the holds a fake page host recorded.
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/testing.dart';

const _entries = <CatalogMenuEntry>[
  CatalogMenuEntry.item(id: 'copy', label: 'Copy'),
  CatalogMenuEntry.item(id: 'remove', label: 'Remove from recent'),
  CatalogMenuEntry.separator(),
  CatalogMenuEntry.item(id: 'clear', label: 'Clear recent', attention: true),
];

void main() {
  late FakePanelPageHost host;
  late CatalogContextMenuController controller;
  late FocusNode field;
  late List<String> chosen;
  late int bottomTaps;

  setUp(() {
    host = FakePanelPageHost();
    controller = CatalogContextMenuController();
    field = FocusNode(debugLabel: 'field');
    chosen = [];
    bottomTaps = 0;
    addTearDown(() {
      host.dispose();
      controller.dispose();
      field.dispose();
    });
  });

  Future<void> pump(WidgetTester tester, {TextDirection? direction}) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      PanelShellTestScope(
        textDirection: direction ?? TextDirection.ltr,
        size: const Size(400, 600),
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => CatalogContextMenuHost(
                host: host,
                controller: controller,
                child: Column(
                  children: [
                    Focus(
                      focusNode: field,
                      child: const SizedBox(width: 400, height: 40),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => bottomTaps++,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void open(Offset at) => controller.show(
    globalPosition: at,
    entries: _entries,
    onSelected: chosen.add,
  );

  Finder item(String label) => find.text(label);

  group('opening', () {
    testWidgets('shows the items at the pointer, below and after it', (
      tester,
    ) async {
      await pump(tester);

      open(const Offset(100, 200));
      await tester.pump();

      for (final label in ['Copy', 'Remove from recent', 'Clear recent']) {
        expect(item(label), findsOneWidget);
      }
      final copy = tester.getTopLeft(item('Copy'));
      expect(copy.dx, greaterThan(100));
      expect(copy.dy, greaterThan(200));
      expect(controller.isOpen, isTrue);
    });

    testWidgets('keeps inside the window by opening up and back from the '
        'edge', (tester) async {
      await pump(tester);

      open(const Offset(395, 595));
      await tester.pump();

      final panel = tester.getRect(find.byType(CatalogContextMenuPanel));
      expect(panel.right, lessThanOrEqualTo(395.01));
      expect(panel.bottom, lessThanOrEqualTo(595.01));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.top, greaterThanOrEqualTo(0));
    });

    testWidgets('holds auto-hide from the moment it opens until it closes', (
      tester,
    ) async {
      await pump(tester);
      expect(host.activeHolds, 0);

      open(const Offset(100, 200));
      expect(host.activeHolds, 1, reason: 'taken as it opens');
      await tester.pump();

      controller.close();
      await tester.pump();
      expect(host.activeHolds, 0);
      expect(host.holdsTaken, 1);
    });

    testWidgets('releases the hold when the page goes with the menu open', (
      tester,
    ) async {
      await pump(tester);
      open(const Offset(100, 200));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());

      expect(host.activeHolds, 0);
    });

    testWidgets('opening it again moves it and holds once', (tester) async {
      await pump(tester);
      open(const Offset(100, 200));
      await tester.pump();

      open(const Offset(150, 250));
      await tester.pump();

      expect(host.activeHolds, 1);
      expect(item('Copy'), findsOneWidget);
    });

    testWidgets('with no entries does nothing and holds nothing', (
      tester,
    ) async {
      await pump(tester);

      controller.show(
        globalPosition: const Offset(100, 200),
        entries: const [],
        onSelected: chosen.add,
      );
      await tester.pump();

      expect(controller.isOpen, isFalse);
      expect(host.holdsTaken, 0);
    });
  });

  group('choosing', () {
    testWidgets('a click on an item reports its id once and closes', (
      tester,
    ) async {
      await pump(tester);
      open(const Offset(100, 200));
      await tester.pump();

      await tester.tap(item('Remove from recent'));
      await tester.pump();

      expect(chosen, ['remove']);
      expect(controller.isOpen, isFalse);
      expect(item('Copy'), findsNothing);
      expect(host.activeHolds, 0);
    });

    testWidgets('the attention item reports its id like any other', (
      tester,
    ) async {
      await pump(tester);
      open(const Offset(100, 200));
      await tester.pump();

      await tester.tap(item('Clear recent'));
      await tester.pump();

      expect(chosen, ['clear']);
    });

    testWidgets('the attention item is drawn in the destructive colour', (
      tester,
    ) async {
      await pump(tester);
      open(const Offset(100, 200));
      await tester.pump();

      Color colorOf(String label) =>
          tester.widget<Text>(find.text(label)).style!.color!;

      expect(colorOf('Clear recent'), const ChromePalette.light().destructive);
      expect(colorOf('Copy'), const ChromePalette.light().onSurface);
    });
  });

  group('dismissing', () {
    testWidgets('a press anywhere else closes it and is not passed on', (
      tester,
    ) async {
      await pump(tester);
      open(const Offset(100, 200));
      await tester.pump();

      await tester.tapAt(const Offset(300, 500));
      await tester.pump();

      expect(controller.isOpen, isFalse);
      expect(chosen, isEmpty);
      expect(bottomTaps, 0, reason: 'the click that closes it is swallowed');
      expect(host.activeHolds, 0);
    });

    testWidgets('a right click elsewhere closes it too', (tester) async {
      await pump(tester);
      open(const Offset(100, 200));
      await tester.pump();

      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.down(const Offset(300, 500));
      await mouse.up();
      await tester.pump();

      expect(controller.isOpen, isFalse);
    });

    testWidgets('Escape closes it', (tester) async {
      await pump(tester);
      open(const Offset(100, 200));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(controller.isOpen, isFalse);
      expect(chosen, isEmpty);
    });

    testWidgets('gives focus back to what had it', (tester) async {
      await pump(tester);
      field.requestFocus();
      await tester.pump();
      open(const Offset(100, 200));
      await tester.pump();
      expect(field.hasFocus, isFalse, reason: 'the menu takes it for the keys');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();

      expect(field.hasFocus, isTrue);
    });
  });

  group('keyboard', () {
    testWidgets('the first item has focus, the arrows move it and Enter '
        'chooses', (tester) async {
      await pump(tester);
      open(const Offset(100, 200));
      await tester.pump();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(chosen, ['remove']);
      expect(controller.isOpen, isFalse);
    });

    testWidgets('Enter on the first item chooses it, and Up wraps to the '
        'last', (tester) async {
      await pump(tester);
      open(const Offset(100, 200));
      await tester.pump();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(chosen, ['clear']);
    });
  });

  group('semantics', () {
    testWidgets('items are buttons named by their labels', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      open(const Offset(100, 200));
      await tester.pump();

      expect(
        tester.getSemantics(find.text('Copy')),
        matchesSemantics(label: 'Copy', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });

  testWidgets('mirrors for a right-to-left window: opens back from the pointer '
      'at the right edge', (tester) async {
    await pump(tester, direction: TextDirection.rtl);

    open(const Offset(390, 200));
    await tester.pump();

    final panel = tester.getRect(find.byType(CatalogContextMenuPanel));
    expect(panel.right, lessThanOrEqualTo(400));
  });
}

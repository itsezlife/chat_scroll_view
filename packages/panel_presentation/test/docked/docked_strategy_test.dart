import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_shell/panel_shell.dart';

import 'docked_rig.dart';

Rect _panelRect(WidgetTester tester) =>
    tester.getRect(find.byType(PanelShell).first);

Rect _chatRect(WidgetTester tester) =>
    tester.getRect(find.byKey(DockedRig.chatKey));

void main() {
  group('arrangement', () {
    testWidgets('is the pointer one', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester);

      rig.controller.show(kind: const Docked());
      await settleDock(tester);

      expect(
        tester.widget<PanelShell>(find.byType(PanelShell)).arrangement,
        PanelArrangement.pointer,
      );
    });
  });

  group('layout', () {
    testWidgets('sits at the end edge, full height (LTR)', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester);

      rig.controller.show(kind: const Docked());
      await settleDock(tester);

      final rect = _panelRect(tester);
      expect(rect.right, 1000);
      expect(rect.width, 320);
      expect(rect.top, 0);
      expect(rect.bottom, 600);
    });

    testWidgets('mirrors to the left edge in RTL', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester, textDirection: TextDirection.rtl);

      rig.controller.show(kind: const Docked());
      await settleDock(tester);

      final rect = _panelRect(tester);
      expect(rect.left, 0);
      expect(rect.width, 320);
    });

    testWidgets('is narrower than its style in a narrower box', (tester) async {
      final rig = DockedRig(style: const DockedStyle(width: 400));
      await rig.pump(tester, size: const Size(300, 600));

      rig.controller.show(kind: const Docked());
      await settleDock(tester);

      expect(_panelRect(tester).width, 300);
    });
  });

  group('occupancy', () {
    testWidgets('is zero while hidden', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester);

      expect(rig.controller.occupancy.value, PanelOccupancy.zero);
    });

    testWidgets('publishes the inline-end width once shown', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester);

      rig.controller.show(kind: const Docked());
      await settleDock(tester);

      expect(
        rig.controller.occupancy.value,
        const PanelOccupancy(inlineEnd: 320),
      );
    });

    testWidgets('grows with the slide and never exceeds the width', (
      tester,
    ) async {
      final rig = DockedRig();
      await rig.pump(tester);
      final seen = <double>[];
      rig.controller.occupancy.addListener(
        () => seen.add(rig.controller.occupancy.value.inlineEnd),
      );

      rig.controller.show(kind: const Docked());
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(seen, isNotEmpty);
      expect(seen, orderedEquals([...seen]..sort()));
      expect(seen.every((w) => w >= 0 && w <= 320), isTrue);
      expect(seen.last, 320);
    });

    testWidgets('the chat gives up exactly the published width (LTR)', (
      tester,
    ) async {
      final rig = DockedRig();
      await rig.pump(tester);

      rig.controller.show(kind: const Docked());
      await settleDock(tester);

      expect(_chatRect(tester), const Rect.fromLTRB(0, 0, 680, 600));
    });

    testWidgets('the chat gives up the left edge in RTL', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester, textDirection: TextDirection.rtl);

      rig.controller.show(kind: const Docked());
      await settleDock(tester);

      expect(_chatRect(tester), const Rect.fromLTRB(320, 0, 1000, 600));
    });

    testWidgets('returns to zero when hidden', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester);
      rig.controller.show(kind: const Docked());
      await settleDock(tester);

      rig.controller.hide();
      await settleDock(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
      expect(rig.controller.occupancy.value, PanelOccupancy.zero);
      expect(_chatRect(tester).width, 1000);
    });

    testWidgets('is instant with reduced motion', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester, speed: ChromeMotionSpeed.instant);

      rig.controller.show(kind: const Docked());
      await tester.pump();
      await tester.pump();

      expect(rig.controller.occupancy.value.inlineEnd, 320);
    });

    testWidgets('is zero again once the view leaves', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester);
      rig.controller.show(kind: const Docked());
      await settleDock(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(rig.controller.occupancy.value, PanelOccupancy.zero);
    });
  });

  group('popup and dock', () {
    testWidgets('dock moves a shown popup into the section', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester);
      rig.controller.show();
      await settleDock(tester);
      expect(rig.controller.occupancy.value, PanelOccupancy.zero);

      rig.controller.dock();
      await settleDock(tester);

      expect(rig.controller.state.value.kind, const Docked());
      expect(rig.controller.occupancy.value.inlineEnd, 320);
      expect(_chatRect(tester).width, 680);
    });

    testWidgets('keeps page, query and search across the move', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester);
      rig.controller.show();
      await settleDock(tester);
      rig.shell.selectPage('stickers');
      await tester.pump();
      final page = rig.shell.selectedPageId.value;

      rig.controller.dock();
      await settleDock(tester);

      expect(rig.shell.selectedPageId.value, page);
      expect(page, 'stickers');
    });

    testWidgets('undock closes the section and frees the width', (
      tester,
    ) async {
      final rig = DockedRig(dockPreferred: true);
      await rig.pump(tester);
      rig.controller.show();
      await settleDock(tester);

      rig.controller.undock();
      await settleDock(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
      expect(_chatRect(tester).width, 1000);
    });

    testWidgets('a window too narrow for it takes the section away: no popup '
        'takes its place', (tester) async {
      final rig = DockedRig(dockPreferred: true);
      await rig.pump(tester);
      await settleDock(tester);
      expect(rig.controller.state.value.kind, const Docked());

      rig.controller.updateWindow(const PanelWindow(width: 500, height: 600));
      await settleDock(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
      expect(rig.controller.occupancy.value, PanelOccupancy.zero);
      expect(_chatRect(tester).width, 1000);
      expect(rig.controller.dockPreferred.value, isTrue);
    });

    testWidgets('widening again brings the section back by itself', (
      tester,
    ) async {
      final rig = DockedRig(dockPreferred: true);
      await rig.pump(tester);
      await settleDock(tester);
      rig.controller.updateWindow(const PanelWindow(width: 500, height: 600));
      await settleDock(tester);

      rig.controller.updateWindow(const PanelWindow(width: 1000, height: 600));
      await settleDock(tester);

      expect(rig.controller.state.value.kind, const Docked());
      expect(rig.controller.occupancy.value.inlineEnd, 320);
    });

    testWidgets('a window that has the room shows a preferred dock with no '
        'click: it stands', (tester) async {
      final rig = DockedRig(dockPreferred: true);
      await rig.pump(tester);
      await settleDock(tester);

      expect(rig.controller.state.value, const PanelVisibility.shown(Docked()));
      expect(_panelRect(tester).width, 320);
      expect(_chatRect(tester).right, 1000 - 320);
    });
  });

  group('input and focus', () {
    testWidgets('Escape with no search open leaves the section up', (
      tester,
    ) async {
      final rig = DockedRig();
      await rig.pump(tester);
      rig.controller.show(kind: const Docked());
      await settleDock(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleDock(tester);

      expect(rig.controller.state.value.kind, const Docked());
    });

    testWidgets('back leaves the section up: a dock is not dismissed', (
      tester,
    ) async {
      final rig = DockedRig();
      await rig.pump(tester);
      rig.controller.show(kind: const Docked());
      await settleDock(tester);

      expect(rig.controller.handleBack(), isFalse);
      await settleDock(tester);

      expect(rig.controller.state.value.kind, const Docked());
    });

    testWidgets('opening does not take focus from the composer', (
      tester,
    ) async {
      final rig = DockedRig();
      await rig.pump(tester);
      rig.composerFocus.requestFocus();
      await tester.pump();

      rig.controller.show(kind: const Docked());
      await settleDock(tester);

      expect(rig.composerFocus.hasPrimaryFocus, isTrue);
    });

    testWidgets('focus inside returns to the composer on hide', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester);
      rig.controller.show(kind: const Docked());
      await settleDock(tester);
      rig.controller.shell.openSearch();
      await tester.pump();
      await tester.pump();
      expect(rig.composerFocus.hasFocus, isFalse);

      rig.controller.hide();
      await settleDock(tester);

      expect(rig.composerFocus.hasPrimaryFocus, isTrue);
    });
  });

  group('resizing', () {
    Finder handle() => find.byKey(DockedStrategy.resizeHandleKey);

    Future<DockedRig> docked(
      WidgetTester tester, {
      DockedStyle style = const DockedStyle(width: 320),
      PanelWindow window = const PanelWindow(width: 1000, height: 600),
      TextDirection textDirection = TextDirection.ltr,
      DockWidthStore? dockWidths,
    }) async {
      final rig = DockedRig(
        style: style,
        window: window,
        dockWidths: dockWidths,
      );
      await rig.pump(
        tester,
        textDirection: textDirection,
        size: Size(window.width, window.height),
      );
      rig.controller.show(kind: const Docked());
      await settleDock(tester);
      return rig;
    }

    testWidgets('is a 6 px strip along the dock\'s start edge, over a '
        'horizontal-resize cursor', (tester) async {
      await docked(tester);

      final strip = tester.getRect(handle());
      expect(strip.width, 6);
      expect(strip.left, 1000 - 320);
      expect(strip.top, 0);
      expect(strip.bottom, 600);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: strip.center);
      addTearDown(mouse.removePointer);
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.resizeColumn,
      );
    });

    testWidgets('dragging it toward the content widens the dock and narrows '
        'the chat as it goes', (tester) async {
      final rig = await docked(tester);

      final drag = await tester.startGesture(tester.getCenter(handle()));
      await drag.moveBy(const Offset(-40, 0));
      await tester.pump();

      expect(_panelRect(tester).width, 360);
      expect(_panelRect(tester).right, 1000);
      expect(rig.controller.occupancy.value.inlineEnd, 360);
      expect(_chatRect(tester).right, 1000 - 360);
      await drag.up();
    });

    testWidgets('dragging the other way narrows it', (tester) async {
      await docked(tester);

      final drag = await tester.startGesture(tester.getCenter(handle()));
      await drag.moveBy(const Offset(20, 0));
      await tester.pump();

      expect(_panelRect(tester).width, 300);
      await drag.up();
    });

    testWidgets('is held between 292 and 392 while it is dragged', (
      tester,
    ) async {
      await docked(tester);

      final drag = await tester.startGesture(tester.getCenter(handle()));
      await drag.moveBy(const Offset(-300, 0));
      await tester.pump();
      expect(_panelRect(tester).width, 392);

      await drag.moveBy(const Offset(600, 0));
      await tester.pump();
      expect(_panelRect(tester).width, 292);
      await drag.up();
    });

    testWidgets('keeps the chat 380 wide in a window that is only just wide '
        'enough', (tester) async {
      await docked(tester, window: const PanelWindow(width: 700, height: 600));

      final drag = await tester.startGesture(tester.getCenter(handle()));
      await drag.moveBy(const Offset(-200, 0));
      await tester.pump();

      expect(_panelRect(tester).width, 320);
      expect(_chatRect(tester).width, 380);
      await drag.up();
    });

    testWidgets('mirrors in RTL: the handle is on the right of a dock on the '
        'left, and dragging right widens it', (tester) async {
      await docked(tester, textDirection: TextDirection.rtl);

      final strip = tester.getRect(handle());
      expect(strip.right, 320);
      final drag = await tester.startGesture(strip.center);
      await drag.moveBy(const Offset(40, 0));
      await tester.pump();

      expect(_panelRect(tester).width, 360);
      expect(_panelRect(tester).left, 0);
      await drag.up();
    });

    testWidgets('keeps nothing until the drag ends, then the width where it '
        'ended, held to the bounds', (tester) async {
      final kv = FakeKeyValueStore();
      final store = await DockWidthStore.open(kv);
      final rig = await docked(tester, dockWidths: store);

      final drag = await tester.startGesture(tester.getCenter(handle()));
      await drag.moveBy(const Offset(-500, 0));
      await tester.pump();
      expect(store.width, isNull, reason: 'not while it moves');
      expect(rig.controller.dockWanted.value, 820);

      await drag.up();
      await tester.pump();

      expect(rig.controller.dockWanted.value, 392);
      expect(store.width, 392);
      expect((await DockWidthStore.open(kv)).width, 392);
    });

    testWidgets('a dock starts from the width that was kept', (tester) async {
      final kv = FakeKeyValueStore();
      await (await DockWidthStore.open(kv)).record(350);

      await docked(tester, dockWidths: await DockWidthStore.open(kv));

      expect(_panelRect(tester).width, 350);
    });

    testWidgets('a window that widens gives the dragged width back', (
      tester,
    ) async {
      final rig = await docked(
        tester,
        window: const PanelWindow(width: 700, height: 600),
      );
      final drag = await tester.startGesture(tester.getCenter(handle()));
      await drag.moveBy(const Offset(-200, 0));
      await drag.up();
      await tester.pump();
      expect(_panelRect(tester).width, 320);

      tester.view.physicalSize = const Size(1000, 600);
      rig.controller.updateWindow(const PanelWindow(width: 1000, height: 600));
      await settleDock(tester);

      expect(_panelRect(tester).width, 392);
    });

    testWidgets('is not in the way of a hidden dock', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester);

      expect(handle(), findsNothing);
      expect(rig.controller.state.value, PanelVisibility.hidden);
    });
  });
}

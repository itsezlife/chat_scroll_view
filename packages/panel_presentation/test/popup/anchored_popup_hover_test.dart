import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_shell/panel_shell.dart';

import 'popup_rig.dart';

const _toggleCentre = Offset(760, 670);
const _popupCentre = Offset(600, 400);
const _nowhere = Offset(20, 20);

void main() {
  group('hover over the toggle', () {
    testWidgets('a mouse entering the toggle opens the popup', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);

      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);

      expect(
        rig.controller.state.value,
        const PanelVisibility.shown(AnchoredPopup()),
      );
      expect(popupIsUp(tester), isTrue);
    });

    testWidgets('touch never opens it: a press is a click', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);

      final touch = await tester.startGesture(_toggleCentre);
      await tester.pump();
      expect(rig.controller.state.value, PanelVisibility.hidden);
      await touch.up();
      await tester.pump();

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('a stylus hovering does not open it', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final stylus = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await stylus.addPointer(location: _nowhere);
      addTearDown(stylus.removePointer);
      await tester.pump();

      await stylus.moveTo(_toggleCentre);
      await tester.pump();

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('the mobile policy does not hover-open', (tester) async {
      final rig = PopupRig(policy: const PanelPresentationPolicy$Mobile());
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);

      await mouse.moveTo(_toggleCentre);
      await tester.pump();

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('a docked preference in a wide window is not hover-opened', (
      tester,
    ) async {
      final rig = PopupRig(window: const PanelWindow(width: 900, height: 700));
      rig.controller.dock();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);

      await mouse.moveTo(_toggleCentre);
      await tester.pump();

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('a docked panel is left alone by a hover', (tester) async {
      final rig = PopupRig(window: const PanelWindow(width: 900, height: 700));
      await rig.pump(tester);
      rig.controller.show(kind: const Docked());
      await tester.pump();

      // The docked fake covers the toggle, so the enter is delivered by hand.
      rig.strategy.hover.toggleEntered(rig.controller);
      await tester.pump();

      expect(rig.controller.state.value.kind, const Docked());
    });

    testWidgets('click toggles the popup', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);

      rig.controller.toggle();
      await settleMotion(tester);
      expect(popupIsUp(tester), isTrue);

      rig.controller.toggle();
      await settleMotion(tester);
      expect(popupIsUp(tester), isFalse);
      expect(rig.controller.state.value, PanelVisibility.hidden);
    });
  });

  group('leaving', () {
    testWidgets('leaving the toggle hides after 300 ms, not before', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);

      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(const Duration(milliseconds: 299));
      await settleMotion(tester);
      expect(rig.controller.state.value.isVisible, isTrue);

      rig.clock.advance(const Duration(milliseconds: 1));
      await settleMotion(tester);
      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('moving from the toggle into the popup cancels the hide', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);

      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(const Duration(milliseconds: 100));
      await mouse.moveTo(_popupCentre);
      await tester.pump();
      rig.clock.advance(const Duration(seconds: 1));
      await settleMotion(tester);

      expect(
        rig.controller.state.value,
        const PanelVisibility.shown(AnchoredPopup()),
      );
    });

    testWidgets('leaving the popup hides after 300 ms', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester, at: _popupCentre);
      rig.controller.show();
      await settleMotion(tester);

      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(const Duration(milliseconds: 300));
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('re-entering the toggle during the hide delay keeps it open', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);
      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(const Duration(milliseconds: 200));

      await mouse.moveTo(_toggleCentre);
      await tester.pump();
      rig.clock.advance(const Duration(seconds: 5));
      await settleMotion(tester);

      expect(rig.controller.state.value.isVisible, isTrue);
    });

    testWidgets('a hover while the popup is hiding turns it back', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);
      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 20));
      expect(rig.controller.state.value, isA<PanelVisibility$Hiding>());

      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);

      expect(
        rig.controller.state.value,
        const PanelVisibility.shown(AnchoredPopup()),
      );
    });

    testWidgets('a click-opened popup also hides on leave', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester, at: _toggleCentre);
      rig.controller.toggle();
      await settleMotion(tester);

      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(const Duration(milliseconds: 300));
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });
  });

  group('preventAutoHide', () {
    testWidgets('a held guard keeps the popup when the pointer leaves', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);
      final hold = rig.controller.holdAutoHide();

      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(const Duration(seconds: 10));
      await settleMotion(tester);

      expect(rig.controller.state.value.isVisible, isTrue);
      hold.release();
    });

    testWidgets('a timer that fires under the guard does not hide', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);
      await mouse.moveTo(_nowhere);
      await tester.pump();
      final hold = rig.controller.holdAutoHide();

      rig.clock.advance(const Duration(milliseconds: 300));
      await settleMotion(tester);

      expect(rig.controller.state.value.isVisible, isTrue);
      hold.release();
    });

    testWidgets(
      'releasing the guard with the pointer away starts the idle delay',
      (tester) async {
        final rig = PopupRig();
        await rig.pump(tester);
        final mouse = await rig.mouse(tester);
        await mouse.moveTo(_toggleCentre);
        await settleMotion(tester);
        final hold = rig.controller.holdAutoHide();
        await mouse.moveTo(_nowhere);
        await tester.pump();

        hold.release();
        rig.clock.advance(const Duration(milliseconds: 2999));
        await settleMotion(tester);
        expect(rig.controller.state.value.isVisible, isTrue);
        rig.clock.advance(const Duration(milliseconds: 1));
        await settleMotion(tester);

        expect(rig.controller.state.value, PanelVisibility.hidden);
      },
    );

    testWidgets('search focus keeps the popup open', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);
      rig.shell.openSearch();
      await tester.pump();

      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(const Duration(seconds: 10));
      await settleMotion(tester);

      expect(rig.controller.state.value.isVisible, isTrue);
    });

    testWidgets('a drag of a page keeps it open until the page is idle', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);
      final host = rig.shell.hostFor('emoji');

      host.reportScrollActivity(const PageScrollDrag(12));
      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(const Duration(seconds: 10));
      expect(rig.controller.autoHideGuard.value, isTrue);
      expect(rig.controller.state.value.isVisible, isTrue);

      host.reportScrollActivity(const PageScrollIdle());
      expect(rig.controller.autoHideGuard.value, isFalse);
    });
  });

  group('delayed hide after interaction', () {
    testWidgets('an interaction with the pointer away hides after 3 s', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);
      await rig.mouse(tester);

      rig.shell.selectPage('stickers');
      await tester.pump();
      rig.clock.advance(const Duration(milliseconds: 2999));
      await settleMotion(tester);
      expect(rig.controller.state.value.isVisible, isTrue);
      rig.clock.advance(const Duration(milliseconds: 1));
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('each interaction restarts the 3 s', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);
      await rig.mouse(tester);

      rig.shell.selectPage('stickers');
      rig.clock.advance(const Duration(seconds: 2));
      rig.shell.selectPage('emoji');
      rig.clock.advance(const Duration(seconds: 2));
      await settleMotion(tester);
      expect(rig.controller.state.value.isVisible, isTrue);

      rig.clock.advance(const Duration(seconds: 1));
      await settleMotion(tester);
      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets(
      'an interaction with the pointer inside the popup arms nothing',
      (tester) async {
        final rig = PopupRig();
        await rig.pump(tester);
        final mouse = await rig.mouse(tester, at: _popupCentre);
        rig.controller.show();
        await settleMotion(tester);
        await mouse.moveBy(const Offset(1, 1));
        await tester.pump();

        rig.shell.selectPage('stickers');
        await tester.pump();
        rig.clock.advance(const Duration(seconds: 10));
        await settleMotion(tester);

        expect(rig.controller.state.value.isVisible, isTrue);
      },
    );

    testWidgets('a touch-driven popup does not time out', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);
      final touch = await tester.startGesture(_popupCentre);
      await touch.up();
      await tester.pump();

      rig.shell.selectPage('stickers');
      await tester.pump();
      rig.clock.advance(const Duration(seconds: 10));
      await settleMotion(tester);

      expect(rig.controller.state.value.isVisible, isTrue);
    });
  });
}

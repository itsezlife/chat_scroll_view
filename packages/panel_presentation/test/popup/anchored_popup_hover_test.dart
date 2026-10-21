import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
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

    testWidgets('a dock standing in a wide window is not joined by a popup '
        'on hover', (tester) async {
      final rig = PopupRig(window: const PanelWindow(width: 900, height: 700));
      rig.controller.dock();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);

      await mouse.moveTo(_toggleCentre);
      await tester.pump();

      expect(rig.controller.state.value.kind, const Docked());
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
    // Reference client: the toggle's leave arms a 0 ms timer, which the
    // popup's enter cancels because the two rectangles touch.
    testWidgets(
      'leaving the toggle hides on the next event pass, not at once',
      (tester) async {
        final rig = PopupRig();
        await rig.pump(tester);
        final mouse = await rig.mouse(tester);
        await mouse.moveTo(_toggleCentre);
        await settleMotion(tester);

        await mouse.moveTo(_nowhere);
        await tester.pump();
        expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
        expect(rig.clock.pendingCount, 1);

        rig.clock.advance(Duration.zero);
        await tester.pump();
        expect(rig.controller.state.value, isA<PanelVisibility$Hiding>());
        await settleMotion(tester);
        expect(rig.controller.state.value, PanelVisibility.hidden);
      },
    );

    testWidgets('moving from the toggle straight into the popup cancels it', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);

      await mouse.moveTo(_popupCentre);
      await tester.pump();
      rig.clock.advance(const Duration(seconds: 1));
      await settleMotion(tester);

      expect(
        rig.controller.state.value,
        const PanelVisibility.shown(AnchoredPopup()),
      );
    });

    testWidgets(
      'no dead zone: a pointer crossing the gap from the toggle up to the '
      'popup never lets it hide',
      (tester) async {
        final rig = PopupRig();
        // A composer 120 px tall puts the toggle (650..690) 70 px under the
        // popup's bottom edge, far more than the shadow gutter alone covers.
        await rig.pump(
          tester,
          composerRect: const Rect.fromLTWH(0, 580, 800, 120),
        );
        final mouse = await rig.mouse(tester);
        await mouse.moveTo(_toggleCentre);
        await settleMotion(tester);

        for (var y = 670.0; y >= 400; y -= 2) {
          await mouse.moveTo(Offset(760, y));
          await tester.pump();
          rig.clock.advance(Duration.zero);
          expect(
            rig.controller.state.value,
            isA<PanelVisibility$Shown>(),
            reason: 'hid with the pointer at y=$y',
          );
        }
        rig.clock.advance(const Duration(seconds: 1));
        expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
      },
    );

    testWidgets('no dead zone across the style\'s edge gap either', (
      tester,
    ) async {
      final rig = PopupRig(
        style: const AnchoredPopupStyle(width: 300, edgeGap: 10),
      );
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);

      for (var y = 670.0; y >= 400; y -= 1) {
        await mouse.moveTo(Offset(760, y));
        await tester.pump();
        rig.clock.advance(Duration.zero);
        expect(
          rig.controller.state.value,
          isA<PanelVisibility$Shown>(),
          reason: 'hid with the pointer at y=$y',
        );
      }
    });

    testWidgets('the shadow gutter around the popup counts as inside it', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester, at: _popupCentre);
      rig.controller.show();
      await settleMotion(tester);
      // 300 wide at the end edge: the card's left edge is x=500, its top is
      // 640 - 525 = 115 in a 700 px window; 4 px outside is within the gutter.
      await mouse.moveTo(const Offset(496, 400));
      await tester.pump();
      rig.clock.advance(const Duration(seconds: 5));
      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());

      await mouse.moveTo(const Offset(480, 400));
      await tester.pump();
      rig.clock.advance(const Duration(milliseconds: 300));
      await settleMotion(tester);
      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('leaving the popup hides after 300 ms, not before', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester, at: _popupCentre);
      rig.controller.show();
      await settleMotion(tester);

      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(const Duration(milliseconds: 299));
      await settleMotion(tester);
      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());

      rig.clock.advance(const Duration(milliseconds: 1));
      await settleMotion(tester);
      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('leaving the popup while it is still appearing hides at the '
        'next pass, with no grace', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester, at: _popupCentre);
      rig.controller.show();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.controller.state.value, isA<PanelVisibility$Showing>());

      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(Duration.zero);
      await tester.pump();

      expect(rig.controller.state.value, isA<PanelVisibility$Hiding>());
    });

    testWidgets('re-entering the toggle during the popup grace keeps it open', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester, at: _popupCentre);
      rig.controller.show();
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
      rig.clock.advance(Duration.zero);
      await tester.pump(const Duration(milliseconds: 20));
      expect(rig.controller.state.value, isA<PanelVisibility$Hiding>());

      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);

      expect(
        rig.controller.state.value,
        const PanelVisibility.shown(AnchoredPopup()),
      );
    });

    testWidgets('entering the popup while it is hiding shows it again', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);
      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(Duration.zero);
      await tester.pump(const Duration(milliseconds: 20));
      expect(rig.controller.state.value, isA<PanelVisibility$Hiding>());

      await mouse.moveTo(_popupCentre);
      await settleMotion(tester);

      expect(
        rig.controller.state.value,
        const PanelVisibility.shown(AnchoredPopup()),
      );
      rig.clock.advance(const Duration(seconds: 5));
      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
    });

    testWidgets('a click-opened popup also hides when the pointer leaves it', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester, at: _popupCentre);
      rig.controller.toggle();
      await settleMotion(tester);

      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(const Duration(milliseconds: 300));
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('a toggle that unmounts under the pointer is left, not stuck', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);
      final hold = rig.controller.holdAutoHide();

      // The toggle leaves the tree with the pointer still over it, and the
      // pointer then goes elsewhere: nothing says it is still on the toggle.
      await rig.pump(tester, withToggle: false);
      await mouse.moveTo(_nowhere);
      await tester.pump();
      hold.release();
      rig.clock.advance(const Duration(seconds: 3));
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });
  });

  group('holds', () {
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

    testWidgets('a leave that happened under a hold hides 3 s after the '
        'release, not 300 ms', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);
      final hold = rig.controller.holdAutoHide();
      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(const Duration(seconds: 1));

      hold.release();
      rig.clock.advance(const Duration(milliseconds: 2999));
      await settleMotion(tester);
      expect(rig.controller.state.value.isVisible, isTrue);
      rig.clock.advance(const Duration(milliseconds: 1));
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('releasing a hold with the pointer still inside arms nothing', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester, at: _popupCentre);
      rig.controller.show();
      await settleMotion(tester);
      final hold = rig.controller.holdAutoHide();
      await mouse.moveBy(const Offset(1, 1));
      await tester.pump();

      hold.release();
      rig.clock.advance(const Duration(seconds: 10));

      expect(rig.clock.pendingCount, 0);
      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
    });

    testWidgets('search focus is not a hold: with the pointer away the leave '
        'rule applies', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(_toggleCentre);
      await settleMotion(tester);
      rig.shell.openSearch();
      await tester.pump();
      expect(rig.controller.autoHideGuard.value, isFalse);

      await mouse.moveTo(_nowhere);
      await tester.pump();
      rig.clock.advance(Duration.zero);
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('search focus with the pointer inside keeps it open', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester, at: _popupCentre);
      rig.controller.show();
      await settleMotion(tester);

      rig.shell.openSearch();
      await tester.pump();
      rig.clock.advance(const Duration(seconds: 10));
      await settleMotion(tester);

      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
      await mouse.moveBy(const Offset(1, 1));
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

    testWidgets(
      'a button pressed inside the popup holds it while the pointer drags out; '
      '3 s after the release it hides',
      (tester) async {
        final rig = PopupRig();
        await rig.pump(tester);
        final mouse = await rig.mouse(tester, at: _popupCentre);
        rig.controller.show();
        await settleMotion(tester);

        await mouse.down(_popupCentre);
        await tester.pump();
        expect(rig.controller.autoHideGuard.value, isTrue);
        await mouse.moveTo(_nowhere);
        await tester.pump();
        rig.clock.advance(const Duration(seconds: 10));
        await settleMotion(tester);
        expect(rig.controller.state.value, isA<PanelVisibility$Shown>());

        await mouse.up();
        await tester.pump();
        expect(rig.controller.autoHideGuard.value, isFalse);
        rig.clock.advance(const Duration(milliseconds: 2999));
        expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
        rig.clock.advance(const Duration(milliseconds: 1));
        await settleMotion(tester);
        expect(rig.controller.state.value, PanelVisibility.hidden);
      },
    );

    testWidgets('a press that began outside the popup is not a hold', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);
      final mouse = await rig.mouse(tester);

      await mouse.down(_toggleCentre);
      await tester.pump();

      expect(rig.controller.autoHideGuard.value, isFalse);
      await mouse.up();
    });
  });

  group('no other idle timer', () {
    testWidgets('an interaction in the panel with the pointer away arms '
        'nothing', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);
      await rig.mouse(tester);

      rig.shell.selectPage('stickers');
      await tester.pump();
      rig.clock.advance(const Duration(seconds: 30));
      await settleMotion(tester);

      expect(rig.clock.pendingCount, 0);
      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
    });

    testWidgets('a touch-driven popup does not time out after a hold either', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);
      final touch = await tester.startGesture(_popupCentre);
      await touch.up();
      await tester.pump();

      final hold = rig.controller.holdAutoHide()..release();
      rig.clock.advance(const Duration(seconds: 10));
      await settleMotion(tester);

      expect(hold, isNotNull);
      expect(rig.controller.state.value.isVisible, isTrue);
    });

    testWidgets('touch flags do not survive the popup: after it hides a '
        'click-open times out after a hold', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);
      final touch = await tester.startGesture(_popupCentre);
      await touch.up();
      await tester.pump();
      rig.controller.hide();
      await settleMotion(tester);
      expect(rig.controller.state.value, PanelVisibility.hidden);

      rig.controller.toggle();
      await settleMotion(tester);
      rig.controller.holdAutoHide().release();
      rig.clock.advance(const Duration(seconds: 3));
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });
  });

  group('outside press', () {
    testWidgets('a press on a registered exempt region does not dismiss', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester, exemptRect: const Rect.fromLTWH(20, 650, 300, 40));
      rig.controller.toggle();
      await settleMotion(tester);

      final mouse = await rig.mouse(tester);
      await mouse.down(const Offset(100, 670));
      await tester.pump();
      await mouse.up();
      await settleMotion(tester);

      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
    });

    testWidgets('a press just outside that region still dismisses', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester, exemptRect: const Rect.fromLTWH(20, 650, 300, 40));
      rig.controller.toggle();
      await settleMotion(tester);

      final mouse = await rig.mouse(tester);
      await mouse.down(const Offset(100, 600));
      await mouse.up();
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('a press in the popup\'s own gutter is not outside', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);

      final mouse = await rig.mouse(tester);
      await mouse.down(const Offset(496, 400));
      await mouse.up();
      await settleMotion(tester);

      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
    });

    testWidgets('an exempt region that unmounts stops exempting', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester, exemptRect: const Rect.fromLTWH(20, 650, 300, 40));
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);

      final mouse = await rig.mouse(tester);
      await mouse.down(const Offset(100, 670));
      await mouse.up();
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });
  });
}

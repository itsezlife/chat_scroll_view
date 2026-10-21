import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_shell/panel_shell.dart';

import 'popup_rig.dart';

Rect _popupRect(WidgetTester tester) =>
    tester.getRect(find.byType(PanelShell).first);

void main() {
  group('arrangement', () {
    testWidgets('is the pointer one: the tabs are above the search field', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);

      rig.controller.show();
      await settleMotion(tester);

      expect(
        tester.widget<PanelShell>(find.byType(PanelShell)).arrangement,
        PanelArrangement.pointer,
      );
    });
  });

  testWidgets('is the composer\'s glass, rounded as the card', (tester) async {
    final rig = PopupRig(
      style: const AnchoredPopupStyle(width: 300, cornerRadius: 14),
    );
    await rig.pump(tester);

    rig.controller.show();
    await settleMotion(tester);

      final glass = find.ancestor(
        of: find.byType(PanelShell),
        matching: find.byType(GlassSurface),
      );
      expect(glass, findsOneWidget);
      expect(
        tester.widget<GlassSurface>(glass).material,
        GlassMaterial.composerIsland,
      );
      expect(
        tester.widget<PanelShell>(find.byType(PanelShell)).background,
        const Color(0x00000000),
        reason: 'the glass shows through the shell',
      );
    expect(
      tester
          .widget<GlassSurface>(
            find.ancestor(
              of: find.byType(PanelShell),
              matching: find.byType(GlassSurface),
            ),
          )
          .cornerRadius,
      14,
    );
  });

  group('geometry', () {
    testWidgets('sits on the composer top, end edges aligned (LTR)', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);

      rig.controller.show();
      await settleMotion(tester);

      final rect = _popupRect(tester);
      expect(rect.bottom, 640);
      expect(rect.right, 800);
      expect(rect.width, 300);
    });

    testWidgets('keeps the style\'s gap above the composer and inside its end '
        'edge (LTR)', (tester) async {
      final rig = PopupRig(
        style: const AnchoredPopupStyle(width: 300, edgeGap: 10),
      );
      await rig.pump(tester);

      rig.controller.show();
      await settleMotion(tester);

      final rect = _popupRect(tester);
      expect(rect.bottom, 640 - 10);
      expect(rect.right, 800 - 10);
    });

    testWidgets('keeps the gap at the start side in RTL', (tester) async {
      final rig = PopupRig(
        style: const AnchoredPopupStyle(width: 300, edgeGap: 10),
      );
      await rig.pump(tester, textDirection: TextDirection.rtl);

      rig.controller.show();
      await settleMotion(tester);

      final rect = _popupRect(tester);
      expect(rect.left, 10);
      expect(rect.bottom, 640 - 10);
    });

    testWidgets('mirrors in RTL: the end edge is the left one', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester, textDirection: TextDirection.rtl);

      rig.controller.show();
      await settleMotion(tester);

      final rect = _popupRect(tester);
      expect(rect.left, 0);
      expect(rect.bottom, 640);
    });

    testWidgets('follows an anchor that moves', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.show();
      await settleMotion(tester);

      rig.controller.anchor(const Rect.fromLTWH(0, 600, 700, 100));
      await tester.pump();

      final rect = _popupRect(tester);
      expect(rect.bottom, 600);
      expect(rect.right, 700);
    });

    testWidgets('stays inside the window when the anchor is near the edge', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.anchor(const Rect.fromLTWH(0, 640, 120, 60));
      rig.controller.show();
      await settleMotion(tester);

      expect(_popupRect(tester).left, 0);
    });

    testWidgets('is narrower than the style in a narrow window', (
      tester,
    ) async {
      final rig = PopupRig(
        style: const AnchoredPopupStyle(width: 360),
        window: const PanelWindow(width: 320, height: 700),
      );
      await rig.pump(tester, size: const Size(320, 700));

      rig.controller.show();
      await settleMotion(tester);

      expect(_popupRect(tester).width, 320);
    });

    testWidgets('takes no occupancy', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);

      rig.controller.show();
      await settleMotion(tester);

      expect(rig.controller.occupancy.value, PanelOccupancy.zero);
    });

    for (final (windowHeight, expected) in [
      (300.0, 278.0), // 0.75 x 300 = 225, raised to the minimum
      (400.0, 300.0), // 0.75 x 400, inside the clamp
      (700.0, 525.0),
      (1000.0, 640.0), // 0.75 x 1000 = 750, lowered to the maximum
    ]) {
      testWidgets('height $expected in a window $windowHeight tall', (
        tester,
      ) async {
        final rig = PopupRig(
          window: PanelWindow(width: 800, height: windowHeight),
        );
        await rig.pump(tester, size: Size(800, windowHeight));

        rig.controller.show();
        await settleMotion(tester);

        expect(_popupRect(tester).height, expected);
      });
    }

    testWidgets('re-sizes when the window is reported again', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.show();
      await settleMotion(tester);

      rig.controller.updateWindow(const PanelWindow(width: 800, height: 1000));
      await tester.pump();

      expect(_popupRect(tester).height, 640);
    });
  });

  group('motion', () {
    testWidgets('grows from the bottom-end corner and fades in', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);

      rig.controller.show();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byType(PanelShell),
          matching: find.byType(Opacity),
        ),
      );
      expect(rig.controller.state.value, isA<PanelVisibility$Showing>());
      final early = _popupRect(tester);
      expect(early.width, lessThan(300));
      expect(early.bottomRight, const Offset(800, 640));
      expect(opacity.opacity, inExclusiveRange(0, 1));

      await settleMotion(tester);
      final settled = _popupRect(tester);
      expect(settled.width, 300);
      expect(settled.bottomRight, const Offset(800, 640));
    });

    testWidgets('showing lasts the popupShow role, hiding the popupHide role', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      const motion = ChromeMotion.standard();

      rig.controller.show();
      await tester.pump();
      await tester.pump(
        motion.popupShow.duration - const Duration(milliseconds: 10),
      );
      expect(rig.controller.state.value, isA<PanelVisibility$Showing>());
      await tester.pump(const Duration(milliseconds: 20));
      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());

      rig.controller.hide();
      await tester.pump();
      await tester.pump(
        motion.popupHide.duration - const Duration(milliseconds: 10),
      );
      expect(rig.controller.state.value, isA<PanelVisibility$Hiding>());
      await tester.pump(const Duration(milliseconds: 20));
      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('instant motion speed settles in the first frame', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester, speed: ChromeMotionSpeed.instant);

      rig.controller.show();
      await tester.pump();
      await tester.pump();

      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
      expect(_popupRect(tester).width, 300);
    });
  });

  group('dismissal', () {
    testWidgets('a mouse press outside the popup hides it', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);

      final mouse = await rig.mouse(tester);
      await mouse.down(const Offset(20, 20));
      await mouse.up();
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('a touch press outside the popup hides it', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);

      await tester.tapAt(const Offset(20, 20));
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('a press inside the popup does not', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);

      await tester.tapAt(const Offset(600, 400));
      await settleMotion(tester);

      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
    });

    testWidgets('a press on the toggle is the toggle\'s: no hide, no re-show', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);

      final mouse = await rig.mouse(tester);
      await mouse.down(const Offset(760, 670));
      await tester.pump();

      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
      await mouse.up();
    });

    testWidgets('the press passes through to what is underneath', (
      tester,
    ) async {
      final rig = PopupRig();
      var taps = 0;
      await rig.pump(tester, onOutsideTap: () => taps++);
      rig.controller.toggle();
      await settleMotion(tester);

      await tester.tapAt(const Offset(20, 20));

      expect(taps, 1);
    });

    testWidgets('Escape closes search first, then the popup', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);
      rig.shell.openSearch();
      await tester.pump();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(rig.shell.search.value.isOpen, isFalse);
      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleMotion(tester);
      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('Escape with search closed closes the popup, from inside it', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);
      // The popup takes no focus on open; a keyboard user tabs into it.
      rig.composerFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<PanelShell>(),
        isNotNull,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('Escape with focus in the composer closes it too', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      rig.composerFocus.requestFocus();
      await mouse.moveTo(const Offset(760, 670));
      await settleMotion(tester);
      expect(rig.composerFocus.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleMotion(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('Escape does nothing when the popup is hidden', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(rig.controller.state.value, PanelVisibility.hidden);
    });
  });

  group('actions', () {
    testWidgets('the toggle intent toggles', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final context = tester.element(find.byKey(PopupRig.outsideKey));

      Actions.invoke(context, const AnchoredPopupToggleIntent());
      await settleMotion(tester);
      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());

      Actions.invoke(context, const AnchoredPopupToggleIntent());
      await settleMotion(tester);
      expect(rig.controller.state.value, PanelVisibility.hidden);
    });

    testWidgets('the search intent opens the panel and focuses search', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final context = tester.element(find.byKey(PopupRig.outsideKey));

      Actions.invoke(context, const PanelSearchIntent());
      await settleMotion(tester);

      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
      expect(rig.shell.search.value.isOpen, isTrue);
      expect(rig.shell.search.value.wantsFocus, isTrue);
    });
  });

  group('focus', () {
    testWidgets('a click-opened popup leaves the caret in the composer', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.composerFocus.requestFocus();
      await tester.pump();
      expect(rig.composerFocus.hasFocus, isTrue);

      rig.controller.toggle();
      await settleMotion(tester);

      expect(popupIsUp(tester), isTrue);
      expect(rig.composerFocus.hasFocus, isTrue);
    });

    testWidgets('a hover-opened popup leaves focus in the composer', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.composerFocus.requestFocus();
      await tester.pump();
      final mouse = await rig.mouse(tester);

      await mouse.moveTo(const Offset(760, 670));
      await settleMotion(tester);

      expect(rig.controller.state.value, isA<PanelVisibility$Shown>());
      expect(rig.composerFocus.hasFocus, isTrue);
    });

    testWidgets('opening does not focus the search field either', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.composerFocus.requestFocus();
      await tester.pump();

      rig.controller.toggle();
      await settleMotion(tester);

      expect(rig.shell.search.value.isOpen, isFalse);
      expect(rig.composerFocus.hasFocus, isTrue);
    });

    testWidgets('Tab from the composer still reaches the popup', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.composerFocus.requestFocus();
      rig.controller.toggle();
      await settleMotion(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(rig.composerFocus.hasFocus, isFalse);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<PanelShell>(),
        isNotNull,
      );
    });

    testWidgets('closing with search focused returns focus to the composer', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.composerFocus.requestFocus();
      rig.controller.toggle();
      await settleMotion(tester);
      rig.shell.openSearch();
      await settleMotion(tester);
      expect(rig.composerFocus.hasFocus, isFalse);

      rig.controller.hide();
      await settleMotion(tester);

      expect(rig.composerFocus.hasFocus, isTrue);
    });

    testWidgets('focus elsewhere is not pulled to the composer on close', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);
      rig.elsewhereFocus.requestFocus();
      await tester.pump();

      rig.controller.hide();
      await settleMotion(tester);

      expect(rig.composerFocus.hasFocus, isFalse);
      expect(rig.elsewhereFocus.hasFocus, isTrue);
    });
  });

  group('shell and controller wiring', () {
    testWidgets(
      'reports the shell present while showing and gone when hidden',
      (tester) async {
        final rig = PopupRig();
        await rig.pump(tester);

        rig.controller.show();
        await tester.pump();
        expect(rig.shell.opening.value, isTrue);
        await settleMotion(tester);
        expect(rig.shell.visible.value, isTrue);
        expect(rig.shell.opening.value, isFalse);

        rig.controller.hide();
        await settleMotion(tester);
        expect(rig.shell.visible.value, isFalse);
      },
    );

    testWidgets('page and search survive hide and show', (tester) async {
      final rig = PopupRig();
      await rig.pump(tester);
      rig.controller.toggle();
      await settleMotion(tester);
      rig.shell.selectPage('stickers');
      await tester.pump();

      rig.controller.hide();
      await settleMotion(tester);
      rig.controller.show();
      await settleMotion(tester);

      expect(rig.shell.selectedPageId.value, 'stickers');
    });

    testWidgets('disposing the strategy while closed leaves no timers', (
      tester,
    ) async {
      final rig = PopupRig();
      await rig.pump(tester);
      final mouse = await rig.mouse(tester);
      await mouse.moveTo(const Offset(760, 670));
      await settleMotion(tester);
      await mouse.moveTo(const Offset(20, 20));
      await tester.pump();
      expect(rig.clock.pendingCount, 1);

      rig.strategy.dispose();

      expect(rig.clock.pendingCount, 0);
    });
  });
}

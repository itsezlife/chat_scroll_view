import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
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
      final rig = DockedRig(dockPreferred: true);
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

    testWidgets('a narrowing window turns the section into a popup', (
      tester,
    ) async {
      final rig = DockedRig(dockPreferred: true);
      await rig.pump(tester);
      rig.controller.show();
      await settleDock(tester);

      rig.controller.updateWindow(const PanelWindow(width: 500, height: 600));
      await settleDock(tester);

      expect(rig.controller.state.value.kind, const AnchoredPopup());
      expect(rig.controller.occupancy.value, PanelOccupancy.zero);
      expect(_chatRect(tester).width, 1000);
    });

    testWidgets('widening again docks the section back', (tester) async {
      final rig = DockedRig(dockPreferred: true);
      await rig.pump(tester);
      rig.controller.show();
      await settleDock(tester);
      rig.controller.updateWindow(const PanelWindow(width: 500, height: 600));
      await settleDock(tester);

      rig.controller.updateWindow(const PanelWindow(width: 1000, height: 600));
      await settleDock(tester);

      expect(rig.controller.state.value.kind, const Docked());
      expect(rig.controller.occupancy.value.inlineEnd, 320);
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

    testWidgets('back hides the section', (tester) async {
      final rig = DockedRig();
      await rig.pump(tester);
      rig.controller.show(kind: const Docked());
      await settleDock(tester);

      expect(rig.controller.handleBack(), isTrue);
      await settleDock(tester);

      expect(rig.controller.state.value, PanelVisibility.hidden);
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
}

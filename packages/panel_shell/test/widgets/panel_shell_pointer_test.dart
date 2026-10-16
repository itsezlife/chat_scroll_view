/// The shell under the pointer arrangement: where the type tabs and the
/// floating bar go, when the bar hides, and what pages are told.
///
/// **Seam:** `PanelShell(arrangement:)` over a controller of fake pages, and
/// the `PanelArrangementScope` a page reads below it.
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/src/widgets/hold_repeat_button.dart';
import 'package:panel_shell/src/widgets/panel_bottom_bar.dart';
import 'package:panel_shell/src/widgets/panel_search_field.dart';
import 'package:panel_shell/src/widgets/panel_type_tabs.dart';
import 'package:panel_shell/testing.dart';

void main() {
  late FakePanelPage emoji;
  late FakePanelPage stickers;
  late PanelShellController controller;

  Future<void> pump(
    WidgetTester tester, {
    PanelArrangement? arrangement,
    List<FakePanelPage>? pages,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    controller = PanelShellController(
      pages: (pages ?? [emoji, stickers]).map((p) => p.page).toList(),
      preferences: FakePreferenceStore(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      PanelShellTestScope(
        child: MediaQuery(
          data: MediaQueryData(size: const Size(400, 600), padding: padding),
          child: PanelShell(
            controller: controller,
            announcer: FakePanelAnnouncer(),
            arrangement: arrangement ?? PanelArrangement.touch,
          ),
        ),
      ),
    );
  }

  setUp(() {
    emoji = FakePanelPage(
      'emoji',
      search: true,
      actions: const [PageAction.backspace()],
    );
    stickers = FakePanelPage('stickers');
  });

  double top(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder).dy;
  double bottom(WidgetTester tester, Finder finder) =>
      tester.getBottomLeft(finder).dy;

  group('what pages are told', () {
    testWidgets('a shell without an arrangement is touch', (tester) async {
      PanelArrangement? seen;
      controller = PanelShellController(
        pages: [
          PanelPage(
            id: 'probe',
            tab: const PanelTab(icon: ChromeIconId.emoji, labelKey: 'probe'),
            builder: (context, host) {
              seen = PanelArrangementScope.of(context);
              return const SizedBox();
            },
          ),
        ],
        preferences: FakePreferenceStore(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        PanelShellTestScope(
          child: PanelShell(
            controller: controller,
            announcer: FakePanelAnnouncer(),
          ),
        ),
      );

      expect(seen, PanelArrangement.touch);
    });

    testWidgets('a pointer shell tells its pages so', (tester) async {
      PanelArrangement? seen;
      controller = PanelShellController(
        pages: [
          PanelPage(
            id: 'probe',
            tab: const PanelTab(icon: ChromeIconId.emoji, labelKey: 'probe'),
            builder: (context, host) {
              seen = PanelArrangementScope.of(context);
              return const SizedBox();
            },
          ),
        ],
        preferences: FakePreferenceStore(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        PanelShellTestScope(
          child: PanelShell(
            controller: controller,
            announcer: FakePanelAnnouncer(),
            arrangement: PanelArrangement.pointer,
          ),
        ),
      );

      expect(seen, PanelArrangement.pointer);
    });

    testWidgets('outside any shell the arrangement is touch', (tester) async {
      PanelArrangement? seen;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = PanelArrangementScope.of(context);
            return const SizedBox();
          },
        ),
      );

      expect(seen, PanelArrangement.touch);
    });

    testWidgets('pages keep the room for the floating bar, safe inset apart', (
      tester,
    ) async {
      await pump(
        tester,
        arrangement: PanelArrangement.pointer,
        padding: const EdgeInsets.only(bottom: 20),
      );
      final inner = tester.element(find.text('page emoji'));

      // The strip a page pins at the bottom sits above the safe inset, which
      // the shell keeps for itself: the page is told the bar's room only.
      expect(MediaQuery.paddingOf(inner).bottom, PanelBottomBar.height);
      expect(bottom(tester, find.text('page emoji')), lessThan(600 - 20));
    });
  });

  group('type tabs', () {
    testWidgets('sit above the search field, not in the bottom bar', (
      tester,
    ) async {
      await pump(tester, arrangement: PanelArrangement.pointer);

      final tabs = find.byType(PanelTypeTabs);
      expect(tabs, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PanelBottomBar),
          matching: find.byType(PanelTypeTabs),
        ),
        findsNothing,
      );
      expect(
        bottom(tester, tabs),
        lessThanOrEqualTo(top(tester, find.byType(PanelSearchField))),
      );
      expect(top(tester, tabs), lessThan(PanelTypeTabs.height + 16));
    });

    testWidgets('stay in the bottom bar under touch', (tester) async {
      await pump(tester);

      expect(
        find.descendant(
          of: find.byType(PanelBottomBar),
          matching: find.byType(PanelTypeTabs),
        ),
        findsOneWidget,
      );
    });

    testWidgets('are not drawn for one page', (tester) async {
      await pump(tester, arrangement: PanelArrangement.pointer, pages: [emoji]);

      expect(find.byType(PanelTypeTabs), findsNothing);
      expect(top(tester, find.byType(PanelSearchField)), 0);
    });

    testWidgets('selecting one still selects the page', (tester) async {
      await pump(tester, arrangement: PanelArrangement.pointer);

      await tester.tap(find.text('Stickers'));
      await tester.pumpAndSettle();

      expect(controller.selectedPageId.value, 'stickers');
    });
  });

  group('the floating bar', () {
    double barTop(WidgetTester tester) =>
        top(tester, find.byType(PanelBottomBar));

    testWidgets('holds the page action and nothing else', (tester) async {
      await pump(tester, arrangement: PanelArrangement.pointer);

      expect(
        find.descendant(
          of: find.byType(PanelBottomBar),
          matching: find.byType(HoldRepeatButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a wheel step (a drag report) does not hide it', (
      tester,
    ) async {
      await pump(tester, arrangement: PanelArrangement.pointer);
      final shown = barTop(tester);

      emoji.host!.reportScrollActivity(const PageScrollDrag(120));
      await tester.pumpAndSettle();

      expect(barTop(tester), shown);
    });

    testWidgets('a fling does not hide it either', (tester) async {
      await pump(tester, arrangement: PanelArrangement.pointer);
      final shown = barTop(tester);

      emoji.host!.reportScrollActivity(const PageScrollFling(300));
      await tester.pumpAndSettle();

      expect(barTop(tester), shown);
    });

    testWidgets('touch hides it on the same report', (tester) async {
      await pump(tester);
      final shown = barTop(tester);

      emoji.host!.reportScrollActivity(const PageScrollDrag(120));
      await tester.pumpAndSettle();

      expect(barTop(tester), greaterThan(shown + 40));
    });

    testWidgets('is hidden while search is open and back when it closes', (
      tester,
    ) async {
      await pump(tester, arrangement: PanelArrangement.pointer);
      final shown = barTop(tester);

      controller.openSearch();
      await tester.pumpAndSettle();
      expect(barTop(tester), greaterThan(shown + 40));

      controller.closeSearch();
      await tester.pumpAndSettle();
      expect(barTop(tester), shown);
    });

    testWidgets('sits at the end side of the bottom edge', (tester) async {
      await pump(tester, arrangement: PanelArrangement.pointer);

      final button = find.byType(HoldRepeatButton);
      expect(
        tester.getBottomRight(button).dx,
        tester.getSize(find.byType(PanelShell)).width -
            PanelBottomBar.padHorizontal,
      );
      expect(bottom(tester, button), 600 - PanelBottomBar.padBottom);
    });

    testWidgets('rises above the strip a page pins at the bottom', (
      tester,
    ) async {
      await pump(tester, arrangement: PanelArrangement.pointer);
      final button = find.byType(HoldRepeatButton);
      final resting = bottom(tester, button);

      emoji.host!.reportBottomExtent(36);
      await tester.pumpAndSettle();

      expect(bottom(tester, button), resting - 36);

      emoji.host!.reportBottomExtent(0);
      await tester.pumpAndSettle();
      expect(bottom(tester, button), resting);
    });

    testWidgets('an extent reported by a page that is not selected is kept '
        'for when it is', (tester) async {
      await pump(tester, arrangement: PanelArrangement.pointer);
      final button = find.byType(HoldRepeatButton);
      final resting = bottom(tester, button);

      emoji.host!.reportBottomExtent(36);
      controller.selectPage('stickers');
      await tester.pumpAndSettle();
      // The stickers page has no actions and reported nothing.
      expect(find.byType(HoldRepeatButton), findsNothing);

      controller.selectPage('emoji');
      await tester.pumpAndSettle();
      expect(bottom(tester, button), resting - 36);
    });

    testWidgets('stays above the safe inset', (tester) async {
      await pump(
        tester,
        arrangement: PanelArrangement.pointer,
        padding: const EdgeInsets.only(bottom: 20),
      );

      expect(
        bottom(tester, find.byType(HoldRepeatButton)),
        600 - 20 - PanelBottomBar.padBottom,
      );
    });
  });
}

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
import 'package:panel_shell/src/widgets/panel_pager.dart';
import 'package:panel_shell/src/widgets/panel_type_tabs.dart';
import 'package:panel_shell/testing.dart';

const _extra = PageAction(
  id: 'extra',
  icon: ChromeIconId.attach,
  semanticLabel: _extraLabel,
);

String _extraLabel(ChromeStrings strings) => 'Extra';

/// The buttons of the bottom bar's action row.
final _actionButton = find.descendant(
  of: find.byType(PanelBottomBar),
  matching: find.byType(ScalePressable),
);

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
    emoji = FakePanelPage('emoji', search: true, actions: const [_extra]);
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

    testWidgets('shrink to fit a narrow shell instead of overflowing it', (
      tester,
    ) async {
      controller = PanelShellController(
        pages: [emoji, stickers].map((p) => p.page).toList(),
        preferences: FakePreferenceStore(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        PanelShellTestScope(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 180,
              height: 600,
              child: PanelShell(
                controller: controller,
                announcer: FakePanelAnnouncer(),
                arrangement: PanelArrangement.pointer,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tabs = tester.getRect(find.byType(PanelTypeTabs));
      expect(
        tabs.width,
        lessThanOrEqualTo(180 - 2 * PanelBottomBar.padHorizontal),
      );
      expect(tester.takeException(), isNull);
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

      expect(_actionButton, findsOneWidget);
    });

    testWidgets('has no backspace, which is a touch idiom: a keyboard has '
        'its own', (tester) async {
      emoji = FakePanelPage(
        'emoji',
        search: true,
        actions: const [PageAction.backspace()],
      );
      await pump(tester, arrangement: PanelArrangement.pointer);

      expect(find.byType(HoldRepeatButton), findsNothing);
      expect(find.byType(PanelBottomBar), findsNothing);
    });

    testWidgets('leaves the page its whole column when there is no bar', (
      tester,
    ) async {
      emoji = FakePanelPage(
        'emoji',
        search: true,
        actions: const [PageAction.backspace()],
      );
      await pump(tester, arrangement: PanelArrangement.pointer);

      expect(
        tester.getSize(find.text('page emoji')).height,
        greaterThan(0),
        reason: 'the pager has a viewport',
      );
      expect(tester.getSize(find.byType(PanelPager)).height, greaterThan(300));
    });

    testWidgets('keeps the page\'s other actions beside a backspace it '
        'leaves out', (tester) async {
      emoji = FakePanelPage(
        'emoji',
        search: true,
        actions: const [PageAction.backspace(), _extra],
      );
      await pump(tester, arrangement: PanelArrangement.pointer);

      expect(find.byType(HoldRepeatButton), findsNothing);
      expect(_actionButton, findsOneWidget);
    });

    testWidgets('touch still offers backspace', (tester) async {
      emoji = FakePanelPage(
        'emoji',
        search: true,
        actions: const [PageAction.backspace()],
      );
      await pump(tester);

      expect(find.byType(HoldRepeatButton), findsOneWidget);
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

      final button = _actionButton;
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
      final button = _actionButton;
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
      final button = _actionButton;
      final resting = bottom(tester, button);

      emoji.host!.reportBottomExtent(36);
      controller.selectPage('stickers');
      await tester.pumpAndSettle();
      // The stickers page has no actions and reported nothing.
      expect(_actionButton, findsNothing);

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
        bottom(tester, _actionButton),
        600 - 20 - PanelBottomBar.padBottom,
      );
    });
  });

  group('the search field', () {
    testWidgets('is the page\'s own under pointer too when it declares inline: '
        'it scrolls with the content', (tester) async {
      emoji = FakePanelPage(
        'emoji',
        search: true,
        searchPlacement: SearchPlacement.inline,
        actions: const [_extra],
      );
      await pump(tester, arrangement: PanelArrangement.pointer);

      expect(find.byType(PanelSearchField), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(PanelSearchField),
          matching: find.byType(PanelPager),
        ),
        findsOneWidget,
        reason: 'inside the page, among its content',
      );
    });

    testWidgets('is the shell\'s under pointer when the page declares it '
        'pinned', (tester) async {
      await pump(tester, arrangement: PanelArrangement.pointer);

      expect(find.byType(PanelSearchField), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(PanelSearchField),
          matching: find.byType(PanelPager),
        ),
        findsNothing,
        reason: 'above the pager, which holds none of its own',
      );
    });

    testWidgets('is the page\'s own under touch when it declares inline', (
      tester,
    ) async {
      emoji = FakePanelPage(
        'emoji',
        search: true,
        searchPlacement: SearchPlacement.inline,
      );
      await pump(tester);

      expect(find.byType(PanelSearchField), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(PanelSearchField),
          matching: find.byType(PanelPager),
        ),
        findsOneWidget,
        reason: 'inside the page, among its content',
      );
    });

    testWidgets('has a cancel control only while there is text: pressing it '
        'empties the query and leaves search open', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, arrangement: PanelArrangement.pointer);
      controller
        ..openSearch()
        ..setQuery('cat');
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.search.value.query, '');
      expect(controller.search.value.isOpen, isTrue);
      expect(find.bySemanticsLabel('Cancel'), findsNothing);
      semantics.dispose();
    });

    testWidgets('has no cancel control for an empty query, open or not', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, arrangement: PanelArrangement.pointer);
      expect(find.bySemanticsLabel('Cancel'), findsNothing);

      controller.openSearch();
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Cancel'), findsNothing);
      semantics.dispose();
    });

    testWidgets('has no control that closes search under touch', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      controller.openSearch();
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Cancel'), findsNothing);
      expect(find.bySemanticsLabel('Clear'), findsNothing);
      semantics.dispose();
    });
  });
}

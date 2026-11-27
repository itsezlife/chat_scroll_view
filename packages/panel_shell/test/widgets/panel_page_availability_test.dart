/// Page availability: the host sets a page `available`, `dimmed(hint)`,
/// `hidden` or `replaced(text)` on the controller, and the shell follows.
///
/// **Seam:** `PanelShellController.setPageAvailability` and `selectPage`
/// over fake pages, observed through the controller's listenables and
/// events, the recorded diagnostics, and the shell's widget tree.
library;

import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/src/widgets/panel_page_availability_view.dart';
import 'package:panel_shell/testing.dart';

void main() {
  late FakePreferenceStore preferences;
  late FakePanelPage emoji;
  late FakePanelPage gif;
  late FakePanelPage stickers;
  late PanelShellController controller;
  late List<PanelEvent> events;

  const hint = 'Stickers are not allowed here';
  const banText = 'The admins of this group do not allow stickers';
  const chat = ChatCorrelation(chatId: 'chat-1');

  void build() {
    controller = PanelShellController(
      pages: [emoji.page, gif.page, stickers.page],
      preferences: preferences,
    );
    controller.events.listen(events.add);
    addTearDown(controller.dispose);
  }

  Future<void> pump(
    WidgetTester tester, {
    TextDirection direction = TextDirection.ltr,
    PanelArrangement arrangement = PanelArrangement.touch,
  }) => tester.pumpWidget(
    PanelShellTestScope(
      textDirection: direction,
      child: PanelShell(
        controller: controller,
        arrangement: arrangement,
        announcer: FakePanelAnnouncer(),
      ),
    ),
  );

  Finder tabOf(String label) => find.text(label);

  setUp(() {
    preferences = FakePreferenceStore();
    events = [];
    emoji = FakePanelPage(
      'emoji',
      search: true,
      actions: const [PageAction.backspace()],
    );
    gif = FakePanelPage('gif', search: true);
    stickers = FakePanelPage('stickers', search: true);
  });

  group('controller', () {
    test('every page starts at its registered availability', () {
      build();

      expect(
        controller.availability.value.values,
        everyElement(const PageAvailability.available()),
      );
      expect(controller.shownPages.value.map((p) => p.id), [
        'emoji',
        'gif',
        'stickers',
      ]);
    });

    test('a dimmed selected page moves the panel to the first selectable '
        'page, unpersisted, and reports the form without its text', () {
      final recorded = RecordingDiagnostics.install();
      build();
      controller.selectPage('stickers');
      events.clear();

      controller.setPageAvailability(
        'stickers',
        const PageAvailability.dimmed(hint),
        correlation: chat,
      );

      expect(controller.selectedPageId.value, 'emoji');
      expect(events, [const PageChanged('emoji')]);
      expect(preferences.selectedPageId, 'stickers');
      final event = recorded
          .whereCategory(ChatEventCategory.capabilities)
          .single;
      expect(event.op, PanelShellOp.pageAvailability);
      expect(event.level, ChatEventLevel.debug);
      expect(event.correlation.chatId, 'chat-1');
      expect(event.fields, {
        'page': 'stickers',
        'form': 'dimmed',
        'movedTo': 'emoji',
      });
      expect(event.fields.values, isNot(contains(hint)));
    });

    test('the same value again changes nothing and reports nothing', () {
      final recorded = RecordingDiagnostics.install();
      build();
      controller
        ..setPageAvailability('gif', const PageAvailability.hidden())
        ..setPageAvailability('gif', const PageAvailability.hidden())
        ..setPageAvailability('nope', const PageAvailability.hidden());

      expect(recorded.events, hasLength(1));
    });

    test('a remembered page that cannot be selected starts on the first '
        'selectable one', () async {
      await preferences.setSelectedPageId('stickers');
      controller = PanelShellController(
        pages: [
          emoji.page,
          PanelPage(
            id: 'stickers',
            tab: stickers.page.tab,
            builder: stickers.page.builder,
            availability: const PageAvailability.dimmed(hint),
          ),
        ],
        preferences: preferences,
      );
      addTearDown(controller.dispose);

      expect(controller.selectedPageId.value, 'emoji');
    });

    test('a hidden page leaves the shown pages and refuses a selection '
        'silently', () {
      build();
      controller
        ..setPageAvailability('gif', const PageAvailability.hidden())
        ..selectPage('gif');

      expect(controller.shownPages.value.map((p) => p.id), [
        'emoji',
        'stickers',
      ]);
      expect(controller.selectedPageId.value, 'emoji');
      expect(events, isEmpty);
    });

    test('a replaced page is selectable but offers none of its search or '
        'actions, and an open search closes', () {
      build();
      controller
        ..selectPage('stickers')
        ..openSearch();
      expect(controller.search.value.isOpen, isTrue);

      controller.setPageAvailability(
        'stickers',
        const PageAvailability.replaced(banText),
      );

      expect(controller.selectedPageId.value, 'stickers');
      expect(controller.search.value.isOpen, isFalse);
      expect(controller.selectedCapabilities.search, isFalse);
      controller.openSearch();
      expect(controller.search.value.isOpen, isFalse);
    });

    test('a page listenable signals for its own page only', () {
      build();
      var stickerSignals = 0;
      controller.availabilityOf('stickers').addListener(() => stickerSignals++);

      controller.setPageAvailability('gif', const PageAvailability.hidden());
      expect(stickerSignals, 0);
      controller.setPageAvailability(
        'stickers',
        const PageAvailability.replaced(),
      );
      expect(stickerSignals, 1);
      expect(
        controller.availabilityOf('stickers').value,
        const PageAvailability.replaced(),
      );
    });

    test('the platform forms', () {
      expect(
        PageUnavailableForm.forPlatform(TargetPlatform.android).withText(hint),
        const PageAvailability.dimmed(hint),
      );
      expect(
        PageUnavailableForm.forPlatform(TargetPlatform.iOS).withText(hint),
        const PageAvailability.hidden(),
      );
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          PageUnavailableForm.forPlatform(platform).withText(banText),
          const PageAvailability.replaced(banText),
        );
      }
    });
  });

  group('dimmed', () {
    testWidgets('the tab is drawn at 0.15 alpha', (tester) async {
      build();
      controller.setPageAvailability(
        'stickers',
        const PageAvailability.dimmed(hint),
      );
      await pump(tester);

      expect(opacityOf(tester, tabOf('Stickers')), 0.15);
      expect(opacityOf(tester, tabOf('GIF')), 1);
    });

    testWidgets('dimming the page on screen moves the panel to emoji', (
      tester,
    ) async {
      build();
      controller.selectPage('stickers');
      await pump(tester);
      expect(find.text('page stickers'), findsOneWidget);

      controller.setPageAvailability(
        'stickers',
        const PageAvailability.dimmed(hint),
      );
      await tester.pumpAndSettle();

      expect(find.text('page emoji'), findsOneWidget);
      expect(find.text('page stickers'), findsNothing);
    });

    testWidgets('a tap does not switch and shows the hint for 3.5 s', (
      tester,
    ) async {
      build();
      controller.setPageAvailability(
        'stickers',
        const PageAvailability.dimmed(hint),
      );
      await pump(tester);

      await tester.tap(tabOf('Stickers'));
      await tester.pump();

      expect(controller.selectedPageId.value, 'emoji');
      expect(events, [const PageDenied('stickers')]);
      expect(find.text(hint), findsOneWidget);
      expectChromeText(tester, within: find.byType(PanelTabHint));

      // Above the tab, centred on it.
      final tip = tester.getRect(find.byType(DecoratedBox).last);
      final tab = tester.getRect(
        find.ancestor(
          of: tabOf('Stickers'),
          matching: find.byType(CompositedTransformTarget),
        ),
      );
      expect(tip.bottom, lessThan(tab.top));
      expect(tip.center.dx, moreOrLessEquals(tab.center.dx, epsilon: 0.5));

      await tester.pump(const Duration(milliseconds: 3400));
      expect(find.text(hint), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(hint), findsNothing);
    });

    testWidgets('a burst of taps is one attempt per guard window', (
      tester,
    ) async {
      build();
      controller.setPageAvailability(
        'stickers',
        const PageAvailability.dimmed(hint),
      );
      await pump(tester);

      for (var i = 0; i < 5; i++) {
        await tester.tap(tabOf('Stickers'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(events, [const PageDenied('stickers')]);
      expect(find.text(hint), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.tap(tabOf('Stickers'));
      await tester.pump();
      expect(events, [
        const PageDenied('stickers'),
        const PageDenied('stickers'),
      ]);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a swipe onto the page slides back', (tester) async {
      build();
      controller
        ..setPageAvailability('stickers', const PageAvailability.dimmed(hint))
        ..selectPage('gif');
      await pump(tester);
      events.clear();

      await tester.fling(find.text('page gif'), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();

      expect(controller.selectedPageId.value, 'gif');
      expect(find.text('page gif'), findsOneWidget);
      expect(events, [const PageDenied('stickers')]);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('the tab stays focusable and is spoken as not available, '
        'with the hint as its hint', (tester) async {
      final semantics = tester.ensureSemantics();
      build();
      controller.setPageAvailability(
        'stickers',
        const PageAvailability.dimmed(hint),
      );
      await pump(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Stickers, not available')),
        isSemantics(
          label: 'Stickers, not available',
          hint: hint,
          isButton: true,
          isFocusable: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('right to left: the tabs mirror and the hint follows its tab', (
      tester,
    ) async {
      build();
      controller.setPageAvailability(
        'stickers',
        const PageAvailability.dimmed(hint),
      );
      await pump(tester, direction: TextDirection.rtl);

      final emojiTab = tester.getCenter(tabOf('Emoji'));
      final stickersTab = tester.getCenter(tabOf('Stickers'));
      expect(stickersTab.dx, lessThan(emojiTab.dx));

      await tester.tap(tabOf('Stickers'));
      await tester.pump();
      final tip = tester.getCenter(find.text(hint));
      expect(tip.dx, moreOrLessEquals(stickersTab.dx, epsilon: 1));
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('under the pointer arrangement the hint hangs below the '
        'section tab', (tester) async {
      build();
      controller.setPageAvailability(
        'stickers',
        const PageAvailability.dimmed(hint),
      );
      await pump(tester, arrangement: PanelArrangement.pointer);

      await tester.tap(tabOf('Stickers'));
      await tester.pump();

      expect(
        tester.getRect(find.text(hint)).top,
        greaterThan(tester.getRect(tabOf('Stickers')).bottom),
      );
      expect(opacityOf(tester, tabOf('Stickers')), 0.15);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('hidden', () {
    testWidgets('the tab is removed and the page has no place', (tester) async {
      build();
      controller.setPageAvailability('gif', const PageAvailability.hidden());
      await pump(tester);

      expect(tabOf('GIF'), findsNothing);
      expect(tabOf('Stickers'), findsOneWidget);

      await tester.fling(find.text('page emoji'), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(controller.selectedPageId.value, 'stickers');
    });

    testWidgets('with every other page hidden, emoji alone and no tabs', (
      tester,
    ) async {
      build();
      controller
        ..setPageAvailability('gif', const PageAvailability.hidden())
        ..setPageAvailability('stickers', const PageAvailability.hidden());
      await pump(tester);

      expect(find.text('page emoji'), findsOneWidget);
      expect(tabOf('Emoji'), findsNothing);
      expect(tabOf('Stickers'), findsNothing);
    });

    testWidgets('hiding a page before the one on screen keeps it on screen '
        'with its state', (tester) async {
      build();
      controller.selectPage('stickers');
      await pump(tester);
      expect(stickers.mounts, 1);

      controller.setPageAvailability('gif', const PageAvailability.hidden());
      await tester.pumpAndSettle();

      expect(find.text('page stickers'), findsOneWidget);
      expect(stickers.mounts, 1);
      expect(stickers.disposals, 0);

      controller.setPageAvailability('gif', const PageAvailability.available());
      await tester.pumpAndSettle();
      expect(find.text('page stickers'), findsOneWidget);
      expect(stickers.mounts, 1);
    });
  });

  group('replaced', () {
    testWidgets('the tab stays and the content is the text, a plain text '
        'node', (tester) async {
      final semantics = tester.ensureSemantics();
      build();
      controller.setPageAvailability(
        'stickers',
        const PageAvailability.replaced(banText),
      );
      controller.selectPage('stickers');
      await pump(tester);

      expect(tabOf('Stickers'), findsOneWidget);
      expect(opacityOf(tester, tabOf('Stickers')), 1);
      expect(find.text(banText), findsOneWidget);
      expect(find.text('page stickers'), findsNothing);
      expect(find.bySemanticsLabel(banText), findsOneWidget);
      expectChromeText(tester, within: find.byType(PanelReplacedPage));
      // No search field and no actions for a page that is not there.
      expect(find.byType(PanelSearchField), findsNothing);
      semantics.dispose();
    });

    testWidgets('a live change while on the page rebuilds that page only', (
      tester,
    ) async {
      build();
      controller.selectPage('stickers');
      await pump(tester);
      final emojiBuilds = emoji.buildCount;
      final gifBuilds = gif.buildCount;

      controller.setPageAvailability(
        'stickers',
        const PageAvailability.replaced(banText),
      );
      await tester.pumpAndSettle();
      expect(find.text(banText), findsOneWidget);

      controller.setPageAvailability(
        'stickers',
        const PageAvailability.available(),
      );
      await tester.pumpAndSettle();
      expect(find.text('page stickers'), findsOneWidget);
      expect(emoji.buildCount, emojiBuilds);
      expect(gif.buildCount, gifBuilds);
    });
  });

  testWidgets('available builds the same tree as a shell without '
      'availability', (tester) async {
    build();
    await pump(tester);

    expect(find.byType(PanelReplacedPage), findsNothing);
    expect(find.byType(PanelTabHint), findsNothing);
    expect(opacityOf(tester, tabOf('Stickers')), 1);
    expect(find.text('page emoji'), findsOneWidget);
  });
}

double opacityOf(WidgetTester tester, Finder tab) => tester
    .widget<Opacity>(
      find.ancestor(of: tab, matching: find.byType(Opacity)).first,
    )
    .opacity;

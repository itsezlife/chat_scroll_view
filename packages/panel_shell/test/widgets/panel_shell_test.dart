import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/src/widgets/hold_repeat_button.dart';
import 'package:panel_shell/src/widgets/panel_bottom_bar.dart';
import 'package:panel_shell/src/widgets/panel_search_field.dart';
import 'package:panel_shell/src/widgets/panel_type_tabs.dart';
import 'package:panel_shell/testing.dart';

void main() {
  late FakePreferenceStore preferences;
  late FakePanelPage emoji;
  late FakePanelPage stickers;
  late PanelShellController controller;
  late FakePanelAnnouncer announcer;
  late List<PanelEvent> events;

  Future<void> pump(
    WidgetTester tester, {
    TextDirection direction = TextDirection.ltr,
    PanelFocusPolicy focusPolicy = PanelFocusPolicy.none,
    Widget Function(Widget shell)? wrap,
  }) async {
    Widget shell = PanelShell(
      controller: controller,
      announcer: announcer,
      focusPolicy: focusPolicy,
    );
    if (wrap != null) shell = wrap(shell);
    await tester.pumpWidget(
      PanelShellTestScope(textDirection: direction, child: shell),
    );
  }

  void build({List<FakePanelPage>? pages}) {
    controller = PanelShellController(
      pages: (pages ?? [emoji, stickers]).map((p) => p.page).toList(),
      preferences: preferences,
    );
    controller.events.addListener(events.add);
    addTearDown(controller.dispose);
  }

  setUp(() {
    preferences = FakePreferenceStore();
    announcer = FakePanelAnnouncer();
    events = [];
    emoji = FakePanelPage(
      'emoji',
      search: true,
      actions: const [PageAction.backspace()],
    );
    stickers = FakePanelPage(
      'stickers',
      actions: const [
        PageAction(
          id: 'settings',
          icon: ChromeIconId('settings'),
          semanticLabel: _settingsLabel,
        ),
      ],
    );
  });

  group('pages and tabs', () {
    testWidgets('shows the selected page and the tab of every page', (
      tester,
    ) async {
      build();
      await pump(tester);

      expect(find.text('page emoji'), findsOneWidget);
      expect(find.text('page stickers'), findsNothing);
      expect(find.text('Emoji'), findsOneWidget);
      expect(find.text('Stickers'), findsOneWidget);
    });

    testWidgets('shows the page remembered by the preference store', (
      tester,
    ) async {
      await preferences.setSelectedPageId('stickers');
      build();
      await pump(tester);

      expect(find.text('page stickers'), findsOneWidget);
    });

    testWidgets('tapping a tab selects the page, persists it and reports it', (
      tester,
    ) async {
      build();
      await pump(tester);

      await tester.tap(find.text('Stickers'));
      await tester.pumpAndSettle();

      expect(find.text('page stickers'), findsOneWidget);
      expect(controller.selectedPageId.value, 'stickers');
      expect(preferences.selectedPageId, 'stickers');
      expect(events, [const PageChanged('stickers')]);
    });

    testWidgets('swiping the pager selects the next page through the same '
        'intent', (tester) async {
      build();
      await pump(tester);

      await tester.fling(find.text('page emoji'), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();

      expect(controller.selectedPageId.value, 'stickers');
      expect(events, [const PageChanged('stickers')]);
      expect(find.text('page stickers'), findsOneWidget);
    });

    testWidgets('a host selecting a page moves the pager without a '
        'second PageChanged', (tester) async {
      build();
      await pump(tester);

      var reselected = 0;
      controller.hostFor('stickers').reselected.addListener(() => reselected++);

      controller.selectPage('stickers');
      await tester.pumpAndSettle();

      expect(find.text('page stickers'), findsOneWidget);
      expect(events, [const PageChanged('stickers')]);
      expect(reselected, 0, reason: 'the pager echoes its own jump');
    });

    testWidgets('selecting the selected tab again signals reselection only', (
      tester,
    ) async {
      build();
      await pump(tester);
      var reselected = 0;
      controller.hostFor('emoji').reselected.addListener(() => reselected++);

      await tester.tap(find.text('Emoji'));
      await tester.pumpAndSettle();

      expect(reselected, 1);
      expect(events, isEmpty);
    });

    testWidgets('a single page shows no type tabs', (tester) async {
      build(pages: [emoji]);
      await pump(tester);

      expect(find.text('Emoji'), findsNothing);
      expect(find.byType(PanelTypeTabs), findsNothing);
    });

    testWidgets('tabs can show icons and keep their spoken label', (
      tester,
    ) async {
      build();
      await tester.pumpWidget(
        PanelShellTestScope(
          child: PanelShell(
            controller: controller,
            announcer: announcer,
            tabDisplay: PanelTabDisplay.icon,
          ),
        ),
      );

      expect(find.text('Emoji'), findsNothing);
      expect(find.bySemanticsLabel('Emoji'), findsOneWidget);
    });
  });

  group('state outlives the widget', () {
    testWidgets('a second shell over the same controller restores page, '
        'query and page controllers', (tester) async {
      build(pages: [emoji, FakePanelPage('gif', search: true)]);
      await pump(tester);
      controller
        ..selectPage('gif')
        ..openSearch()
        ..setQuery('cat');
      final kept = controller.controllers.obtain('gif', _Kept.new);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await pump(tester);

      expect(find.text('page gif: cat'), findsOneWidget);
      expect(controller.controllers.obtain('gif', _Kept.new), same(kept));
    });

    testWidgets('swapping the controller rebinds every listener', (
      tester,
    ) async {
      build();
      final first = controller;
      await pump(tester);
      final second = PanelShellController(
        pages: [emoji.page, stickers.page],
        preferences: FakePreferenceStore(),
      );
      addTearDown(second.dispose);

      await tester.pumpWidget(
        PanelShellTestScope(
          child: PanelShell(controller: second, announcer: announcer),
        ),
      );
      first.selectPage('stickers');
      await tester.pumpAndSettle();
      expect(find.text('page emoji'), findsOneWidget);

      second.selectPage('stickers');
      await tester.pumpAndSettle();
      expect(find.text('page stickers'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('the field shows only above a page that declares search', (
      tester,
    ) async {
      build();
      await pump(tester);
      expect(find.bySemanticsLabel('Search'), findsOneWidget);

      controller.selectPage('stickers');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Search'), findsNothing);
    });

    testWidgets('tapping the field opens search with focus', (tester) async {
      build();
      await pump(tester);

      await tester.tap(find.byType(EditableText));
      await tester.pumpAndSettle();

      expect(controller.search.value.isOpen, isTrue);
      expect(events, [const SearchOpened()]);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
    });

    testWidgets('typing sets the query and the page follows it', (
      tester,
    ) async {
      build();
      await pump(tester);
      controller.openSearch();
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText), 'cat');
      await tester.pump();

      expect(controller.search.value.query, 'cat');
      expect(find.text('page emoji: cat'), findsOneWidget);
    });

    testWidgets('a host setting the query is shown in the field', (
      tester,
    ) async {
      build();
      await pump(tester);
      controller
        ..openSearch()
        ..setQuery('dog');
      await tester.pumpAndSettle();

      expect(find.text('dog'), findsOneWidget);
    });

    testWidgets('the trailing control clears the query, then closes search', (
      tester,
    ) async {
      build();
      await pump(tester);
      controller
        ..openSearch()
        ..setQuery('cat');
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.search.value.query, '');
      expect(controller.search.value.isOpen, isTrue);

      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.search.value.isOpen, isFalse);
    });

    testWidgets('dismissing the keyboard keeps search open without focus', (
      tester,
    ) async {
      build();
      await pump(tester);
      controller.openSearch();
      await tester.pumpAndSettle();

      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();

      expect(controller.search.value.isOpen, isTrue);
      expect(controller.search.value.wantsFocus, isFalse);
    });

    testWidgets('shows progress while the selected page reports a search '
        'in flight', (tester) async {
      build();
      await pump(tester);
      controller.openSearch();
      await tester.pumpAndSettle();

      emoji.host!.reportSearchProgress(busy: true);
      await tester.pump();

      expect(find.byType(CustomPaint), findsWidgets);
      expect(controller.searchBusy.value, isTrue);
    });

    group('the progress ring', () {
      double turns(WidgetTester tester) => tester
          .widget<RotationTransition>(
            find.descendant(
              of: find.byType(PanelSearchField),
              matching: find.byType(RotationTransition),
            ),
          )
          .turns
          .value;

      Future<void> startBusy(
        WidgetTester tester, {
        ChromeMotionSpeed speed = ChromeMotionSpeed.normal,
        ChromeMotion? motion,
      }) async {
        build();
        await pump(
          tester,
          wrap: (shell) =>
              ChromeMotionScope(motion: motion, speed: speed, child: shell),
        );
        controller.openSearch();
        await tester.pumpAndSettle();
        emoji.host!.reportSearchProgress(busy: true);
        await tester.pump();
      }

      testWidgets('turns once per loop period of the motion table', (
        tester,
      ) async {
        await startBusy(tester);
        await tester.pump(const Duration(milliseconds: 450));
        expect(turns(tester), closeTo(0.5, 0.02), reason: 'standard: 900 ms');
      });

      testWidgets('follows a slower loop role', (tester) async {
        await startBusy(
          tester,
          motion: const ChromeMotion.standard().copyWith(
            loop: const MotionSpec(Duration(seconds: 2), Curves.linear),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(turns(tester), closeTo(0.5, 0.02));
      });

      testWidgets('stands still, and lets the frame settle, when motion is '
          'instant', (tester) async {
        await startBusy(tester, speed: ChromeMotionSpeed.instant);

        await tester.pump(const Duration(milliseconds: 450));
        expect(turns(tester), 0);
        await tester.pumpAndSettle();
      });
    });

    testWidgets('the query survives switching between searchable pages', (
      tester,
    ) async {
      final gif = FakePanelPage('gif', search: true);
      build(pages: [emoji, gif]);
      await pump(tester);
      controller
        ..openSearch()
        ..setQuery('cat')
        ..selectPage('gif');
      await tester.pumpAndSettle();

      expect(find.text('page gif: cat'), findsOneWidget);
      expect(find.text('cat'), findsOneWidget, reason: 'the field keeps it');
    });
  });

  group('input', () {
    testWidgets('Escape closes search first and then bubbles to the '
        'enclosing popup', (tester) async {
      build();
      var dismissed = 0;
      await pump(
        tester,
        // A popup owns its Escape binding; the shell's own is skipped while
        // search is closed, so the key bubbles up to this one.
        wrap: (shell) => Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  dismissed++;
                  return null;
                },
              ),
            },
            child: shell,
          ),
        ),
      );
      controller.openSearch();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.search.value.isOpen, isFalse);
      expect(dismissed, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(dismissed, 1);
    });

    testWidgets('the search shortcut opens and focuses the field', (
      tester,
    ) async {
      build();
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      expect(
        controller.search.value,
        const PanelSearchState(isOpen: true, wantsFocus: true),
      );
    });

    testWidgets('the shortcut map can be replaced by the host', (tester) async {
      build();
      await tester.pumpWidget(
        PanelShellTestScope(
          child: PanelShell(
            controller: controller,
            announcer: announcer,
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyS): PanelSearchIntent(),
            },
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();

      expect(controller.search.value.isOpen, isTrue);
    });

    testWidgets('Enter on a focused tab selects it', (tester) async {
      build();
      await pump(tester);

      // Tab order is page, bottom bar, search: the first tab is the first
      // control of the bar.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controller.selectedPageId.value, 'stickers');
    });
  });

  group('bottom bar', () {
    double barTop(WidgetTester tester) =>
        tester.getTopLeft(find.byType(PanelBottomBar)).dy;

    testWidgets('slides away after page scroll activity and back on a jump', (
      tester,
    ) async {
      build();
      await pump(tester);
      final shown = barTop(tester);

      emoji.host!.reportScrollActivity(const PageScrollDrag(50));
      await tester.pumpAndSettle();
      expect(barTop(tester), greaterThan(shown + 40));

      emoji.host!.reportScrollActivity(const PageScrollJump());
      await tester.pumpAndSettle();
      expect(barTop(tester), shown);
    });

    testWidgets('slides away when search opens and returns when it closes', (
      tester,
    ) async {
      build();
      await pump(tester);
      final shown = barTop(tester);

      controller.openSearch();
      await tester.pumpAndSettle();
      expect(barTop(tester), greaterThan(shown + 40));

      controller.closeSearch();
      await tester.pumpAndSettle();
      expect(barTop(tester), shown);
    });

    testWidgets('scroll activity of a page that is not selected is ignored', (
      tester,
    ) async {
      build();
      await pump(tester);
      final shown = barTop(tester);
      controller.selectPage('stickers');
      await tester.pumpAndSettle();

      emoji.host!.reportScrollActivity(const PageScrollDrag(50));
      await tester.pumpAndSettle();

      expect(barTop(tester), shown);
    });

    testWidgets('changing page shows a hidden bar', (tester) async {
      build();
      await pump(tester);
      final shown = barTop(tester);
      emoji.host!.reportScrollActivity(const PageScrollDrag(50));
      await tester.pumpAndSettle();

      controller.selectPage('stickers');
      await tester.pumpAndSettle();

      expect(barTop(tester), shown);
    });

    testWidgets('pages are told to leave room under the floating bar', (
      tester,
    ) async {
      build();
      await tester.pumpWidget(
        PanelShellTestScope(
          child: PanelShell(controller: controller, announcer: announcer),
        ),
      );
      final inner = tester.element(find.text('page emoji'));

      expect(MediaQuery.paddingOf(inner).bottom, PanelBottomBar.height);
    });
  });

  group('actions and events', () {
    testWidgets('tapping backspace publishes BackspaceRequested', (
      tester,
    ) async {
      build();
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Delete'));
      await tester.pump();

      expect(events, [const BackspaceRequested()]);
    });

    testWidgets('holding backspace repeats, accelerating, and stops on '
        'release', (tester) async {
      build();
      await pump(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Delete')),
      );
      await tester.pump(HoldRepeatButton.initialRepeatDelay);
      expect(events.length, 1);
      await tester.pump(const Duration(milliseconds: 250));
      expect(events.length, 2);
      await tester.pump(const Duration(milliseconds: 150));
      expect(events.length, 3);

      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(
        events.length,
        3,
        reason: 'release neither adds a tap nor repeats',
      );
    });

    testWidgets('a cancelled press triggers nothing', (tester) async {
      build();
      await pump(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Delete')),
      );
      await gesture.cancel();
      await tester.pump(const Duration(seconds: 1));

      expect(events, isEmpty);
    });

    testWidgets('another action publishes ActionInvoked with page and id', (
      tester,
    ) async {
      build();
      await pump(tester);
      controller.selectPage('stickers');
      await tester.pumpAndSettle();
      events.clear();

      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pump();

      expect(events, [
        const ActionInvoked(pageId: 'stickers', actionId: 'settings'),
      ]);
    });

    testWidgets('the search action opens search instead of publishing', (
      tester,
    ) async {
      final searchable = FakePanelPage(
        'emoji',
        search: true,
        actions: const [PageAction.search()],
      );
      build(pages: [searchable]);
      await pump(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(PanelBottomBar),
          matching: find.byType(ScalePressable),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.search.value.isOpen, isTrue);
      expect(events, [const SearchOpened()]);
    });

    testWidgets('the action row shows the actions of the selected page only', (
      tester,
    ) async {
      build();
      await pump(tester);
      expect(find.bySemanticsLabel('Delete'), findsOneWidget);
      expect(find.bySemanticsLabel('Settings'), findsNothing);

      controller.selectPage('stickers');
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Delete'), findsNothing);
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    });

    testWidgets('picks and clear requests from a page reach the single '
        'handler', (tester) async {
      build();
      await pump(tester);
      const thumbs = ContentKey.unicode('1F44D');

      emoji.host!
        ..pick(
          thumbs,
          kind: SemanticKind.unicodeEmoji,
          source: PickSource.search,
        )
        ..requestClearRecents(SemanticKind.unicodeEmoji);

      expect(events, [
        const ContentPicked(
          key: thumbs,
          kind: SemanticKind.unicodeEmoji,
          source: PickSource.search,
        ),
        const ClearRecentsRequested(kind: SemanticKind.unicodeEmoji),
      ]);
    });
  });

  group('announcements', () {
    testWidgets('announces the page after a selection', (tester) async {
      build();
      await pump(tester);

      controller.selectPage('stickers');

      expect(announcer.messages, ['Stickers selected']);
    });

    testWidgets('announces the result count a page reports', (tester) async {
      build();
      await pump(tester);

      emoji.host!.reportSearchResultCount(3);
      emoji.host!.reportSearchResultCount(0);

      expect(announcer.messages, ['3 results', 'No results']);
    });

    testWidgets('announces opening and closing from the visible state', (
      tester,
    ) async {
      build();
      await pump(tester);

      controller.updatePresence(visible: true, opening: true);
      controller.updatePresence(visible: true, opening: false);
      controller.updatePresence(visible: false, opening: false);

      expect(announcer.messages, ['Panel opened', 'Panel closed']);
    });
  });

  group('focus policy', () {
    testWidgets('moves focus into the shell on open and back on close', (
      tester,
    ) async {
      build();
      final composer = FocusNode(debugLabel: 'composer');
      addTearDown(composer.dispose);
      await tester.pumpWidget(
        PanelShellTestScope(
          child: Column(
            children: [
              Focus(focusNode: composer, child: const SizedBox(height: 10)),
              Expanded(
                child: PanelShell(
                  controller: controller,
                  announcer: announcer,
                  focusPolicy: PanelFocusPolicy(
                    focusOnOpen: true,
                    restoreTarget: composer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      composer.requestFocus();
      await tester.pump();

      controller.updatePresence(visible: true, opening: false);
      await tester.pump();
      expect(composer.hasFocus, isFalse);
      expect(FocusManager.instance.primaryFocus, isNotNull);

      controller.updatePresence(visible: false, opening: false);
      await tester.pump();
      expect(composer.hasFocus, isTrue);
    });

    testWidgets('the default policy never moves focus', (tester) async {
      build();
      final composer = FocusNode(debugLabel: 'composer');
      addTearDown(composer.dispose);
      await tester.pumpWidget(
        PanelShellTestScope(
          child: Column(
            children: [
              Focus(focusNode: composer, child: const SizedBox(height: 10)),
              Expanded(
                child: PanelShell(controller: controller, announcer: announcer),
              ),
            ],
          ),
        ),
      );
      composer.requestFocus();
      await tester.pump();

      controller.updatePresence(visible: true, opening: false);
      await tester.pump();

      expect(composer.hasFocus, isTrue);
    });
  });

  group('right to left', () {
    testWidgets('orders tabs from the right and the action at the left', (
      tester,
    ) async {
      build();
      await pump(tester, direction: TextDirection.rtl);

      final emojiX = tester.getCenter(find.text('Emoji')).dx;
      final stickersX = tester.getCenter(find.text('Stickers')).dx;
      expect(emojiX, greaterThan(stickersX));

      final delete = tester.getCenter(find.bySemanticsLabel('Delete')).dx;
      expect(delete, lessThan(200), reason: 'the end side is the left');
    });

    testWidgets('swiping toward the start side selects the next page', (
      tester,
    ) async {
      build();
      await pump(tester, direction: TextDirection.rtl);

      await tester.fling(find.text('page emoji'), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();

      expect(controller.selectedPageId.value, 'stickers');
    });

    testWidgets('the capsule follows the selected tab', (tester) async {
      build();
      await pump(tester, direction: TextDirection.rtl);
      await tester.pumpAndSettle();

      controller.selectPage('stickers');
      await tester.pumpAndSettle();

      final capsule = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color ==
                const ChromePalette.light().surfaceSelected,
      );
      final stickersX = tester.getCenter(find.text('Stickers')).dx;
      expect(
        (tester.getCenter(capsule.first).dx - stickersX).abs(),
        lessThan(2),
      );
    });
  });

  group('paced mount', () {
    testWidgets('mounts everything with the first frame by default', (
      tester,
    ) async {
      build();
      await pump(tester);

      expect(find.byType(PanelSearchField), findsOneWidget);
    });

    testWidgets('a deferred search field joins one frame after the page', (
      tester,
    ) async {
      build();
      await tester.pumpWidget(
        PanelShellTestScope(
          child: PanelShell(
            controller: controller,
            announcer: announcer,
            deferSearchField: true,
          ),
        ),
      );

      expect(find.text('page emoji'), findsOneWidget);
      expect(find.byType(PanelSearchField), findsNothing);

      await tester.pump();

      expect(find.byType(PanelSearchField), findsOneWidget);
    });

    testWidgets('a deferred field is there at once for a page selected later', (
      tester,
    ) async {
      build();
      await tester.pumpWidget(
        PanelShellTestScope(
          child: PanelShell(
            controller: controller,
            announcer: announcer,
            deferSearchField: true,
          ),
        ),
      );
      await tester.pump();
      controller.selectPage('stickers');
      await tester.pumpAndSettle();

      controller.selectPage('emoji');
      await tester.pump();

      expect(find.byType(PanelSearchField), findsOneWidget);
    });
  });

  group('motion and text scale', () {
    testWidgets('under instant motion the bar hides within one frame', (
      tester,
    ) async {
      build();
      await tester.pumpWidget(
        PanelShellTestScope(
          speed: ChromeMotionSpeed.instant,
          child: PanelShell(controller: controller, announcer: announcer),
        ),
      );
      final shown = tester.getTopLeft(find.byType(PanelBottomBar)).dy;

      emoji.host!.reportScrollActivity(const PageScrollDrag(50));
      await tester.pump();
      await tester.pump();

      expect(
        tester.getTopLeft(find.byType(PanelBottomBar)).dy,
        greaterThan(shown + 40),
      );
    });

    testWidgets('under instant motion the search field comes and goes with '
        'the page without a layout error', (tester) async {
      build();
      await tester.pumpWidget(
        PanelShellTestScope(
          speed: ChromeMotionSpeed.instant,
          child: PanelShell(controller: controller, announcer: announcer),
        ),
      );
      expect(find.byType(PanelSearchField), findsOneWidget);

      controller.selectPage('stickers');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(PanelSearchField), findsNothing);

      controller.selectPage('emoji');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(PanelSearchField), findsOneWidget);
    });

    testWidgets('large text does not overflow the fixed-height controls', (
      tester,
    ) async {
      build();
      await tester.pumpWidget(
        PanelShellTestScope(
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 600),
              textScaler: TextScaler.linear(2),
            ),
            child: PanelShell(controller: controller, announcer: announcer),
          ),
        ),
      );
      controller.openSearch();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(PanelSearchField)).height,
        PanelSearchField.height,
      );
    });
  });

  group('semantics', () {
    testWidgets('tabs, actions and the search field are labelled', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      build();
      await pump(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Emoji')),
        matchesSemantics(
          label: 'Emoji',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          hasEnabledState: false,
        ),
      );
      expect(find.bySemanticsLabel('Stickers'), findsOneWidget);
      expect(find.bySemanticsLabel('Delete'), findsOneWidget);
      expect(find.bySemanticsLabel('Search'), findsOneWidget);
      handle.dispose();
    });
  });
}

String _settingsLabel(ChromeStrings strings) => 'Settings';

class _Kept implements PanelPageController {
  @override
  void dispose() {}
}

import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'emoji_page_test.dart' show createTestEmojiDataSource;

/// Drives [AnimationController] ticks until [future] completes.
///
/// [KeyboardPanelController.openSearch] / [closeSearch] await expand/collapse
/// motion that only advances when the tester pumps frames.
Future<void> pumpAsync(WidgetTester tester, Future<void> future) async {
  var completed = false;
  final tracked = future.whenComplete(() => completed = true);
  await tester.pump();
  for (var i = 0; i < 120 && !completed; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tracked;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KeyboardPanelStore store;
  late DefaultEmojiDataSource dataSource;
  late ChatBottomInsetController inset;
  late KeyboardPanelController panel;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = KeyboardPanelStore(defaultHeight: 200);
    await store.load();
    dataSource = await createTestEmojiDataSource();
    inset = ChatBottomInsetController(store: store);
    panel = KeyboardPanelController(inset: inset, store: store);
  });

  tearDown(() {
    dataSource.dispose();
    panel.dispose();
    inset.dispose();
  });

  /// Bottom-bar center Y — rises when visible, drops when hide-slide is applied.
  double bottomBarCenterY(WidgetTester tester) =>
      tester.getCenter(find.byType(KeyboardPanelBottomBar)).dy;

  Widget harness() => MaterialApp(
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(
          viewPadding: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          viewInsets: EdgeInsets.zero,
        ),
        child: child!,
      );
    },
    home: Scaffold(
      body: Column(
        children: <Widget>[
          const Expanded(child: SizedBox.expand()),
          ValueListenableBuilder<double>(
            valueListenable: inset.heightListenable,
            // Cold close may publish a brief negative overshoot (safe-bottom).
            builder: (context, height, child) =>
                SizedBox(height: height < 0 ? 0 : height, child: child),
            child: KeyboardPanel(
              controller: panel,
              dataSource: dataSource,
              allow: KeyboardPanelAllow.emojiOnly,
              onEmojiSelected: (_) {},
              onBackspace: () {},
            ),
          ),
        ],
      ),
    ),
  );

  testWidgets('cold open grows slot and shows keyboard panel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              Expanded(
                child: TextButton(
                  onPressed: () => panel.open(landscape: false),
                  child: const Text('open'),
                ),
              ),
              ValueListenableBuilder<double>(
                valueListenable: inset.heightListenable,
                builder: (context, height, child) =>
                    SizedBox(height: height, child: child),
                child: KeyboardPanel(
                  controller: panel,
                  dataSource: dataSource,
                  allow: KeyboardPanelAllow.emojiOnly,
                  onEmojiSelected: (_) {},
                  onBackspace: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(inset.height, 0);
    await tester.tap(find.text('open'));
    await tester.pump(); // start
    await tester.pump(const Duration(milliseconds: 50)); // startDelay
    await tester.pump(const Duration(milliseconds: 100));
    expect(inset.height, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(inset.height, closeTo(200, 1));
    expect(find.byType(KeyboardPanel), findsOneWidget);
    expect(panel.isOpen, isTrue);
    expect(inset.isPanelOpen, isTrue);
  });

  testWidgets('replace keeps height and shows panel immediately', (
    tester,
  ) async {
    inset.onImeHeight(320, landscape: false);
    await tester.pumpWidget(harness());

    panel.open(landscape: false);
    await tester.pumpAndSettle();

    expect(inset.height, 320);
    expect(find.byType(EmojiPage), findsOneWidget);
  });

  testWidgets('opening panel keeps search closed', (tester) async {
    await tester.pumpWidget(harness());
    inset.onImeHeight(320, landscape: false);
    panel.open(landscape: false);
    await tester.pumpAndSettle();

    expect(find.byType(EmojiSearchField), findsOneWidget);
    expect(panel.isSearchOpen, isFalse);
    expect(find.byType(EmojiPage), findsOneWidget);
  });

  testWidgets('cold close animates slot height before releasing panel', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    panel.open(landscape: false);
    await tester.pump();
    await tester.pump(KeyboardPanelMotion.startDelay);
    await tester.pump(KeyboardPanelMotion.duration);
    await tester.pump();
    expect(inset.height, closeTo(200, 1));

    // Do not await projection before pumping — [animateTo] needs frames.
    panel.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(inset.height, lessThan(200));
    expect(inset.height, greaterThanOrEqualTo(0));
    expect(find.byType(EmojiPage), findsOneWidget);

    await tester.pump(KeyboardPanelMotion.duration);
    await tester.pump();
    expect(inset.height, 0);
    expect(inset.isPanelOpen, isFalse);
    expect(panel.isOpen, isFalse);
  });

  testWidgets('keyboard handoff hides content but keeps panel shell', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    inset.onImeHeight(320, landscape: false);
    panel.open(landscape: false);
    await tester.pumpAndSettle();
    expect(find.byType(EmojiPage), findsOneWidget);

    panel.close(waitForIme: true);
    await tester.pumpAndSettle();
    expect(find.byType(EmojiPage), findsNothing);
    expect(find.byType(KeyboardPanel), findsOneWidget);
    expect(inset.height, closeTo(320, 1));

    inset.onImeHeight(320, landscape: false);
    await tester.pump();
    inset.onImeHeight(320, landscape: false);
    await tester.pumpAndSettle();
    expect(inset.isHoldingForIme, isFalse);
    expect(find.byType(EmojiPage), findsNothing);
    expect(panel.isOpen, isFalse);
  });

  testWidgets(
    'search open then waitForIme handoff holds at base not expanded height',
    (tester) async {
      await tester.pumpWidget(harness());
      inset.onImeHeight(320, landscape: false);
      panel.open(landscape: false);
      await tester.pumpAndSettle();
      final base = inset.panelTarget;

      final opening = panel.openSearch();
      await pumpAsync(tester, opening);
      expect(panel.isSearchOpen, isTrue);
      expect(inset.isSearchExpanded, isTrue);
      expect(inset.height, greaterThan(base));

      // Pre-refactor host ordering: await animated search collapse, then
      // waitForIme close so the hold captures the keyboard-sized base.
      final closing = panel.closeSearch(hideKeyboard: false);
      await pumpAsync(tester, closing);

      expect(panel.isSearchOpen, isFalse);
      expect(inset.isSearchExpanded, isFalse);
      expect(inset.height, closeTo(base, 1));

      panel.close(waitForIme: true);
      await tester.pump();

      expect(panel.isOpen, isFalse);
      expect(inset.height, closeTo(base, 1));
      expect(inset.isHoldingForIme, isTrue);
    },
  );

  testWidgets('reopen after handoff restores emoji content', (tester) async {
    await tester.pumpWidget(harness());
    inset.onImeHeight(320, landscape: false);
    panel.open(landscape: false);
    await tester.pumpAndSettle();
    expect(find.byType(EmojiPage), findsOneWidget);

    panel.close(waitForIme: true);
    await tester.pumpAndSettle();
    expect(find.byType(EmojiPage), findsNothing);
    expect(find.byType(KeyboardPanel), findsOneWidget);

    // Host toggles emoji again before handoff shell dismisses (stuck shell).
    panel.open(landscape: false);
    await tester.pumpAndSettle();

    expect(find.byType(EmojiPage), findsOneWidget);
    expect(panel.isOpen, isTrue);
  });

  testWidgets('close during handoff shell dismisses stuck panel', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    inset.onImeHeight(320, landscape: false);
    panel.open(landscape: false);
    await tester.pumpAndSettle();

    panel.close(waitForIme: true);
    await tester.pumpAndSettle();
    expect(find.byType(KeyboardPanel), findsOneWidget);

    // SoT already closed; waitForIme still projects so the stuck shell finishes.
    panel.close(waitForIme: true);
    await tester.pumpAndSettle();

    expect(panel.isOpen, isFalse);
    expect(find.byType(EmojiPage), findsNothing);
  });

  testWidgets('unmount does not dispose host panel controller', (tester) async {
    await tester.pumpWidget(harness());
    inset.onImeHeight(320, landscape: false);
    panel.open(landscape: false);
    await tester.pumpAndSettle();
    expect(panel.isOpen, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(panel.isDisposed, isFalse);
    expect(panel.isOpen, isTrue);
    panel.close();
    expect(panel.isOpen, isFalse);
  });

  testWidgets('remount projects already-open controller state', (tester) async {
    await tester.pumpWidget(harness());
    inset.onImeHeight(320, landscape: false);
    panel.open(landscape: false);
    await tester.pumpAndSettle();
    expect(find.byType(EmojiPage), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(panel.isOpen, isTrue);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.byType(EmojiPage), findsOneWidget);
    expect(panel.isOpen, isTrue);
  });

  Future<void> openReplace(WidgetTester tester) async {
    await tester.pumpWidget(harness());
    inset.onImeHeight(320, landscape: false);
    panel.open(landscape: false);
    await tester.pumpAndSettle();
  }

  testWidgets('scroll down hides bottom bar; scroll up shows it', (
    tester,
  ) async {
    await openReplace(tester);
    final visibleY = bottomBarCenterY(tester);

    await tester.drag(find.byType(EmojiPage), const Offset(0, -120));
    await tester.pump();
    await tester.pump(KeyboardPanelBottomBar.visibilityDuration);
    expect(bottomBarCenterY(tester), greaterThan(visibleY));

    await tester.drag(find.byType(EmojiPage), const Offset(0, 120));
    await tester.pump();
    await tester.pump(KeyboardPanelBottomBar.visibilityDuration);
    expect(bottomBarCenterY(tester), closeTo(visibleY, 1));
  });

  testWidgets('sticky search field is present when panel is open', (
    tester,
  ) async {
    await openReplace(tester);
    expect(find.byType(EmojiSearchField), findsOneWidget);
    expect(panel.isSearchOpen, isFalse);
  });

  testWidgets('browse at rest reserves strip and search spacer in catalog', (
    tester,
  ) async {
    await openReplace(tester);
    await tester.pump(const Duration(milliseconds: 250));

    final page = tester.state<EmojiPageState>(find.byType(EmojiPage));
    expect(page.catalogScrollOffset, 0);
    expect(
      page.catalogPaddingTop,
      closeTo(EmojiPage.gridPadTop + EmojiSearchField.height, 0.1),
    );
    expect(find.byType(EmojiPage), findsOneWidget);
  });

  testWidgets('search open hides bottom bar and expands panel target', (
    tester,
  ) async {
    await openReplace(tester);
    final visibleY = bottomBarCenterY(tester);
    final base = inset.panelTarget;

    final opening = panel.openSearch();
    await pumpAsync(tester, opening);
    await tester.pump(KeyboardPanelBottomBar.visibilityDuration);

    expect(bottomBarCenterY(tester), greaterThan(visibleY));
    expect(panel.isSearchOpen, isTrue);
    expect(find.byType(EmojiSearchField), findsOneWidget);
    expect(inset.panelTarget, lessThanOrEqualTo(base + 175));
    expect(inset.panelTarget, greaterThanOrEqualTo(base));
    expect(inset.isSearchExpanded, isTrue);
  });

  testWidgets('handleBack closes search before panel', (tester) async {
    await openReplace(tester);
    final opening = panel.openSearch();
    await pumpAsync(tester, opening);
    expect(panel.isSearchOpen, isTrue);

    inset.onImeHeight(0, landscape: false);
    await tester.pump();

    expect(panel.handleBack(), isTrue);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (!inset.isSearchExpanded && !panel.isSearchOpen) break;
    }
    expect(panel.isSearchOpen, isFalse);
    expect(panel.isOpen, isTrue);
    expect(inset.isSearchExpanded, isFalse);
  });

  Widget allTabsHarness() => MaterialApp(
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(
          viewPadding: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          viewInsets: EdgeInsets.zero,
        ),
        child: child!,
      );
    },
    home: Scaffold(
      body: Column(
        children: <Widget>[
          const Expanded(child: SizedBox.expand()),
          ValueListenableBuilder<double>(
            valueListenable: inset.heightListenable,
            builder: (context, height, child) =>
                SizedBox(height: height < 0 ? 0 : height, child: child),
            child: KeyboardPanel(
              controller: panel,
              dataSource: dataSource,
              allow: KeyboardPanelAllow.all,
              onEmojiSelected: (_) {},
              onBackspace: () {},
              callbacks: KeyboardPanelCallbacks(onStickerSettings: () {}),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> openAllTabs(WidgetTester tester) async {
    await tester.pumpWidget(allTabsHarness());
    inset.onImeHeight(320, landscape: false);
    panel.open(landscape: false);
    await tester.pump();
  }

  testWidgets('reselect emoji tab animates to first category', (tester) async {
    await openAllTabs(tester);
    await tester.pumpAndSettle();
    final page = tester.state<EmojiPageState>(find.byType(EmojiPage));

    // Scroll deep enough that a fixed-duration animateTo would look like a
    // jump; reselect must use jumpToSection (near/far) to section 0.
    await tester.drag(find.byType(EmojiPage), const Offset(0, -2400));
    await tester.pump();
    final before = page.catalogScrollOffset;
    expect(before, greaterThan(EmojiSearchField.height + 100));

    // Same-value selectTab is silent — tap the already-selected type tab so
    // the bottom bar reselect path scrolls to the first category.
    await tester.tap(find.text(KeyboardPanelLabels.english.emoji));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(page.categoryIndex, 0);
    expect(page.catalogScrollOffset, closeTo(EmojiSearchField.height, 1));
  });

  testWidgets('category jump keeps bottom bar visible during animation', (
    tester,
  ) async {
    await openReplace(tester);
    final visibleY = bottomBarCenterY(tester);

    final animalsIndex = dataSource.categories.indexWhere(
      (c) => c.id == 'animals',
    );
    expect(animalsIndex, greaterThan(0));

    final strip = find.byType(EmojiCategoryStrip);
    expect(strip, findsOneWidget);
    final stripRect = tester.getRect(strip);
    final tabCenter = Offset(
      stripRect.left +
          EmojiCategoryStrip.padH +
          animalsIndex * (EmojiCategoryStrip.cell + EmojiCategoryStrip.gap) +
          EmojiCategoryStrip.cell / 2,
      stripRect.center.dy,
    );
    await tester.tapAt(tabCenter);
    await tester.pump();
    expect(bottomBarCenterY(tester), closeTo(visibleY, 1));

    await tester.pump(const Duration(milliseconds: 100));
    expect(bottomBarCenterY(tester), closeTo(visibleY, 1));

    await tester.pumpAndSettle();
    expect(bottomBarCenterY(tester), closeTo(visibleY, 1));
  });

  testWidgets('selectTab projects pager from controller', (tester) async {
    await openAllTabs(tester);
    expect(panel.selectedTab, KeyboardPanelTab.emoji);

    panel.selectTab(KeyboardPanelTab.stickers);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(panel.selectedTab, KeyboardPanelTab.stickers);
    expect(find.byType(StickerPageStub), findsOneWidget);
    expect(store.selectedPage, KeyboardPanelTab.stickers.prefsPage);
  });

  testWidgets('trailing action swaps by panel type tab', (tester) async {
    await openAllTabs(tester);
    expect(panel.selectedTab, KeyboardPanelTab.emoji);
    expect(find.bySemanticsLabel('Settings'), findsNothing);

    await tester.tap(find.text('GIF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(panel.selectedTab, KeyboardPanelTab.gifs);
    expect(find.bySemanticsLabel('Settings'), findsNothing);

    await tester.tap(find.text('Stickers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(panel.selectedTab, KeyboardPanelTab.stickers);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);

    await tester.tap(find.text('Emoji'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(panel.selectedTab, KeyboardPanelTab.emoji);
    expect(find.bySemanticsLabel('Settings'), findsNothing);
  });

  testWidgets('persisted tab opens and selection is saved on switch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      KeyboardPanelStore.selectedPageKey: KeyboardPanelTab.stickers.prefsPage,
    });
    final localStore = KeyboardPanelStore(defaultHeight: 200);
    await localStore.load();
    final localInset = ChatBottomInsetController(store: localStore);
    final localPanel = KeyboardPanelController(
      inset: localInset,
      store: localStore,
    );
    addTearDown(() {
      localPanel.dispose();
      localInset.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const Expanded(child: SizedBox.expand()),
              SizedBox(
                height: 320,
                child: KeyboardPanel(
                  controller: localPanel,
                  dataSource: dataSource,
                  allow: KeyboardPanelAllow.all,
                  onEmojiSelected: (_) {},
                  onBackspace: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    localPanel.open(landscape: false);
    await tester.pumpAndSettle();

    expect(localPanel.selectedTab, KeyboardPanelTab.stickers);
    expect(find.byType(StickerPageStub), findsOneWidget);

    localPanel.selectTab(KeyboardPanelTab.emoji);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(localPanel.selectedTab, KeyboardPanelTab.emoji);
    expect(localStore.selectedPage, KeyboardPanelTab.emoji.prefsPage);
    expect(find.byType(EmojiPage), findsOneWidget);
    expect(find.byType(StickerPageStub), findsNothing);
  });
}

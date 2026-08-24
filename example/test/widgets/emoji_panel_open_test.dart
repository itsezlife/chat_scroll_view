import 'dart:async';

import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'emoji_page_test.dart' show createTestEmojiDataSource;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KeyboardHeightStore store;
  late DefaultEmojiDataSource dataSource;
  late ChatBottomInsetController controller;
  late GlobalKey<EmojiPanelState> panelKey;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = KeyboardHeightStore(defaultHeight: 200);
    await store.load();
    dataSource = await createTestEmojiDataSource();
    controller = ChatBottomInsetController(store: store);
    panelKey = GlobalKey<EmojiPanelState>();
  });

  tearDown(() {
    dataSource.dispose();
    controller.dispose();
  });

  Widget harness({required bool open}) => MaterialApp(
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
            valueListenable: controller.heightListenable,
            // Cold close may publish a brief negative overshoot (safe-bottom).
            builder: (context, height, child) =>
                SizedBox(height: height < 0 ? 0 : height, child: child),
            child: EmojiPanel(
              key: panelKey,
              open: open,
              controller: controller,
              store: store,
              dataSource: dataSource,
              allow: EmojiPanelAllow.emojiOnly,
              onEmojiSelected: (_) {},
              onBackspace: () {},
            ),
          ),
        ],
      ),
    ),
  );

  testWidgets('cold open grows slot and shows emoji panel', (tester) async {
    var open = false;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      controller.openPanel(landscape: false);
                      setState(() => open = true);
                      await panelKey.currentState?.open(
                        replacingKeyboard: false,
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: controller.heightListenable,
                  builder: (context, height, child) =>
                      SizedBox(height: height, child: child),
                  child: EmojiPanel(
                    key: panelKey,
                    open: open,
                    controller: controller,
                    store: store,
                    dataSource: dataSource,
                    allow: EmojiPanelAllow.emojiOnly,
                    onEmojiSelected: (_) {},
                    onBackspace: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(controller.height, 0);
    await tester.tap(find.text('open'));
    await tester.pump(); // start
    await tester.pump(const Duration(milliseconds: 50)); // startDelay
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.height, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(controller.height, closeTo(200, 1));
    expect(find.byType(EmojiPanel), findsOneWidget);
    expect(controller.isPanelOpen, isTrue);
  });

  testWidgets('replace keeps height and shows panel immediately', (
    tester,
  ) async {
    controller.onImeHeight(320, landscape: false);
    await tester.pumpWidget(harness(open: false));

    controller.openPanel(landscape: false);
    expect(controller.height, 320);

    await tester.pumpWidget(harness(open: true));
    await panelKey.currentState!.open(replacingKeyboard: true);
    await tester.pump();

    expect(controller.height, 320);
    expect(find.byType(EmojiPage), findsOneWidget);
  });

  testWidgets('opening panel keeps search closed', (tester) async {
    await tester.pumpWidget(harness(open: false));
    controller.onImeHeight(320, landscape: false);
    controller.openPanel(landscape: false);
    await tester.pumpWidget(harness(open: true));
    // Snap open — we only assert search chrome, not cold animation.
    await panelKey.currentState!.open(replacingKeyboard: true);
    await tester.pump();

    expect(find.byType(EmojiSearchField), findsOneWidget);
    expect(panelKey.currentState!.isSearchOpen, isFalse);
    expect(find.byType(EmojiPage), findsOneWidget);
  });

  testWidgets('cold close animates slot height before releasing panel', (
    tester,
  ) async {
    await tester.pumpWidget(harness(open: false));
    controller.openPanel(landscape: false);
    await panelKey.currentState!.open(replacingKeyboard: true);
    await tester.pump();
    expect(controller.height, closeTo(200, 1));

    // Do not await [close] before pumping — [animateTo] needs frames.
    final closeFuture = panelKey.currentState!.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.height, lessThan(200));
    expect(controller.height, greaterThanOrEqualTo(0));
    expect(find.byType(EmojiPage), findsOneWidget);

    await tester.pump(KeyboardPanelMotion.duration);
    await tester.pump();
    await closeFuture;
    expect(controller.height, 0);
    expect(controller.isPanelOpen, isFalse);
  });

  testWidgets('keyboard handoff hides content but keeps panel shell', (
    tester,
  ) async {
    await tester.pumpWidget(harness(open: false));
    controller.onImeHeight(320, landscape: false);
    controller.openPanel(landscape: false);
    await panelKey.currentState!.open(replacingKeyboard: true);
    await tester.pump();
    expect(find.byType(EmojiPage), findsOneWidget);

    await panelKey.currentState!.close(waitForIme: true);
    await tester.pump();
    expect(find.byType(EmojiPage), findsNothing);
    expect(find.byType(EmojiPanel), findsOneWidget);
    expect(controller.height, closeTo(320, 1));

    controller.onImeHeight(320, landscape: false);
    await tester.pump();
    controller.onImeHeight(320, landscape: false);
    await tester.pump();
    expect(controller.isHoldingForIme, isFalse);
    expect(find.byType(EmojiPage), findsNothing);
    expect(panelKey.currentState!.isOpen, isFalse);
  });

  testWidgets('reopen after handoff restores emoji content', (tester) async {
    await tester.pumpWidget(harness(open: false));
    controller.onImeHeight(320, landscape: false);
    controller.openPanel(landscape: false);
    await panelKey.currentState!.open(replacingKeyboard: true);
    await tester.pump();
    expect(find.byType(EmojiPage), findsOneWidget);

    await panelKey.currentState!.close(waitForIme: true);
    await tester.pump();
    expect(find.byType(EmojiPage), findsNothing);
    expect(find.byType(EmojiPanel), findsOneWidget);

    // Host toggles emoji again before handoff shell dismisses (stuck shell).
    controller.openPanel(landscape: false);
    await tester.pumpWidget(harness(open: true));
    await panelKey.currentState!.open(replacingKeyboard: true);
    await tester.pump();

    expect(find.byType(EmojiPage), findsOneWidget);
    expect(panelKey.currentState!.isOpen, isTrue);
  });

  testWidgets('close during handoff shell dismisses stuck panel', (
    tester,
  ) async {
    await tester.pumpWidget(harness(open: false));
    controller.onImeHeight(320, landscape: false);
    controller.openPanel(landscape: false);
    await panelKey.currentState!.open(replacingKeyboard: true);
    await tester.pump();

    await panelKey.currentState!.close(waitForIme: true);
    await tester.pump();
    expect(find.byType(EmojiPanel), findsOneWidget);

    await panelKey.currentState!.close(waitForIme: true);
    await tester.pump();

    expect(panelKey.currentState!.isOpen, isFalse);
    expect(find.byType(EmojiPage), findsNothing);
  });

  Future<void> openReplace(WidgetTester tester) async {
    await tester.pumpWidget(harness(open: false));
    controller.onImeHeight(320, landscape: false);
    controller.openPanel(landscape: false);
    await tester.pumpWidget(harness(open: true));
    await panelKey.currentState!.open(replacingKeyboard: true);
    await tester.pumpAndSettle();
  }

  /// Drives async panel work that awaits [AnimationController.forward] — needs
  /// explicit frame pumps in widget tests (search expand, strip reveal, …).
  Future<void> pumpAsync(
    WidgetTester tester,
    Future<void> future, {
    int frames = 40,
  }) async {
    await tester.pump();
    var done = false;
    unawaited(future.whenComplete(() => done = true));
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (done) break;
    }
    await future;
  }

  testWidgets('scroll down hides bottom bar; scroll up shows it', (
    tester,
  ) async {
    await openReplace(tester);
    expect(panelKey.currentState!.bottomBarVisible, isTrue);

    await tester.drag(find.byType(EmojiPage), const Offset(0, -120));
    await tester.pump();
    expect(panelKey.currentState!.bottomBarVisible, isFalse);

    await tester.drag(find.byType(EmojiPage), const Offset(0, 120));
    await tester.pump();
    expect(panelKey.currentState!.bottomBarVisible, isTrue);
  });

  testWidgets('sticky search field is present when panel is open', (
    tester,
  ) async {
    await openReplace(tester);
    expect(find.byType(EmojiSearchField), findsOneWidget);
    expect(panelKey.currentState!.isSearchOpen, isFalse);
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
    expect(panelKey.currentState!.debugEmojiPageKey.currentState, isNotNull);
  });

  testWidgets('search open hides bottom bar and expands panel target', (
    tester,
  ) async {
    await openReplace(tester);
    expect(panelKey.currentState!.bottomBarVisible, isTrue);
    final base = controller.panelTarget;

    await pumpAsync(tester, panelKey.currentState!.openSearch());
    await tester.pump();

    expect(panelKey.currentState!.bottomBarVisible, isFalse);
    expect(panelKey.currentState!.isSearchOpen, isTrue);
    expect(find.byType(EmojiSearchField), findsOneWidget);
    expect(controller.panelTarget, lessThanOrEqualTo(base + 175));
    expect(controller.panelTarget, greaterThanOrEqualTo(base));
    expect(controller.isSearchExpanded, isTrue);
  });

  testWidgets('handleBack closes search before panel', (tester) async {
    await openReplace(tester);
    await pumpAsync(tester, panelKey.currentState!.openSearch());
    expect(panelKey.currentState!.isSearchOpen, isTrue);

    controller.onImeHeight(0, landscape: false);
    await tester.pump();

    await pumpAsync(tester, panelKey.currentState!.handleBack());
    expect(panelKey.currentState!.isSearchOpen, isFalse);
    expect(panelKey.currentState!.isOpen, isTrue);
    expect(controller.isSearchExpanded, isFalse);
  });

  testWidgets('reselect emoji tab animates to first category', (tester) async {
    await openReplace(tester);
    final page = tester.state<EmojiPageState>(find.byType(EmojiPage));

    // Scroll deep enough that a fixed-duration animateTo would look like a
    // jump; reselect must use jumpToSection (near/far) to section 0.
    await tester.drag(find.byType(EmojiPage), const Offset(0, -2400));
    await tester.pump();
    final before = page.catalogScrollOffset;
    expect(before, greaterThan(EmojiSearchField.height + 100));

    await pumpAsync(
      tester,
      panelKey.currentState!.debugSelectPage(0),
      frames: 180,
    );
    await tester.pumpAndSettle();

    expect(page.categoryIndex, 0);
    expect(
      page.catalogScrollOffset,
      closeTo(EmojiSearchField.height, 1),
    );
  });

  testWidgets('category jump keeps bottom bar visible during animation', (
    tester,
  ) async {
    await openReplace(tester);
    expect(panelKey.currentState!.bottomBarVisible, isTrue);

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
    expect(panelKey.currentState!.bottomBarVisible, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    expect(panelKey.currentState!.bottomBarVisible, isTrue);

    await tester.pumpAndSettle();
    expect(panelKey.currentState!.bottomBarVisible, isTrue);
  });

  Widget allTabsHarness({required bool open}) => MaterialApp(
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
            valueListenable: controller.heightListenable,
            builder: (context, height, child) =>
                SizedBox(height: height < 0 ? 0 : height, child: child),
            child: EmojiPanel(
              key: panelKey,
              open: open,
              controller: controller,
              store: store,
              dataSource: dataSource,
              allow: EmojiPanelAllow.all,
              onEmojiSelected: (_) {},
              onBackspace: () {},
              onStickerSettings: () {},
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> openAllTabs(WidgetTester tester) async {
    await tester.pumpWidget(allTabsHarness(open: false));
    controller.onImeHeight(320, landscape: false);
    controller.openPanel(landscape: false);
    await tester.pumpWidget(allTabsHarness(open: true));
    await panelKey.currentState!.open(replacingKeyboard: true);
    await tester.pump();
  }

  testWidgets('trailing action swaps by panel type tab', (tester) async {
    await openAllTabs(tester);
    expect(panelKey.currentState!.selectedTab, EmojiPanelTab.emoji);
    expect(find.bySemanticsLabel('Settings'), findsNothing);

    await tester.tap(find.text('GIF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(panelKey.currentState!.selectedTab, EmojiPanelTab.gifs);
    expect(find.bySemanticsLabel('Settings'), findsNothing);

    await tester.tap(find.text('Stickers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(panelKey.currentState!.selectedTab, EmojiPanelTab.stickers);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);

    await tester.tap(find.text('Emoji'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(panelKey.currentState!.selectedTab, EmojiPanelTab.emoji);
    expect(find.bySemanticsLabel('Settings'), findsNothing);
  });

  testWidgets('persisted tab opens and selection is saved on switch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat_chrome_emoji_selected_page': EmojiPanelTab.stickers.prefsPage,
    });
    final localStore = KeyboardHeightStore(defaultHeight: 200);
    await localStore.load();
    final localController = ChatBottomInsetController(store: localStore);
    addTearDown(localController.dispose);
    final localKey = GlobalKey<EmojiPanelState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const Expanded(child: SizedBox.expand()),
              SizedBox(
                height: 320,
                child: EmojiPanel(
                  key: localKey,
                  open: false,
                  controller: localController,
                  store: localStore,
                  dataSource: dataSource,
                  allow: EmojiPanelAllow.all,
                  onEmojiSelected: (_) {},
                  onBackspace: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    localController.openPanel(landscape: false);
    await localKey.currentState!.open(replacingKeyboard: true);
    await tester.pump();

    expect(localKey.currentState!.selectedTab, EmojiPanelTab.stickers);
    expect(find.byType(StickerPageStub), findsOneWidget);

    await localKey.currentState!.debugSelectPage(0);
    await tester.pump();

    expect(localKey.currentState!.selectedTab, EmojiPanelTab.emoji);
    expect(localStore.selectedPage, EmojiPanelTab.emoji.prefsPage);
    expect(find.byType(EmojiPage), findsOneWidget);
    expect(find.byType(StickerPageStub), findsNothing);
  });
}

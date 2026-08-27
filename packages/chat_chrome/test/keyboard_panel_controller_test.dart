import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KeyboardPanelStore store;
  late ChatBottomInsetController inset;
  late KeyboardPanelController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = KeyboardPanelStore(defaultHeight: 200);
    await store.load();
    inset = ChatBottomInsetController(store: store);
    controller = KeyboardPanelController(inset: inset, store: store);
  });

  tearDown(() {
    controller.dispose();
    inset.dispose();
  });

  test('open claims inset and notifies even when unbound', () {
    final opens = <bool>[];
    controller.addOpenListener(opens.add);

    expect(controller.isOpen, isFalse);
    expect(inset.isPanelOpen, isFalse);

    controller.open(landscape: false);

    expect(controller.isOpen, isTrue);
    expect(inset.isPanelOpen, isTrue);
    expect(inset.height, 0); // cold open publishes 0
    expect(inset.panelTarget, 200);
    expect(opens, [true]);
  });

  test('open while IME visible claims replace height', () {
    inset.onImeHeight(320, landscape: false);

    controller.open(landscape: false);

    expect(controller.isOpen, isTrue);
    expect(inset.openedReplacingIme, isTrue);
    expect(inset.height, 320);
  });

  test('same-value open is silent no-op', () {
    var calls = 0;
    controller.addOpenListener((_) => calls++);

    controller.open(landscape: false);
    controller.open(landscape: false);

    expect(calls, 1);
    expect(controller.isOpen, isTrue);
  });

  test('close releases inset and notifies when unbound', () {
    final opens = <bool>[];
    controller
      ..addOpenListener(opens.add)
      ..open(landscape: false);
    opens.clear();

    controller.close();

    expect(controller.isOpen, isFalse);
    expect(inset.isPanelOpen, isFalse);
    expect(inset.height, 0);
    expect(opens, [false]);
  });

  test('close waitForIme holds inset floor when unbound', () {
    inset.onImeHeight(310, landscape: false);
    controller.open(landscape: false);
    expect(inset.height, 310);

    controller.close(waitForIme: true);

    expect(controller.isOpen, isFalse);
    expect(inset.isPanelOpen, isFalse);
    expect(inset.isHoldingForIme, isTrue);
    expect(inset.height, 310);
  });

  test('same-value close is silent no-op', () {
    var calls = 0;
    controller.addOpenListener((_) => calls++);

    controller.close();
    expect(calls, 0);

    controller.open(landscape: false);
    calls = 0;
    controller.close();
    controller.close();
    expect(calls, 1);
  });

  test('already-closed waitForIme still invokes projection', () {
    var projected = 0;
    controller.bindProjection(
      onClose: ({required bool waitForIme}) {
        if (waitForIme) projected++;
      },
    );

    controller.close(waitForIme: true);
    expect(projected, 1);
    controller.close(waitForIme: true);
    expect(projected, 2);
  });

  test('addOpenListener dedups; remove clears', () {
    var calls = 0;
    void cb(bool _) => calls++;

    controller
      ..addOpenListener(cb)
      ..addOpenListener(cb)
      ..open(landscape: false);
    expect(calls, 1);

    controller
      ..removeOpenListener(cb)
      ..close();
    expect(calls, 1);
  });

  test('post-dispose open/close/listeners are silent no-ops', () {
    var calls = 0;
    controller.addOpenListener((_) => calls++);
    controller.dispose();

    expect(controller.isDisposed, isTrue);
    controller.open(landscape: false);
    controller.close();
    controller.addOpenListener((_) => calls++);
    expect(controller.isOpen, isFalse);
    expect(inset.isPanelOpen, isFalse);
    expect(calls, 0);
  });

  group('type tab', () {
    test('defaults to store selected page', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        KeyboardPanelStore.selectedPageKey: KeyboardPanelTab.stickers.prefsPage,
      });
      final localStore = KeyboardPanelStore(defaultHeight: 200);
      await localStore.load();
      final localInset = ChatBottomInsetController(store: localStore);
      final local = KeyboardPanelController(
        inset: localInset,
        store: localStore,
      );
      addTearDown(() {
        local.dispose();
        localInset.dispose();
      });

      expect(local.selectedTab, KeyboardPanelTab.stickers);
    });

    test('selectTab commits, persists, and notifies unbound', () async {
      final tabs = <KeyboardPanelTab>[];
      controller.addTabListener(tabs.add);

      expect(controller.selectedTab, KeyboardPanelTab.emoji);
      controller.selectTab(KeyboardPanelTab.gifs);

      expect(controller.selectedTab, KeyboardPanelTab.gifs);
      expect(tabs, [KeyboardPanelTab.gifs]);
      await pumpEventQueue();
      expect(store.selectedPage, KeyboardPanelTab.gifs.prefsPage);
    });

    test('same-value selectTab is silent no-op', () {
      var calls = 0;
      controller.addTabListener((_) => calls++);

      controller.selectTab(KeyboardPanelTab.emoji);
      expect(calls, 0);

      controller.selectTab(KeyboardPanelTab.stickers);
      controller.selectTab(KeyboardPanelTab.stickers);
      expect(calls, 1);
    });

    test('addTabListener dedups; remove clears', () {
      var calls = 0;
      void cb(KeyboardPanelTab _) => calls++;

      controller
        ..addTabListener(cb)
        ..addTabListener(cb)
        ..selectTab(KeyboardPanelTab.gifs);
      expect(calls, 1);

      controller
        ..removeTabListener(cb)
        ..selectTab(KeyboardPanelTab.stickers);
      expect(calls, 1);
    });

    test('adoptTab updates SoT without projecting', () {
      var projected = 0;
      controller.bindProjection(onTab: (_) => projected++);

      controller.adoptTab(KeyboardPanelTab.stickers);
      expect(controller.selectedTab, KeyboardPanelTab.stickers);
      expect(projected, 0);
    });

    test('selectTab projects when bound', () {
      KeyboardPanelTab? projected;
      controller.bindProjection(onTab: (tab) => projected = tab);

      controller.selectTab(KeyboardPanelTab.gifs);
      expect(projected, KeyboardPanelTab.gifs);
    });

    test('post-dispose selectTab is silent no-op', () {
      var calls = 0;
      controller
        ..addTabListener((_) => calls++)
        ..dispose()
        ..selectTab(KeyboardPanelTab.stickers);

      expect(controller.selectedTab, KeyboardPanelTab.emoji);
      expect(calls, 0);
    });
  });

  group('search', () {
    test('openSearch commits and notifies unbound', () {
      final events = <bool>[];
      controller.addSearchListener(events.add);

      expect(controller.isSearchOpen, isFalse);
      controller.openSearch();

      expect(controller.isSearchOpen, isTrue);
      expect(events, [true]);
    });

    test('closeSearch commits and notifies unbound', () {
      final events = <bool>[];
      controller
        ..addSearchListener(events.add)
        ..openSearch();
      events.clear();

      controller.closeSearch();
      expect(controller.isSearchOpen, isFalse);
      expect(events, [false]);
    });

    test('same-value openSearch/closeSearch are silent no-ops', () {
      var calls = 0;
      controller.addSearchListener((_) => calls++);

      controller.closeSearch();
      expect(calls, 0);

      controller.openSearch();
      controller.openSearch();
      expect(calls, 1);

      calls = 0;
      controller.closeSearch();
      controller.closeSearch();
      expect(calls, 1);
    });

    test('openSearch/closeSearch project when bound', () async {
      var opens = 0;
      var closes = 0;
      bool? hideKb;
      controller.bindProjection(
        onSearchOpen: () async {
          opens++;
        },
        onSearchClose: ({required bool hideKeyboard}) async {
          closes++;
          hideKb = hideKeyboard;
        },
      );

      await controller.openSearch();
      expect(opens, 1);

      await controller.closeSearch(hideKeyboard: false);
      expect(closes, 1);
      expect(hideKb, isFalse);
    });

    test('adoptSearch updates SoT without projecting', () {
      var projected = 0;
      controller.bindProjection(
        onSearchOpen: () async {
          projected++;
        },
      );

      controller.adoptSearch(true);
      expect(controller.isSearchOpen, isTrue);
      expect(projected, 0);
    });

    test('close clears search SoT', () {
      final events = <bool>[];
      controller
        ..addSearchListener(events.add)
        ..open(landscape: false)
        ..openSearch();
      events.clear();

      controller.close();
      expect(controller.isSearchOpen, isFalse);
      expect(events, [false]);
    });

    test('addSearchListener dedups; remove clears', () {
      var calls = 0;
      void cb(bool _) => calls++;

      controller
        ..addSearchListener(cb)
        ..addSearchListener(cb)
        ..openSearch();
      expect(calls, 1);

      controller
        ..removeSearchListener(cb)
        ..closeSearch();
      expect(calls, 1);
    });

    test('post-dispose openSearch is silent no-op', () {
      var calls = 0;
      controller
        ..addSearchListener((_) => calls++)
        ..dispose()
        ..openSearch();

      expect(controller.isSearchOpen, isFalse);
      expect(calls, 0);
    });

    test('post-dispose closeSearch is silent no-op', () {
      var calls = 0;
      controller
        ..openSearch()
        ..addSearchListener((_) => calls++)
        ..dispose()
        ..closeSearch();

      expect(calls, 0);
    });
  });

  group('handleBack', () {
    test('closes search first while panel stays open', () {
      controller
        ..open(landscape: false)
        ..openSearch();

      expect(controller.handleBack(), isTrue);
      expect(controller.isSearchOpen, isFalse);
      expect(controller.isOpen, isTrue);
    });

    test('closes panel when search already closed', () {
      controller.open(landscape: false);

      expect(controller.handleBack(), isTrue);
      expect(controller.isOpen, isFalse);
      expect(inset.isPanelOpen, isFalse);
    });

    test('returns false when neither search nor panel is open', () {
      expect(controller.handleBack(), isFalse);
    });

    test('post-dispose returns false', () {
      controller
        ..open(landscape: false)
        ..openSearch()
        ..dispose();

      expect(controller.handleBack(), isFalse);
    });
  });
}

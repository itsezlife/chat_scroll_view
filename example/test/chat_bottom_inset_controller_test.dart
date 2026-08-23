import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KeyboardHeightStore store;
  late ChatBottomInsetController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = KeyboardHeightStore(defaultHeight: 200);
    await store.load();
    controller = ChatBottomInsetController(
      store: store,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('keyboard replace keeps inset through hide glitch 310→0→310', () async {
    controller.onImeHeight(310, landscape: false);
    await pumpEventQueue();

    expect(controller.openPanel(landscape: false), 310);
    expect(controller.height, 310);
    expect(controller.openedReplacingIme, isTrue);

    // Hide animation glitch from keyboard_insets / WindowInsetsAnimation.
    controller.onImeHeight(0, landscape: false);
    controller.onImeHeight(310, landscape: false);
    controller.onImeHeight(200, landscape: false);
    controller.onImeHeight(0, landscape: false);
    await pumpEventQueue();

    expect(controller.isPanelOpen, isTrue);
    expect(controller.height, 310);
  });

  test('cold open publishes 0 then occupancy animates up', () async {
    expect(controller.openPanel(landscape: false), 200);
    expect(controller.openedReplacingIme, isFalse);
    expect(controller.height, 0);
    expect(controller.panelTarget, 200);

    controller.setPanelOccupancy(100);
    expect(controller.height, 100);
    controller.setPanelOccupancy(200);
    expect(controller.height, 200);
  });

  test('poisoned short store height falls back to default', () async {
    await store.record(59, landscape: false); // should be ignored
    expect(store.heightFor(landscape: false), 200);
    expect(controller.openPanel(landscape: false), 200);
  });

  test('record never shrinks a sane height', () async {
    await store.record(310, landscape: false);
    await store.record(59, landscape: false);
    expect(store.heightFor(landscape: false), 310);
  });

  test('rising IME does not auto-dismiss panel', () async {
    controller.onImeHeight(300, landscape: false);
    controller.openPanel(landscape: false);
    expect(controller.isPanelOpen, isTrue);

    controller
      ..onImeHeight(0, landscape: false)
      ..onImeHeight(0, landscape: false)
      ..onImeHeight(0, landscape: false)
      ..onImeHeight(300, landscape: false);
    await pumpEventQueue();

    // Panel stays — close is host-driven only.
    expect(controller.isPanelOpen, isTrue);
    expect(controller.height, 300);
  });

  test('closePanel waitForIme holds through 0→peak→0 glitch', () async {
    controller
      ..onImeHeight(310, landscape: false)
      ..openPanel(landscape: false);
    expect(controller.height, 310);
    controller.closePanel(waitForIme: true);
    expect(controller.height, 310);

    controller.onImeHeight(0, landscape: false);
    expect(controller.height, 310);
    controller.onImeHeight(310, landscape: false);
    expect(controller.height, 310);
    controller.onImeHeight(0, landscape: false);
    expect(controller.height, 310);

    controller.onImeHeight(100, landscape: false);
    expect(controller.height, 310);
    controller.onImeHeight(310, landscape: false);
    expect(controller.height, 310);
    controller.onImeHeight(310, landscape: false);
    expect(controller.height, 310);
    expect(controller.owner, ChatBottomInsetOwner.ime);

    // True zero glitch after release — sticky holds floor.
    controller.onImeHeight(0, landscape: false);
    expect(controller.height, 310);
    controller.onImeHeight(310, landscape: false);
    expect(controller.height, 310);
  });

  test('waitForIme release does not dip below floor on IME undershoot', () async {
    controller
      ..onImeHeight(310.4, landscape: false)
      ..openPanel(landscape: false);
    controller.closePanel(waitForIme: true);
    expect(controller.height, 310.4);

    // IME settles within ε of floor but slightly under — common on Android.
    controller.onImeHeight(309.33, landscape: false);
    expect(controller.height, 310.4);
    controller.onImeHeight(309.33, landscape: false);
    // Hold released; must stay at floor, not publish 309.33.
    expect(controller.height, 310.4);
    controller.onImeHeight(309.69, landscape: false);
    expect(controller.height, 310.4);
    controller.onImeHeight(310.4, landscape: false);
    expect(controller.height, 310.4);
  });

  test(
    'post-hold sticky does not restore floor after gradual IME descent',
    () async {
      controller
        ..onImeHeight(310.4, landscape: false)
        ..openPanel(landscape: false);
      controller.closePanel(waitForIme: true);

      // Hold release (undershoot at floor).
      controller.onImeHeight(309.33, landscape: false);
      controller.onImeHeight(309.33, landscape: false);
      expect(controller.height, closeTo(310.4, 1));

      // Real hide animation after emoji handoff — must not snap back to floor.
      for (final h in <double>[308, 280, 200, 100, 40, 8, 0]) {
        controller.onImeHeight(h, landscape: false);
      }
      expect(controller.height, 0);
    },
  );

  test('expandPanelForSearch raises target by at most 175', () async {
    expect(controller.openPanel(landscape: false), 200);
    controller.setPanelOccupancy(200);
    expect(controller.panelBaseTarget, 200);

    final expanded = controller.expandPanelForSearch(availableMax: 1000);
    expect(expanded, 375);
    expect(controller.panelTarget, 375);
    expect(controller.panelBaseTarget, 200);
    expect(controller.isSearchExpanded, isTrue);

    controller.setPanelOccupancy(375);
    expect(controller.height, 375);

    controller.collapsePanelFromSearch();
    expect(controller.panelTarget, 200);
    expect(controller.isSearchExpanded, isFalse);
    expect(controller.height, 200);
  });

  test('expandPanelForSearch respects availableMax cap', () async {
    controller.openPanel(landscape: false);
    controller.setPanelOccupancy(200);
    final expanded = controller.expandPanelForSearch(availableMax: 300);
    expect(expanded, 300);
    expect(controller.panelTarget, 300);
  });

  test('closePanel clears search expand', () async {
    controller.openPanel(landscape: false);
    controller.expandPanelForSearch(availableMax: 1000);
    expect(controller.isSearchExpanded, isTrue);
    controller.closePanel();
    expect(controller.isSearchExpanded, isFalse);
    expect(controller.panelTarget, 0);
  });
}

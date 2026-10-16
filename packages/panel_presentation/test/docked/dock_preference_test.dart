import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_presentation/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

void main() {
  const desktop = PanelPresentationPolicy$Desktop();
  const wide = PanelWindow(width: 1200, height: 800);
  const narrow = PanelWindow(width: 500, height: 800);

  late FakeKeyValueStore storage;

  Future<KeyValuePreferenceStore> openStore() =>
      KeyValuePreferenceStore.load(storage, namespace: 'host');

  PanelPresentationController build({
    required PreferenceStore? preferences,
    PanelWindow window = wide,
    bool dockPreferred = false,
  }) {
    final shell = PanelShellController(
      pages: [FakePanelPage('emoji').page],
      preferences: FakePreferenceStore(),
    );
    final strategies = [
      FakePresentationStrategy(const AnchoredPopup()),
      FakePresentationStrategy(const Docked()),
    ];
    final controller = PanelPresentationController(
      shell: shell,
      policy: desktop,
      strategies: strategies,
      window: window,
      dockPreferred: dockPreferred,
      preferences: preferences,
    );
    addTearDown(() {
      controller.dispose();
      shell.dispose();
      for (final strategy in strategies) {
        strategy.dispose();
      }
    });
    return controller;
  }

  setUp(() => storage = FakeKeyValueStore());

  group('loading the preference from the store', () {
    test('starts docked-preferred when the store says so', () async {
      final store = await openStore();
      await store.setDockPreferred(preferred: true);

      final controller = build(preferences: await openStore())..show();

      expect(controller.dockPreferred.value, isTrue);
      expect(controller.state.value.kind, const Docked());
    });

    test('lets the store win over the constructor flag', () async {
      final controller = build(
        preferences: await openStore(),
        dockPreferred: true,
      );

      expect(controller.dockPreferred.value, isFalse);
    });

    test('keeps the constructor flag when there is no store', () {
      final controller = build(preferences: null, dockPreferred: true);

      expect(controller.dockPreferred.value, isTrue);
    });
  });

  group('persisting the preference', () {
    test('dock writes it through the store', () async {
      final store = await openStore();
      final controller = build(preferences: store)..show();

      controller.dock();

      expect(store.dockPreferred, isTrue);
      expect((await openStore()).dockPreferred, isTrue);
    });

    test('undock writes the opposite', () async {
      final store = await openStore();
      await store.setDockPreferred(preferred: true);
      final controller = build(preferences: store)..show();

      controller.undock();

      expect(store.dockPreferred, isFalse);
      expect((await openStore()).dockPreferred, isFalse);
    });

    test('toggleDock docks, then undocks', () async {
      final store = await openStore();
      final controller = build(preferences: store)..show();

      controller.toggleDock();
      expect(controller.state.value.kind, const Docked());
      expect(store.dockPreferred, isTrue);

      controller.toggleDock();
      expect(controller.state.value, PanelVisibility.hidden);
      expect(store.dockPreferred, isFalse);
    });

    test('a later controller on the same storage restores the dock', () async {
      build(preferences: await openStore()).dock();

      final restored = build(preferences: await openStore())..show();

      expect(restored.state.value.kind, const Docked());
    });

    test('a failed write is reported and keeps the choice in memory', () async {
      final store = await openStore();
      final controller = build(preferences: store)..show();
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      storage.failure = Exception('disk');

      controller.dock();
      await pumpEventQueue();

      expect(controller.state.value.kind, const Docked());
      expect(controller.dockPreferred.value, isTrue);
      expect(reported, hasLength(1));
      expect(reported.single.library, 'panel_presentation');
    });
  });

  group('following the store', () {
    test('a change made elsewhere moves a popup into the dock', () async {
      final store = await openStore();
      final controller = build(preferences: store)..show();
      expect(controller.state.value.kind, const AnchoredPopup());

      await store.setDockPreferred(preferred: true);

      expect(controller.dockPreferred.value, isTrue);
      expect(controller.state.value.kind, const Docked());
    });

    test('a change of another preference does nothing', () async {
      final store = await openStore();
      final controller = build(preferences: store)..show();

      await store.setSelectedPageId('stickers');

      expect(controller.dockPreferred.value, isFalse);
      expect(controller.state.value.kind, const AnchoredPopup());
    });

    test('stops following once disposed', () async {
      final store = await openStore();
      final controller = build(preferences: store)..show();
      controller.dispose();

      await store.setDockPreferred(preferred: true);

      expect(controller.dockPreferred.value, isFalse);
    });
  });

  group('window class changes while docked', () {
    test('narrowing falls back to a popup and widening docks again', () async {
      final controller = build(preferences: await openStore())
        ..dock()
        ..show();
      expect(controller.state.value.kind, const Docked());

      controller.updateWindow(narrow);
      expect(controller.state.value.kind, const AnchoredPopup());
      expect(controller.dockPreferred.value, isTrue);

      controller.updateWindow(wide);
      expect(controller.state.value.kind, const Docked());
    });

    test('a popup the user opened by choice stays a popup on widening', () {
      final controller = build(preferences: null, window: narrow)
        ..dock()
        ..show();
      expect(controller.state.value.kind, const AnchoredPopup());

      controller.updateWindow(wide);

      expect(controller.state.value.kind, const AnchoredPopup());
    });

    test('undocking while narrowed cancels the return to the dock', () {
      final controller = build(preferences: null)
        ..dock()
        ..show()
        ..updateWindow(narrow)
        ..undock()
        ..updateWindow(wide);

      expect(controller.state.value.kind, const AnchoredPopup());
    });

    test('a hidden panel docks on the next show after widening', () {
      final controller = build(preferences: null)
        ..dock()
        ..show()
        ..updateWindow(narrow)
        ..hide()
        ..updateWindow(wide)
        ..show();

      expect(controller.state.value.kind, const Docked());
    });
  });
}

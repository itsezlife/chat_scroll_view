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
    DockWidthStore? dockWidths,
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
      dockWidths: dockWidths,
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

  group('the window and the dock', () {
    test('narrowing takes the dock away, widening brings it back', () async {
      final controller = build(preferences: await openStore())..dock();
      expect(controller.state.value.kind, const Docked());

      controller.updateWindow(narrow);
      expect(controller.state.value, PanelVisibility.hidden);
      expect(controller.dockPreferred.value, isTrue);

      controller.updateWindow(wide);
      expect(controller.state.value.kind, const Docked());
    });

    test('a popup open in a window that then has the room gives way to the '
        'preferred dock', () {
      final controller = build(preferences: null, window: narrow)
        ..dock()
        ..show();
      expect(controller.state.value.kind, const AnchoredPopup());

      controller.updateWindow(wide);

      expect(controller.state.value.kind, const Docked());
    });

    test('undocking while narrowed cancels the return to the dock', () {
      final controller = build(preferences: null)
        ..dock()
        ..updateWindow(narrow)
        ..undock()
        ..updateWindow(wide);

      expect(controller.state.value, PanelVisibility.hidden);
    });

    test('a window that never had the room shows a preferred dock as a popup '
        'when asked', () {
      final controller = build(preferences: null, window: narrow)
        ..dock()
        ..show();

      expect(controller.state.value.kind, const AnchoredPopup());
    });

    test('a dock the host hid stays hidden until the window or the choice '
        'changes', () {
      final controller = build(preferences: null)
        ..dock()
        ..hide()
        ..updateWindow(const PanelWindow(width: 1300, height: 800));
      expect(controller.state.value, PanelVisibility.hidden);

      controller
        ..updateWindow(narrow)
        ..updateWindow(wide);

      expect(controller.state.value.kind, const Docked());
    });

    test('back does not hide a dock, and Escape is the shell\'s', () {
      final controller = build(preferences: null)..dock();

      expect(controller.handleBack(), isFalse);
      expect(controller.state.value.kind, const Docked());
    });
  });

  group('the dock\'s width', () {
    test('is the wish as dragged until the drag ends', () {
      final controller = build(preferences: null)..dock();

      controller.resizeDock(500);

      expect(controller.dockWanted.value, 500);
    });

    test('ends held to the policy\'s bounds', () {
      final controller = build(preferences: null)..dock();

      controller
        ..resizeDock(500)
        ..endDockResize();
      expect(controller.dockWanted.value, 392);

      controller
        ..resizeDock(10)
        ..endDockResize();
      expect(controller.dockWanted.value, 292);
    });

    test('ignores a width that is not a number', () {
      final controller = build(preferences: null)..resizeDock(double.nan);

      expect(controller.dockWanted.value, isNull);
    });

    test(
      'is kept in the store, and a later controller starts from it',
      () async {
        final widths = await DockWidthStore.open(storage);
        final controller = build(preferences: null, dockWidths: widths)
          ..resizeDock(333)
          ..endDockResize();
        await pumpEventQueue();

        final later = build(
          preferences: null,
          dockWidths: await DockWidthStore.open(storage),
        );

        expect(widths.width, 333);
        expect(controller.dockWanted.value, 333);
        expect(later.dockWanted.value, 333);
      },
    );

    test('a resize with nothing dragged keeps nothing', () async {
      final widths = await DockWidthStore.open(storage);
      build(preferences: null, dockWidths: widths).endDockResize();

      expect(widths.width, isNull);
    });
  });
}

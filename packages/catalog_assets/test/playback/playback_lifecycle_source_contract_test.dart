import 'dart:ui' show AppLifecycleState;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ManualPlaybackLifecycleSource', () {
    PlaybackLifecycleSourceContract.run(() {
      final source = ManualPlaybackLifecycleSource();
      return PlaybackLifecycleHarness(
        source: source,
        emit: source.emit,
        dispose: source.dispose,
      );
    });

    test('reports the state it was given at the start', () {
      final source = ManualPlaybackLifecycleSource(
        initial: AppLifecycleState.inactive,
      );
      addTearDown(source.dispose);

      expect(source.state, AppLifecycleState.inactive);
    });

    test('emitAll delivers a jump as the platform does, state by state', () {
      final source = ManualPlaybackLifecycleSource(
        initial: AppLifecycleState.resumed,
      );
      addTearDown(source.dispose);
      final heard = <AppLifecycleState?>[];
      source.addListener(() => heard.add(source.state));

      source.emitAll([AppLifecycleState.inactive, AppLifecycleState.hidden]);

      expect(heard, [AppLifecycleState.inactive, AppLifecycleState.hidden]);
    });
  });

  group('WidgetsPlaybackLifecycleSource', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    // The binding is process-wide and these tests move its lifecycle (and
    // `hidden` turns its frames off): give it back as found.
    final before = binding.lifecycleState;

    PlaybackLifecycleSourceContract.run(
      () {
        final source = WidgetsPlaybackLifecycleSource();
        return PlaybackLifecycleHarness(
          source: source,
          initialState: binding.lifecycleState,
          emit: binding.handleAppLifecycleStateChanged,
          dispose: source.dispose,
        );
      },
      tearDownHarness: () {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        if (before == null) binding.resetInternalState();
      },
    );

    test('starts at the binding\'s state, not at resumed', () {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      addTearDown(
        () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      );

      final source = WidgetsPlaybackLifecycleSource();
      addTearDown(source.dispose);

      expect(source.state, AppLifecycleState.inactive);
    });
  });
}

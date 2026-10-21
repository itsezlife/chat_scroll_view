import 'dart:ui' show AppLifecycleState;

import 'package:catalog_assets/src/playback/playback_lifecycle_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a [PlaybackLifecycleSource] contract run needs besides the source: a
/// way to make the platform report a state, and to end the source.
final class PlaybackLifecycleHarness {
  /// Creates a harness around [source].
  const PlaybackLifecycleHarness({
    required this.source,
    required this.emit,
    required this.dispose,
    this.initialState,
  });

  /// The source under test.
  final PlaybackLifecycleSource source;

  /// The state [source] reports before anything is emitted.
  final AppLifecycleState? initialState;

  /// Makes the platform report [state].
  final void Function(AppLifecycleState state) emit;

  /// Disposes [source].
  final void Function() dispose;
}

/// The contract every [PlaybackLifecycleSource] meets; see its documentation.
abstract final class PlaybackLifecycleSourceContract {
  /// Runs it as a test group. [create] builds a fresh harness for each test;
  /// [tearDownHarness] undoes what the platform emitted that outlives the
  /// source (the widgets binding is process-wide state).
  static void run(
    PlaybackLifecycleHarness Function() create, {
    void Function()? tearDownHarness,
  }) {
    group('PlaybackLifecycleSource contract', () {
      late PlaybackLifecycleHarness harness;
      late List<AppLifecycleState?> heard;

      setUp(() {
        harness = create();
        heard = <AppLifecycleState?>[];
      });
      tearDown(() {
        harness.dispose();
        tearDownHarness?.call();
      });

      void listen() =>
          harness.source.addListener(() => heard.add(harness.source.state));

      test('starts at what the platform said last, or at null', () {
        expect(harness.source.state, harness.initialState);
      });

      test('each distinct change notifies once, in order, with the new '
          'state already readable', () {
        listen();

        harness.emit(AppLifecycleState.inactive);
        harness.emit(AppLifecycleState.hidden);
        harness.emit(AppLifecycleState.inactive);
        harness.emit(AppLifecycleState.resumed);

        expect(heard, [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]);
      });

      test('the state it already has notifies nothing', () {
        harness.emit(AppLifecycleState.inactive);
        listen();

        harness.emit(AppLifecycleState.inactive);
        harness.emit(AppLifecycleState.inactive);

        expect(heard, isEmpty);
        expect(harness.source.state, AppLifecycleState.inactive);
      });

      test('says nothing after it is disposed, and a late report is '
          'harmless', () {
        listen();
        harness.emit(AppLifecycleState.inactive);

        harness.dispose();
        harness.emit(AppLifecycleState.hidden);

        expect(heard, [AppLifecycleState.inactive]);
      });

      test('disposing twice does nothing', () {
        harness.dispose();
        harness.dispose();
      });
    });
  }
}

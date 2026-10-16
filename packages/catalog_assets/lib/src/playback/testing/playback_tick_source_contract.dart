import 'package:catalog_assets/src/playback/playback_tick_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a [PlaybackTickSource] contract run needs besides the source: a way to
/// make the engine produce [frames] frames, `step` for each.
final class PlaybackTickHarness {
  /// Creates a harness around [source]; [pumpFrame] produces one frame.
  const PlaybackTickHarness({required this.source, required this.pumpFrame});

  /// The source under test.
  final PlaybackTickSource source;

  /// Makes the engine run one frame (a test binding pump, a manual tick).
  final Future<void> Function() pumpFrame;
}

/// The contract every [PlaybackTickSource] meets; see its documentation.
///
/// [create] builds a fresh harness for each test.
void runPlaybackTickSourceContract(PlaybackTickHarness Function() create) {
  group('PlaybackTickSource contract', () {
    late PlaybackTickHarness harness;
    late List<Duration> ticks;

    setUp(() {
      harness = create();
      ticks = <Duration>[];
    });
    tearDown(() => harness.source.stop());

    test('delivers one tick per frame, in order', () async {
      harness.source.start(ticks.add);

      await harness.pumpFrame();
      await harness.pumpFrame();
      await harness.pumpFrame();

      expect(ticks, hasLength(3));
      expect(ticks, orderedEquals([...ticks]..sort()));
    });

    test('delivers nothing before it is started', () async {
      await harness.pumpFrame();

      expect(ticks, isEmpty);
    });

    test('delivers nothing after it is stopped', () async {
      harness.source.start(ticks.add);
      await harness.pumpFrame();

      harness.source.stop();
      await harness.pumpFrame();
      await harness.pumpFrame();

      expect(ticks, hasLength(1));
    });

    test('starting while running keeps the first callback', () async {
      final second = <Duration>[];
      harness.source
        ..start(ticks.add)
        ..start(second.add);

      await harness.pumpFrame();

      expect(ticks, hasLength(1));
      expect(second, isEmpty);
    });

    test('stopping while stopped does nothing, and it can restart', () async {
      harness.source
        ..stop()
        ..start(ticks.add);

      await harness.pumpFrame();

      expect(ticks, hasLength(1));
    });
  });
}

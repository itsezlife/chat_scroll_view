import 'package:catalog_assets/src/playback/scheduler_playback_tick_source.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ManualPlaybackTickSource', () {
    var clock = Duration.zero;
    PlaybackTickSourceContract.run(() {
      final source = ManualPlaybackTickSource();
      return PlaybackTickHarness(
        source: source,
        pumpFrame: () async {
          clock += const Duration(milliseconds: 16);
          source.tick(clock);
        },
      );
    });
  });

  group('SchedulerPlaybackTickSource', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    var timestamp = Duration.zero;
    PlaybackTickSourceContract.run(
      () => PlaybackTickHarness(
        source: SchedulerPlaybackTickSource(),
        pumpFrame: () async {
          // One engine frame by hand: only callbacks requested run.
          timestamp += const Duration(milliseconds: 16);
          binding
            ..handleBeginFrame(timestamp)
            ..handleDrawFrame();
        },
      ),
    );

    test('leaves no frame callback requested once stopped', () {
      final before = SchedulerBinding.instance.transientCallbackCount;
      final source = SchedulerPlaybackTickSource()
        ..start((_) {})
        ..stop();

      expect(SchedulerBinding.instance.transientCallbackCount, before);
      source.stop();
    });
  });
}

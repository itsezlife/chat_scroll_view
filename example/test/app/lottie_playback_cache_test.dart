/// The frame cache of the Lottie playback: frames rendered once are replayed
/// instead of rendered again, in the same run and in the next one.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/app/environment_specific/lottie_playback_vm.dart'
    as vm;
import 'package:chat_scroll_view_example/src/app/lottie_playback.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_decoder/testing.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

final _bytes = Uint8List.fromList([1, 2, 3]);
const _info = LottieInfo(
  width: 64,
  height: 64,
  frameCount: 10,
  frameRate: 30,
  features: LottieFeatures.none,
);

const _descriptor = ContentDescriptor(
  key: ContentKey.document('cached'),
  semanticKind: SemanticKind.customEmoji,
  mediaForm: MediaForm.vectorAnimation,
  animated: true,
);

/// Keeps what one decode reported.
final class _Report implements AssetProgress {
  final List<AssetPaintable> animations = [];

  @override
  void advance(
    AssetStage stage,
    AssetPaintable paintable, {
    required int bytes,
    AssetTier tier = AssetTier.still,
  }) {
    if (stage == AssetStage.full) animations.add(paintable);
  }

  @override
  void fail(
    Object error, [
    StackTrace? stackTrace,
    AssetFailureKind kind = AssetFailureKind.transient,
  ]) => throw StateError('the decode failed: $error');

  @override
  void cancelled() {}
}

void main() {
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late ChangeNotifier pressure;
  late Directory dir;
  var time = Duration.zero;

  setUp(() {
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    pressure = ChangeNotifier();
    dir = Directory.systemTemp.createTempSync('lottie_cache_test_');
    time = Duration.zero;
    addTearDown(() {
      clock.dispose();
      pressure.dispose();
      dir.deleteSync(recursive: true);
    });
  });

  CountingLottieEngine newEngine() => CountingLottieEngine(
    InProcessLottieEngine(
      FakeLottieBinding()..accept(_bytes, _info),
      codec: FakeLottieFrameCodec(),
    ),
  );

  Future<LottiePlayback> startOver(
    CountingLottieEngine engine, {
    String? cacheDirectory,
  }) async {
    final playback = await vm.$startLottiePlayback(
      clock: clock,
      memoryPressure: pressure,
      cacheDirectory: cacheDirectory,
      spawn: () async => engine,
    );
    return playback!;
  }

  /// Room for a batch: the page upload after a render takes real time.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 8));

  /// Decodes the animation and paints it for [ticksToPlay] ticks, a tick
  /// being 16 ms of the playback clock.
  Future<void> play(LottiePlayback playback, int ticksToPlay) async {
    final report = _Report();
    playback.decoder.decode(
      DecodeRequest(
        descriptor: _descriptor,
        spec: const AssetSpec(pixelWidth: 64, pixelHeight: 64),
        part: FetchPart.content,
        content: FetchedContent.bytes(_bytes),
      ),
      report,
    );
    // The first frame goes through the engine's image machinery, which takes
    // real time.
    for (var i = 0; i < 400 && report.animations.isEmpty; i++) {
      await settle();
    }
    final paintable = report.animations.single;
    for (var i = 0; i < ticksToPlay; i++) {
      final recorder = ui.PictureRecorder();
      paintable.paint(
        ui.Canvas(recorder),
        const ui.Rect.fromLTWH(0, 0, 64, 64),
        AssetPaintContext(
          time: time,
          loop: true,
          restFrame: AssetRestFrame.first,
          animate: true,
          opacity: 1,
        ),
      );
      recorder.endRecording().dispose();
      time += const Duration(milliseconds: 16);
      ticks.tick(time);
      await settle();
    }
    paintable.dispose();
  }

  // Two loops of the ten frames at 30 fps, at 16 ms a tick: every frame is
  // asked for at least once even if a tick coalesces.
  const twoLoops = 80;

  test('frames played once are replayed in the same run, not rendered '
      'again', () async {
    final engine = newEngine();
    final playback = await startOver(engine);
    addTearDown(playback.close);

    await play(playback, twoLoops);
    final renderedOnce = engine.rendered;
    await play(playback, twoLoops);

    expect(renderedOnce, greaterThan(1));
    expect(engine.restored, greaterThan(0), reason: 'the replay restored');
    expect(
      engine.rendered,
      renderedOnce + 1,
      reason: 'only the decoder\'s first frame rendered in the second play',
    );
  });

  test('a new run on the same directory replays what the last one '
      'rendered', () async {
    final first = newEngine();
    final earlier = await startOver(first, cacheDirectory: dir.path);
    await play(earlier, twoLoops);
    await earlier.close();
    expect(
      dir.listSync().where((e) => e.path.endsWith('.frames')),
      hasLength(1),
      reason: 'close flushed the animation to disk',
    );

    final second = newEngine();
    final later = await startOver(second, cacheDirectory: dir.path);
    addTearDown(later.close);
    await play(later, twoLoops);

    expect(second.rendered, 1, reason: 'only the decoder\'s first frame');
    expect(second.restored, greaterThan(0));
  });

  test('close flushes the cache to disk and closes the engine', () async {
    final engine = newEngine();
    final playback = await startOver(engine, cacheDirectory: dir.path);
    await play(playback, twoLoops);

    await playback.close();

    expect(
      dir.listSync().where((e) => e.path.endsWith('.frames')),
      hasLength(1),
    );
    await expectLater(engine.load(_bytes), throwsStateError);
  });
}

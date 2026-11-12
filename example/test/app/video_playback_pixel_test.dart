/// The web's video start: probed by building an engine over the browser's
/// element, registered only when that works. The element is the engine's
/// in-memory fake, so this runs on the VM; the browser path is not covered
/// here.
library;

import 'dart:async';
import 'dart:io';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/app/video_playback.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';

/// The app bundle as the files under `assets/` on disk.
final class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

void main() {
  late PlaybackClock clock;
  late ChangeNotifier pressure;

  setUp(() {
    clock = PlaybackClock(ticks: ManualPlaybackTickSource());
    pressure = ChangeNotifier();
  });
  tearDown(() {
    clock.dispose();
    pressure.dispose();
  });

  test('an engine that cannot start gives no playback, and says so once, with '
      'its type', () async {
    final logged = <String>[];
    final subscription = l.listen(
      (message) => logged.add('${message.message}'),
    );
    addTearDown(subscription.cancel);

    final playback = await VideoPlayback.startPixel(
      clock: clock,
      memoryPressure: pressure,
      engineFactory: () async => throw const FormatException('no element'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(playback, isNull);
    expect(logged.where((line) => line.contains('Video')), hasLength(1));
    expect(logged.single, contains('FormatException'));
  });

  test('a web engine gives a decoder that takes a demo clip to full through '
      'the pipeline, and close releases every element', () async {
    final sticker = VideoStickerPack.stickers.first;
    final bytes = await File(sticker.assetPath).readAsBytes();
    final elements = FakeVideoElements()
      ..accept(
        bytes,
        const VideoElementMetadata(
          width: 512,
          height: 512,
          duration: Duration(seconds: 2),
          hasAlpha: true,
        ),
        frameCount: 40,
      );

    final playback = await VideoPlayback.startPixel(
      clock: clock,
      memoryPressure: pressure,
      engineFactory: () async => WebVideoEngine(createPort: elements.create),
    );
    expect(playback, isNotNull);

    final pipeline = AssetPipeline(
      fetcher: BundledPacks.fetcher(_DiskBundle()),
      decoders: DecoderRegistry()..register(MediaForm.video, playback!.decoder),
    );
    BundledPacks.descriptors.forEach(pipeline.know);
    final scope = AssetCacheScope(producer: pipeline, clock: clock);
    final attached = scope.attach(
      sticker.key,
      const AssetSpec(pixelWidth: 128, pixelHeight: 128),
      const AssetProfile(animate: true),
    );
    final full = Completer<void>();
    void check() {
      if (attached.readiness.stage == AssetStage.full && !full.isCompleted) {
        full.complete();
      }
    }

    attached.addListener(check);
    check();
    await full.future.timeout(const Duration(seconds: 10));

    expect(attached.paintable.isAnimated, isTrue);
    expect(elements.live, 1);

    attached.detach();
    scope.dispose();
    pipeline.dispose();
    await playback.close();
    expect(elements.live, 0);
  });
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

import '../support/fixtures.dart';

/// Records what one decode reported.
final class _Report implements AssetProgress {
  final List<({AssetStage stage, AssetPaintable paintable})> advances = [];
  final List<Object> failures = [];

  @override
  void advance(
    AssetStage stage,
    AssetPaintable paintable, {
    required int bytes,
    AssetTier tier = AssetTier.still,
  }) => advances.add((stage: stage, paintable: paintable));

  @override
  void fail(
    Object error, [
    StackTrace? stackTrace,
    AssetFailureKind kind = AssetFailureKind.transient,
  ]) => failures.add(error);

  @override
  void cancelled() {}
}

/// Keeps the image of the one `drawImageRect` it is given.
final class _RecordingCanvas implements ui.Canvas {
  ui.Image? image;

  @override
  void drawImageRect(
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  ) => this.image = image;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

DecodeRequest _request(Fixture fixture, int edge) => DecodeRequest(
  descriptor: const ContentDescriptor(
    key: ContentKey.document('fixture'),
    semanticKind: SemanticKind.customEmoji,
    mediaForm: MediaForm.video,
    animated: true,
  ),
  spec: AssetSpec(pixelWidth: edge, pixelHeight: edge),
  part: FetchPart.content,
  content: FetchedContent.bytes(fixture.bytes),
);

/// The whole pipeline over the real FFmpeg build: decoder, engine, scheduler,
/// pool and paintable. Skips where the native library is not bundled.
void main() {
  group('VideoDecoder over the native binding', skip: nativeSkipReason(), () {
    late VideoEngine engine;
    late ListFramePageMemory memory;
    late ManualPlaybackTickSource ticks;
    late PlaybackClock clock;
    late VideoFrameScheduler scheduler;
    late VideoDecoder decoder;

    setUp(() {
      engine = InProcessVideoEngine(NativeVideoBinding.probe());
      memory = ListFramePageMemory();
      ticks = ManualPlaybackTickSource();
      clock = PlaybackClock(ticks: ticks);
      scheduler = VideoFrameScheduler(
        engine: engine,
        atlas: VideoFrameAtlas.create(memory: memory),
        clock: clock,
        startTimer: ManualRetentionTimers().start,
      );
      decoder = VideoDecoder(engine: engine, scheduler: scheduler);
    });
    tearDown(() async {
      scheduler.dispose();
      clock.dispose();
      await engine.dispose();
    });

    Future<_Report> decode(Fixture fixture, int edge) async {
      final report = _Report();
      decoder.decode(_request(fixture, edge), report);
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (report.advances.length < 2 &&
          report.failures.isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return report;
    }

    test('an alpha WebM plays into the pool with its transparency', () async {
      final report = await decode(webm, 64);
      expect(report.failures, isEmpty);
      expect(report.advances.map((a) => a.stage), [
        AssetStage.firstFrame,
        AssetStage.full,
      ]);
      final animation = report.advances.last.paintable;

      var played = 0;
      for (var i = 0; i < 40; i++) {
        played += 33;
        animation.advancePlayback(
          AssetPaintContext(time: Duration(milliseconds: played)),
        );
        ticks.tick(Duration(milliseconds: played));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(animation.sprite, isNotNull);
      final sprite = animation.sprite!;
      final side = memory.sideOf(sprite.pageIndex);
      final page = memory.page(sprite.pageIndex, side: side);
      var transparent = 0;
      var opaque = 0;
      for (var y = 0; y < 64; y++) {
        final row =
            ((sprite.source.top.toInt() + y) * side +
                sprite.source.left.toInt()) *
            4;
        for (var x = 0; x < 64; x++) {
          final alpha = page[row + x * 4 + 3];
          if (alpha == 0) transparent++;
          if (alpha > 0) opaque++;
        }
      }
      // A sticker on a transparent ground: both kinds of pixel survive.
      expect(transparent, greaterThan(0));
      expect(opaque, greaterThan(0));
      animation.dispose();
    });

    test('a GIF keeps its aspect at the snapped size', () async {
      final report = await decode(gif, 100);

      expect(report.failures, isEmpty);
      final canvas = _RecordingCanvas();
      report.advances.first.paintable.paint(
        canvas,
        const ui.Rect.fromLTWH(0, 0, 128, 96),
        const AssetPaintContext(),
      );
      // 64x48 snapped to the 128 class is 128x96, the same three to four.
      expect((canvas.image!.width, canvas.image!.height), (128, 96));
      report.advances.last.paintable.dispose();
    });

    test('a file that is not a video fails with the rejection', () async {
      final report = _Report();
      decoder.decode(
        DecodeRequest(
          descriptor: const ContentDescriptor(
            key: ContentKey.document('bad'),
            semanticKind: SemanticKind.customEmoji,
            mediaForm: MediaForm.video,
            animated: true,
          ),
          spec: const AssetSpec(pixelWidth: 64, pixelHeight: 64),
          part: FetchPart.content,
          content: FetchedContent.bytes(Uint8List(2048)),
        ),
        report,
      );
      while (report.failures.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(
        report.failures.single,
        isA<VideoDecodeRejected>().having(
          (e) => e.reason,
          'reason',
          VideoRejection.malformed,
        ),
      );
    });
  });
}

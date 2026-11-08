import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

import '../support/gated_video_engine.dart';

const _descriptor = ContentDescriptor(
  key: ContentKey.document('fixture'),
  semanticKind: SemanticKind.customEmoji,
  mediaForm: MediaForm.video,
  animated: true,
);

ui.Image _image([int side = 4]) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(side, side);
  picture.dispose();
  return image;
}

DecodeRequest _request(
  Uint8List bytes, {
  FetchPart part = FetchPart.content,
  AssetSpec spec = const AssetSpec(pixelWidth: 64, pixelHeight: 64),
  FetchedContent? content,
}) => DecodeRequest(
  descriptor: _descriptor,
  spec: spec,
  part: part,
  content: content ?? FetchedContent.bytes(bytes),
);

VideoInfo _info(int width, int height) => VideoInfo(
  width: width,
  height: height,
  duration: const Duration(milliseconds: 100),
  frameRate: 30,
  hasAlpha: true,
);

/// Everything one decode reported, paintables and errors included.
final class _Report implements AssetProgress {
  final List<
    ({AssetStage stage, AssetPaintable paintable, int bytes, AssetTier tier})
  >
  advances = [];
  final List<({Object error, AssetFailureKind kind})> failures = [];
  int cancels = 0;

  @override
  void advance(
    AssetStage stage,
    AssetPaintable paintable, {
    required int bytes,
    AssetTier tier = AssetTier.still,
  }) => advances.add((
    stage: stage,
    paintable: paintable,
    bytes: bytes,
    tier: tier,
  ));

  @override
  void fail(
    Object error, [
    StackTrace? stackTrace,
    AssetFailureKind kind = AssetFailureKind.transient,
  ]) => failures.add((error: error, kind: kind));

  @override
  void download(double fraction) {}

  @override
  void cancelled() => cancels++;
}

void main() {
  final good = Uint8List.fromList([1, 2, 3]);
  final wide = Uint8List.fromList([4, 5, 6]);
  final refused = Uint8List.fromList([7]);
  final bad = Uint8List.fromList([9]);

  late FakeVideoEngine fake;
  late GatedVideoEngine engine;
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late VideoFrameScheduler scheduler;
  late VideoDecoder decoder;
  late List<({Uint8List pixels, int width, int height})> uploaded;

  setUp(() {
    fake = FakeVideoEngine()
      ..accept(good, _info(64, 64), frameCount: 3)
      ..accept(wide, _info(32, 16), frameCount: 3)
      ..reject(refused, VideoRejection.unsupported);
    engine = GatedVideoEngine(fake);
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    uploaded = [];
    scheduler = VideoFrameScheduler(
      engine: engine,
      atlas: VideoFrameAtlas.create(upload: (pixels, side) async => _image()),
      clock: clock,
      startTimer: ManualRetentionTimers().start,
    );
    decoder = VideoDecoder(
      engine: engine,
      scheduler: scheduler,
      decodeImage: (bytes) async => _image(),
      uploadPixels: (pixels, width, height) async {
        uploaded.add((pixels: pixels, width: width, height: height));
        return _image();
      },
    );
  });
  tearDown(() async {
    scheduler.dispose();
    clock.dispose();
    await fake.dispose();
  });

  group('over the fake engine', () {
    DecoderContract.run(
      () => DecoderHarness(
        decoder: decoder,
        valid: (part, spec) => _request(good, part: part, spec: spec),
        invalid: () => _request(bad),
      ),
    );
  });

  group('VideoDecoder', () {
    test('a full decode reports the still, then the animation', () async {
      final report = _Report();

      decoder.decode(_request(good), report);
      await pumpEventQueue();

      expect(report.advances.map((a) => a.stage), [
        AssetStage.firstFrame,
        AssetStage.full,
      ]);
      expect(report.advances.last.paintable.isAnimated, isTrue);
      expect(report.advances.last.tier, AssetTier.animated);
      expect(report.advances.first.paintable.isAnimated, isFalse);
      expect(report.failures, isEmpty);
    });

    test('the still is the clip first frame, as decoded', () async {
      decoder.decode(_request(good), _Report());
      await pumpEventQueue();

      final frame = uploaded.single;
      expect((frame.width, frame.height), (64, 64));
      expect(frame.pixels, hasLength(64 * 64 * 4));
      // The fake's frame 0: B 0, G 0, R 0, alpha 200, premultiplied BGRA.
      expect(frame.pixels.sublist(0, 4), [0, 0, 0, 200]);
    });

    test(
      'a first-frame-only decode ends with the still and frees the clip',
      () async {
        final report = _Report();

        decoder.decode(
          _request(
            good,
            spec: const AssetSpec(
              pixelWidth: 64,
              pixelHeight: 64,
              variant: AssetVariant.firstFrame,
            ),
          ),
          report,
        );
        await pumpEventQueue();

        expect(report.advances.map((a) => a.stage), [AssetStage.firstFrame]);
        expect(fake.openClips, 0);
      },
    );

    test('a thumbnail is an ordinary image: the placeholder', () async {
      final report = _Report();

      decoder.decode(_request(good, part: FetchPart.thumbnail), report);
      await pumpEventQueue();

      expect(report.advances.map((a) => a.stage), [AssetStage.placeholder]);
      expect(fake.openClips, 0);
    });

    testWidgets(
      'by default a thumbnail is decoded small, as a mini-thumbnail',
      (tester) async {
        final report = _Report();
        final plain = VideoDecoder(engine: engine, scheduler: scheduler);
        await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          ui.Canvas(recorder).drawRect(
            const ui.Rect.fromLTWH(0, 0, 100, 100),
            ui.Paint()..color = const ui.Color(0xFF336699),
          );
          final picture = recorder.endRecording();
          final source = await picture.toImage(200, 100);
          picture.dispose();
          final png = (await source.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          source.dispose();

          plain.decode(
            _request(png.buffer.asUint8List(), part: FetchPart.thumbnail),
            report,
          );
          while (report.advances.isEmpty && report.failures.isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        });

        expect(report.failures, isEmpty);
        // 40 x 20 pixels at 4 bytes each, not the 200 x 100 of the file.
        expect(report.advances.single.bytes, 40 * 20 * 4);
      },
    );

    test(
      'a rejected clip fails permanently with the reason and holds nothing',
      () async {
        final report = _Report();

        decoder.decode(_request(refused), report);
        await pumpEventQueue();

        final failure = report.failures.single;
        expect(failure.kind, AssetFailureKind.permanent);
        expect(
          failure.error,
          isA<VideoDecodeRejected>().having(
            (e) => e.reason,
            'reason',
            VideoRejection.unsupported,
          ),
        );
        expect(report.advances, isEmpty);
        expect(fake.openClips, 0);
      },
    );

    test(
      'decodes at the size class the spec snaps to, keeping the aspect',
      () async {
        decoder.decode(
          _request(
            wide,
            spec: const AssetSpec(pixelWidth: 100, pixelHeight: 100),
          ),
          _Report(),
        );
        await pumpEventQueue();

        // 100 px snaps up to the 128 class; 32x16 keeps its two to one.
        final frame = uploaded.single;
        expect((frame.width, frame.height), (128, 64));
        // The square probe was closed; the clip that plays is the fitted one.
        expect(fake.openClips, 1);
      },
    );

    test('a file on disk is read and decoded like bytes', () async {
      final dir = Directory.systemTemp.createTempSync('video_decoder_file_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}clip.webm')
        ..writeAsBytesSync(good);
      final report = _Report();

      decoder.decode(
        _request(good, content: FetchedContent.file(file.path)),
        report,
      );
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (report.advances.length < 2 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await pumpEventQueue();
      }

      expect(report.advances.map((a) => a.stage), [
        AssetStage.firstFrame,
        AssetStage.full,
      ]);
    });

    test(
      'a cancel while the first frame decodes reports nothing and frees the clip',
      () async {
        final report = _Report();
        engine.hold();

        final task = decoder.decode(_request(good), report);
        await pumpEventQueue();
        task.cancel();
        engine.release();
        await pumpEventQueue();

        expect(report.advances, isEmpty);
        expect(report.failures, isEmpty);
        expect(fake.openClips, 0);
      },
    );

    test('disposing the animation closes its clip', () async {
      final report = _Report();
      decoder.decode(_request(good), report);
      await pumpEventQueue();
      expect(fake.openClips, 1);

      report.advances.last.paintable.dispose();
      await pumpEventQueue();

      expect(fake.openClips, 0);
    });

    test('reports the still and the encoded size as the cost', () async {
      final report = _Report();

      decoder.decode(_request(good), report);
      await pumpEventQueue();

      expect(report.advances.first.bytes, 64 * 64 * 4);
      expect(report.advances.last.bytes, 64 * 64 * 4 + good.length);
    });
  });
}

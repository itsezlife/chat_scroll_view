import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

final _fakeBytes = Uint8List.fromList([1, 2, 3]);
final _badBytes = Uint8List.fromList([9]);

const _info = LottieInfo(
  width: 64,
  height: 64,
  frameCount: 10,
  frameRate: 30,
  features: LottieFeatures.none,
);

const _descriptor = ContentDescriptor(
  key: ContentKey.document('fixture'),
  semanticKind: SemanticKind.customEmoji,
  mediaForm: MediaForm.vectorAnimation,
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
}) => DecodeRequest(
  descriptor: _descriptor,
  spec: spec,
  part: part,
  content: FetchedContent.bytes(bytes),
);

/// The fake binding, an in-process engine over it and a decoder, with the
/// image steps replaced so no test needs the engine's image machinery.
final class _Rig {
  _Rig({LottieImageDecoder? decodeImage, LottiePixelUploader? upload})
    : binding = FakeLottieBinding()..accept(_fakeBytes, _info) {
    engine = InProcessLottieEngine(binding);
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    scheduler = LottieFrameScheduler(
      atlas: FrameAtlas<Object>(
        renderer: FakeFrameRenderer(),
        memory: ListFramePageMemory(pageSide: 1024),
        sizeClasses: const [64, 128, 256, 512],
        upload: (pixels, side) async => _image(),
      ),
      clock: clock,
      startTimer: ManualRetentionTimers().start,
    );
    decoder = LottieDecoder(
      engine: engine,
      scheduler: scheduler,
      decodeImage: decodeImage ?? (bytes) async => _image(),
      uploadPixels:
          upload ??
          (pixels, width, height) async {
            uploaded.add((pixels: pixels, width: width, height: height));
            return _image();
          },
    );
  }

  final FakeLottieBinding binding;
  late final InProcessLottieEngine engine;
  late final ManualPlaybackTickSource ticks;
  late final PlaybackClock clock;
  late final LottieFrameScheduler scheduler;
  late final LottieDecoder decoder;
  final List<({Uint8List pixels, int width, int height})> uploaded = [];

  void close() {
    scheduler.dispose();
    clock.dispose();
  }
}

/// Everything one decode reported, paintables included.
final class _Report implements AssetProgress {
  final List<({AssetStage stage, AssetPaintable paintable, int bytes})>
  advances = [];
  final List<AssetFailureKind> failures = [];

  @override
  void advance(
    AssetStage stage,
    AssetPaintable paintable, {
    required int bytes,
    AssetTier tier = AssetTier.still,
  }) => advances.add((stage: stage, paintable: paintable, bytes: bytes));

  @override
  void fail(
    Object error, [
    StackTrace? stackTrace,
    AssetFailureKind kind = AssetFailureKind.transient,
  ]) => failures.add(kind);

  @override
  void cancelled() {}
}

void main() {
  group('over the fake binding', () {
    DecoderContract.run(() {
      final rig = _Rig();
      addTearDown(rig.close);
      return DecoderHarness(
        decoder: rig.decoder,
        valid: (part, spec) => _request(_fakeBytes, part: part, spec: spec),
        invalid: () => _request(_badBytes),
      );
    });
  });

  group('LottieDecoder', () {
    late _Rig rig;
    late _Report report;

    setUp(() {
      rig = _Rig();
      report = _Report();
      addTearDown(rig.close);
    });

    Future<void> settle() => pumpEventQueue();

    test('a full decode reports the still, then the animation', () async {
      rig.decoder.decode(_request(_fakeBytes), report);
      await settle();

      expect(report.advances.map((a) => a.stage), [
        AssetStage.firstFrame,
        AssetStage.full,
      ]);
      expect(report.advances.first.paintable.isAnimated, isFalse);
      expect(report.advances.last.paintable.isAnimated, isTrue);
      // 64 x 64 frame, plus four times the three encoded bytes.
      expect(report.advances.first.bytes, 64 * 64 * 4);
      expect(report.advances.last.bytes, 64 * 64 * 4 + 4 * 3);
    });

    test('draws frame 0 at the spec size, keeping the aspect ratio', () async {
      rig.binding.accept(
        Uint8List.fromList([7]),
        const LottieInfo(
          width: 200,
          height: 100,
          frameCount: 10,
          frameRate: 30,
          features: LottieFeatures.none,
        ),
      );

      rig.decoder.decode(
        _request(
          Uint8List.fromList([7]),
          spec: const AssetSpec(pixelWidth: 100, pixelHeight: 100),
        ),
        report,
      );
      await settle();

      expect(rig.uploaded.single.width, 100);
      expect(rig.uploaded.single.height, 50);
      expect(rig.uploaded.single.pixels, hasLength(100 * 50 * 4));
    });

    test('the animation frees its handle when it is disposed', () async {
      rig.decoder.decode(_request(_fakeBytes), report);
      await settle();
      expect(rig.binding.liveHandles, 1);

      report.advances.last.paintable.dispose();
      await settle();

      expect(rig.binding.liveHandles, 0);
    });

    test('a first-frame-only decode leaves no live handle', () async {
      rig.decoder.decode(
        _request(
          _fakeBytes,
          spec: const AssetSpec(
            pixelWidth: 64,
            pixelHeight: 64,
            variant: AssetVariant.firstFrame,
          ),
        ),
        report,
      );
      await settle();

      expect(report.advances.map((a) => a.stage), [AssetStage.firstFrame]);
      expect(rig.binding.liveHandles, 0);
    });

    test(
      'a spec above the largest size class ends with the still as full',
      () async {
        rig.decoder.decode(
          _request(
            _fakeBytes,
            spec: const AssetSpec(pixelWidth: 1024, pixelHeight: 1024),
          ),
          report,
        );
        await settle();

        expect(report.advances.map((a) => a.stage), [
          AssetStage.firstFrame,
          AssetStage.full,
        ]);
        expect(report.advances.every((a) => !a.paintable.isAnimated), isTrue);
        // Rendered at the cap, not at the spec.
        expect(rig.uploaded.single.width, 512);
        expect(report.advances.last.bytes, 512 * 512 * 4);
        expect(rig.binding.liveHandles, 0);
      },
    );

    test('cancelled before the load completes, it frees the handle', () async {
      final task = rig.decoder.decode(_request(_fakeBytes), report);
      task.cancel();
      await settle();

      expect(report.advances, isEmpty);
      expect(rig.binding.liveHandles, 0);
    });

    test(
      'cancelled while the frame uploads, it frees image and handle',
      () async {
        final upload = Completer<ui.Image>();
        final slow = _Rig(upload: (pixels, width, height) => upload.future);
        addTearDown(slow.close);
        final task = slow.decoder.decode(_request(_fakeBytes), report);
        await settle();
        expect(slow.binding.liveHandles, 1);

        task.cancel();
        final image = _image();
        upload.complete(image);
        await settle();

        expect(report.advances, isEmpty);
        expect(image.debugDisposed, isTrue);
        expect(slow.binding.liveHandles, 0);
      },
    );

    test('a rejected file fails permanently, holding nothing', () async {
      rig.binding.reject(_badBytes, LottieRejection.tooLarge);

      rig.decoder.decode(_request(_badBytes), report);
      await settle();

      expect(report.failures, [AssetFailureKind.permanent]);
      expect(report.advances, isEmpty);
      expect(rig.binding.liveHandles, 0);
    });

    test('a frame that does not render fails permanently', () async {
      rig.binding.renderFails = true;

      rig.decoder.decode(_request(_fakeBytes), report);
      await settle();

      expect(report.failures, [AssetFailureKind.permanent]);
      expect(report.advances, isEmpty);
      expect(rig.binding.liveHandles, 0);
    });

    test('an engine that throws fails permanently, never throws', () async {
      await rig.engine.close();

      expect(
        () => rig.decoder.decode(_request(_fakeBytes), report),
        returnsNormally,
      );
      await settle();

      expect(report.failures, [AssetFailureKind.permanent]);
    });

    test(
      'a thumbnail is an ordinary image, reported as a placeholder',
      () async {
        final image = _image(8);
        final thumbs = _Rig(decodeImage: (bytes) async => image);
        addTearDown(thumbs.close);

        thumbs.decoder.decode(
          _request(Uint8List.fromList([0xFF]), part: FetchPart.thumbnail),
          report,
        );
        await settle();

        expect(report.advances.map((a) => a.stage), [AssetStage.placeholder]);
        expect(report.advances.single.bytes, 8 * 8 * 4);
        expect(thumbs.binding.liveHandles, 0);
      },
    );

    test('a thumbnail that is not an image fails permanently', () async {
      final bad = _Rig(
        decodeImage: (bytes) async => throw const FormatException('no image'),
      );
      addTearDown(bad.close);

      bad.decoder.decode(
        _request(_badBytes, part: FetchPart.thumbnail),
        report,
      );
      await settle();

      expect(report.failures, [AssetFailureKind.permanent]);
      expect(report.advances, isEmpty);
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

/// A hand-authored 100x100, 30 fps, 60 frame animation: one rotating 60x60
/// square filled with 50% opaque orange. Not a corpus sticker.
const _fixture = '''
{"v":"5.5.2","fr":30,"ip":0,"op":60,"w":100,"h":100,"nm":"fixture","ddd":0,
"assets":[],
"layers":[{"ddd":0,"ind":1,"ty":4,"nm":"square","sr":1,
"ks":{"o":{"a":0,"k":100},
"r":{"a":1,"k":[{"t":0,"s":[0],"i":{"x":[0.5],"y":[1]},"o":{"x":[0.5],"y":[0]}},{"t":60,"s":[90]}]},
"p":{"a":0,"k":[50,50,0]},"a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]}},
"ao":0,
"shapes":[{"ty":"gr","it":[
{"ty":"rc","d":1,"s":{"a":0,"k":[60,60]},"p":{"a":0,"k":[0,0]},"r":{"a":0,"k":0}},
{"ty":"fl","c":{"a":0,"k":[1,0.5,0.25,1]},"o":{"a":0,"k":50},"r":1},
{"ty":"tr","p":{"a":0,"k":[0,0]},"a":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100}}
]}],"ip":0,"op":60,"st":0,"bm":0}]}''';

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
  _Rig({
    LottieEngine? engine,
    LottieImageDecoder? decodeImage,
    LottiePixelUploader? upload,
    FrameRenderer? renderer,
  }) : binding = FakeLottieBinding()..accept(_fakeBytes, _info) {
    this.engine = engine ?? InProcessLottieEngine(binding);
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    scheduler = LottieFrameScheduler(
      atlas: FrameAtlas<Object>(
        renderer: renderer ?? FakeFrameRenderer(),
        memory: ListFramePageMemory(pageSide: 1024),
        sizeClasses: const [64, 128, 256, 512],
        upload: (pixels, side) async => _image(),
      ),
      clock: clock,
      startTimer: ManualRetentionTimers().start,
    );
    decoder = LottieDecoder(
      engine: this.engine,
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
  late final LottieEngine engine;
  late final ManualPlaybackTickSource ticks;
  late final PlaybackClock clock;
  late final LottieFrameScheduler scheduler;
  late final LottieDecoder decoder;
  final List<({Uint8List pixels, int width, int height})> uploaded = [];

  /// Waits until [report] has an outcome, for engines that take real time.
  Future<void> settled(_Report report) async {
    while (report.advances.isEmpty && report.failures.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  void close() {
    scheduler.dispose();
    unawaited(engine.close());
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

    test(
      'the decode and the paintable render a non-square file at one size',
      () async {
        final sizes = _SizeRecordingRenderer();
        final wide = _Rig(renderer: sizes);
        addTearDown(wide.close);
        wide.binding.accept(
          Uint8List.fromList([7]),
          const LottieInfo(
            width: 300,
            height: 100,
            frameCount: 10,
            frameRate: 30,
            features: LottieFeatures.none,
          ),
        );
        wide.decoder.decode(
          _request(
            Uint8List.fromList([7]),
            spec: const AssetSpec(pixelWidth: 64, pixelHeight: 64),
          ),
          report,
        );
        await settle();

        final paintable = report.advances.last.paintable;
        final recorder = ui.PictureRecorder();
        paintable.paint(
          ui.Canvas(recorder),
          const ui.Rect.fromLTWH(0, 0, 64, 64),
          const AssetPaintContext(
            time: Duration.zero,
            loop: true,
            restFrame: AssetRestFrame.first,
            animate: true,
            opacity: 1,
          ),
        );
        recorder.endRecording().dispose();
        wide.ticks.tick(const Duration(milliseconds: 16));
        await settle();

        final first = wide.uploaded.single;
        expect(sizes.sizes, [(first.width, first.height)]);
        expect((first.width, first.height), (64, 21));
      },
    );

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

    test('a closed engine at handle disposal is not reported', () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      final closing = _Rig(engine: _DisposeThrows(LottieEngineClosed()));
      addTearDown(closing.close);
      closing.decoder.decode(_request(_fakeBytes), report);
      await settle();

      report.advances.last.paintable.dispose();
      await settle();

      expect(reported, isEmpty);
    });

    test('any other failure at handle disposal is reported', () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      final failing = _Rig(engine: _DisposeThrows(StateError('not a close')));
      addTearDown(failing.close);
      failing.decoder.decode(_request(_fakeBytes), report);
      await settle();

      report.advances.last.paintable.dispose();
      await settle();

      expect(reported.single.exception, isA<StateError>());
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

  final native = NativeLottieBinding.probe().isAvailable;
  group(
    'over the native library in the render isolate',
    () {
      final fixture = Uint8List.fromList(utf8.encode(_fixture));

      DecoderContract.run(() {
        final rig = _Rig(engine: _DeferredEngine(IsolateLottieEngine.spawn));
        addTearDown(rig.close);
        return DecoderHarness(
          decoder: rig.decoder,
          valid: (part, spec) => _request(fixture, part: part, spec: spec),
          invalid: () =>
              _request(Uint8List.fromList(utf8.encode('not a lottie file'))),
        );
      });

      test('hands over the first frame as premultiplied RGBA', () async {
        final rig = _Rig(engine: _DeferredEngine(IsolateLottieEngine.spawn));
        addTearDown(rig.close);
        final report = _Report();

        rig.decoder.decode(
          _request(
            fixture,
            spec: const AssetSpec(
              pixelWidth: 100,
              pixelHeight: 100,
              variant: AssetVariant.firstFrame,
            ),
          ),
          report,
        );
        await rig.settled(report);

        final upload = rig.uploaded.single;
        expect((upload.width, upload.height), (100, 100));
        const center = (50 * 100 + 50) * 4;
        final [r, g, b, a] = upload.pixels.sublist(center, center + 4);
        // 50% orange (1, 0.5, 0.25): colour channels sit under the alpha.
        expect(a, inInclusiveRange(120, 135));
        expect(r, inInclusiveRange(120, 135));
        expect(g, inInclusiveRange(58, 70));
        expect(b, inInclusiveRange(28, 36));
        expect(
          [r, g, b].every((c) => c <= a),
          isTrue,
          reason: 'premultiplied: no channel above alpha',
        );
      });
    },
    skip: native
        ? false
        : 'The native library is absent or speaks another ABI version: the '
              'build hook compiles it with cargo on macOS only (rustup.rs).',
  );
}

/// An engine that spawns its render isolate on first use, so a contract
/// harness, which is built synchronously, can hold it.
final class _DeferredEngine implements LottieEngine {
  _DeferredEngine(this._open);

  final Future<LottieEngine> Function() _open;
  late final Future<LottieEngine> _engine = _open();

  @override
  Future<LottieLoadResult> load(Uint8List bytes) async =>
      (await _engine).load(bytes);

  @override
  Future<List<LottieRenderStatus>> renderBatch(
    List<LottieEngineJob> jobs,
  ) async => (await _engine).renderBatch(jobs);

  @override
  Future<void> dispose(LottieHandle handle) async =>
      (await _engine).dispose(handle);

  @override
  Future<void> close() async => (await _engine).close();
}

/// An in-process engine whose handle disposal throws [error].
final class _DisposeThrows implements LottieEngine {
  _DisposeThrows(this.error);

  final Object error;
  final _inner = InProcessLottieEngine(
    FakeLottieBinding()..accept(_fakeBytes, _info),
  );

  @override
  Future<LottieLoadResult> load(Uint8List bytes) => _inner.load(bytes);

  @override
  Future<List<LottieRenderStatus>> renderBatch(List<LottieEngineJob> jobs) =>
      _inner.renderBatch(jobs);

  @override
  Future<void> dispose(LottieHandle handle) => Future.error(error);

  @override
  Future<void> close() => _inner.close();
}

/// A renderer that notes the size of every job and renders nothing.
final class _SizeRecordingRenderer implements FrameRenderer {
  final List<(int, int)> sizes = [];

  @override
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory) async {
    sizes.addAll([for (final job in jobs) (job.width, job.height)]);
    return [for (var i = 0; i < jobs.length; i++) i];
  }
}

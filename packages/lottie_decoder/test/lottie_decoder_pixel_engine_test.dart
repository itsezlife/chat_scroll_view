import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_decoder/src/decoder/read_file_bytes_stub.dart' as web;
import 'package:lottie_decoder/testing.dart';
import 'package:lottie_native/lottie_native.dart';

/// The decoder over an engine that can only return pixels, which is all the
/// web has: no slot method exists to fall back on.
void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);
  const info = LottieInfo(
    width: 64,
    height: 64,
    frameCount: 10,
    frameRate: 30,
    features: LottieFeatures.none,
  );

  late FakePixelLottieEngine engine;
  late ListFramePageMemory memory;
  late _RecordingRenderer renderer;
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late LottieFrameScheduler scheduler;
  late LottieDecoder decoder;
  late List<({Uint8List pixels, int width, int height})> uploaded;

  setUp(() {
    engine = FakePixelLottieEngine()..accept(bytes, info);
    memory = ListFramePageMemory();
    renderer = _RecordingRenderer(PixelCopyFrameRenderer(engine));
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    uploaded = [];
    scheduler = LottieFrameScheduler(
      atlas: FrameAtlas<Object>(
        renderer: renderer,
        memory: memory,
        sizeClasses: const [64, 128, 256, 512],
        upload: (pixels, side) async => _image(),
      ),
      clock: clock,
      startTimer: ManualRetentionTimers().start,
    );
    decoder = LottieDecoder(
      engine: engine,
      scheduler: scheduler,
      uploadPixels: (pixels, width, height) async {
        uploaded.add((pixels: pixels, width: width, height: height));
        return _image();
      },
      decodeImage: (bytes) async => _image(),
    );
  });

  tearDown(() async {
    scheduler.dispose();
    await engine.close();
    clock.dispose();
  });

  test('a full decode reports the still, then the animation', () async {
    final report = _Report();

    decoder.decode(_request(bytes), report);
    await pumpEventQueue();

    expect(report.advances.map((a) => a.stage), [
      AssetStage.firstFrame,
      AssetStage.full,
    ]);
    expect(report.advances.last.paintable.isAnimated, isTrue);
    expect(report.failures, isEmpty);
  });

  test('the first frame is the engine\'s frame 0, as drawn', () async {
    decoder.decode(_request(bytes), _Report());
    await pumpEventQueue();

    final frame = uploaded.single;
    expect((frame.width, frame.height), (64, 64));
    expect(frame.pixels, hasLength(64 * 64 * 4));
    // Column 3, row 2 of frame 0: the fake's pixel, by its own literal rule.
    const at = (2 * 64 + 3) * 4;
    expect(frame.pixels.sublist(at, at + 4), [3, 2, 0, 255]);
  });

  test('the animation plays through the scheduler, PixelCopy and the atlas '
      'into page memory', () async {
    final report = _Report();
    decoder.decode(_request(bytes), report);
    await pumpEventQueue();

    final recorder = ui.PictureRecorder();
    report.advances.last.paintable.paint(
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
    ticks.tick(const Duration(milliseconds: 16));
    await pumpEventQueue();

    expect(renderer.jobs, isNotEmpty);
    final job = renderer.jobs.last;
    final page = memory.page(job.slot.pageIndex, side: job.slot.pageSide);
    final at =
        (job.slot.rect.top.toInt() * job.slot.pageSide +
            job.slot.rect.left.toInt()) *
        4;
    // The slot's top left pixel is the engine's, carrying the job's frame.
    expect(page.sublist(at, at + 4), [0, 0, job.frame % 256, 255]);
  });

  test('a file on disk is read and decoded like bytes', () async {
    final dir = Directory.systemTemp.createTempSync('lottie_decoder_file_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}sticker.json')
      ..writeAsBytesSync(bytes);
    final report = _Report();

    decoder.decode(
      _request(bytes, content: FetchedContent.file(file.path)),
      report,
    );
    await pumpEventQueue();

    expect(report.advances.map((a) => a.stage), [
      AssetStage.firstFrame,
      AssetStage.full,
    ]);
  });

  test('on the web a file is an UnsupportedError, not a read', () async {
    await expectLater(web.readFileBytes('a.json'), throwsUnsupportedError);
  });

  test('a rejected file fails the decode and frees nothing twice', () async {
    final report = _Report();

    decoder.decode(_request(Uint8List.fromList([9])), report);
    await pumpEventQueue();

    expect(report.failures, [AssetFailureKind.permanent]);
    expect(engine.liveHandles, 0);
  });

  test('a decode that ends without a paintable frees its handle', () async {
    final report = _Report();

    decoder.decode(
      _request(bytes, spec: const AssetSpec(pixelWidth: 600, pixelHeight: 600)),
      report,
    );
    await pumpEventQueue();

    // Above the largest size class the still is the final picture.
    expect(report.advances.map((a) => a.stage), [
      AssetStage.firstFrame,
      AssetStage.full,
    ]);
    expect(engine.liveHandles, 0);
  });
}

ui.Image _image() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
  picture.dispose();
  return image;
}

DecodeRequest _request(
  Uint8List bytes, {
  AssetSpec spec = const AssetSpec(pixelWidth: 64, pixelHeight: 64),
  FetchedContent? content,
}) => DecodeRequest(
  descriptor: const ContentDescriptor(
    key: ContentKey.document('fixture'),
    semanticKind: SemanticKind.customEmoji,
    mediaForm: MediaForm.vectorAnimation,
    animated: true,
  ),
  spec: spec,
  part: FetchPart.content,
  content: content ?? FetchedContent.bytes(bytes),
);

/// Forwards to [_inner] and keeps every job it was given.
final class _RecordingRenderer implements FrameRenderer {
  _RecordingRenderer(this._inner);

  final FrameRenderer _inner;
  final List<FrameJob> jobs = [];

  @override
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory) {
    this.jobs.addAll(jobs);
    return _inner.render(jobs, memory);
  }
}

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

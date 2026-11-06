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
}

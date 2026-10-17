import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_decoder/image_decoder.dart';

// 16 x 16, three frames: red 40 ms, blue 60 ms, green 80 ms.
final Uint8List _threeFrames = File(
  'test/fixtures/three_frames.gif',
).readAsBytesSync();

// 32 x 16, one yellow frame.
final Uint8List _still = File('test/fixtures/still.png').readAsBytesSync();

const ContentDescriptor _descriptor = ContentDescriptor(
  key: ContentKey.document('fixture'),
  semanticKind: SemanticKind.customEmoji,
  mediaForm: MediaForm.animatedImage,
  animated: true,
);

DecodeRequest _request(
  Uint8List bytes, {
  AssetSpec spec = const AssetSpec(pixelWidth: 64, pixelHeight: 64),
  FetchPart part = FetchPart.content,
}) => DecodeRequest(
  descriptor: _descriptor,
  spec: spec,
  part: part,
  content: FetchedContent.bytes(bytes),
);

/// Collects what one decode reports.
final class _Progress implements AssetProgress {
  final List<
    ({AssetStage stage, AssetPaintable paintable, int bytes, AssetTier tier})
  >
  advances = [];
  final Completer<void> _ended = Completer();
  Object? error;

  Future<void> get ended => _ended.future;

  @override
  void advance(
    AssetStage stage,
    AssetPaintable paintable, {
    required int bytes,
    AssetTier tier = AssetTier.still,
  }) {
    advances.add((
      stage: stage,
      paintable: paintable,
      bytes: bytes,
      tier: tier,
    ));
    if (!_ended.isCompleted) _ended.complete();
  }

  @override
  void fail(
    Object error, [
    StackTrace? stackTrace,
    AssetFailureKind kind = AssetFailureKind.transient,
  ]) {
    this.error = error;
    if (!_ended.isCompleted) _ended.complete();
  }

  @override
  void cancelled() {}
}

/// A progress that takes the paintable, then throws, as a buggy one would.
final class _ThrowingProgress implements AssetProgress {
  AssetPaintable? paintable;
  final List<Object> failures = [];

  @override
  void advance(
    AssetStage stage,
    AssetPaintable paintable, {
    required int bytes,
    AssetTier tier = AssetTier.still,
  }) {
    this.paintable = paintable;
    throw StateError('the progress broke');
  }

  @override
  void fail(
    Object error, [
    StackTrace? stackTrace,
    AssetFailureKind kind = AssetFailureKind.transient,
  ]) => failures.add(error);

  @override
  void cancelled() {}
}

Future<_Progress> _decode(DecodeRequest request) async {
  final progress = _Progress();
  const ImageCodecDecoder().decode(request, progress);
  await progress.ended.timeout(const Duration(seconds: 10));
  return progress;
}

/// The colour at the centre of [paintable] painted at [time], by a surface
/// that animates unless [animate] is false.
Future<ui.Color> _centreAt(
  AssetPaintable paintable,
  Duration time, {
  bool animate = true,
}) async {
  final recorder = ui.PictureRecorder();
  paintable.paint(
    ui.Canvas(recorder),
    const ui.Rect.fromLTWH(0, 0, 16, 16),
    AssetPaintContext(time: time, animate: animate),
  );
  final image = await recorder.endRecording().toImage(16, 16);
  final pixels = (await image.toByteData())!;
  image.dispose();
  const offset = (8 * 16 + 8) * 4;
  return ui.Color.fromARGB(
    pixels.getUint8(offset + 3),
    pixels.getUint8(offset),
    pixels.getUint8(offset + 1),
    pixels.getUint8(offset + 2),
  );
}

/// Paints [paintable] at [time] after giving its decode ahead a moment to
/// land, and returns the centre colour.
Future<ui.Color> _settledAt(
  AssetPaintable paintable,
  Duration time, {
  bool animate = true,
}) async {
  await _centreAt(paintable, time, animate: animate);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return _centreAt(paintable, time, animate: animate);
}

const ui.Color _red = ui.Color(0xFFFF0000);
const ui.Color _blue = ui.Color(0xFF0000FF);
const ui.Color _green = ui.Color(0xFF00FF00);

void main() {
  DecoderContract.run(
    () => DecoderHarness(
      decoder: const ImageCodecDecoder(),
      valid: (part, spec) => _request(_threeFrames, spec: spec, part: part),
      invalid: () => _request(Uint8List.fromList([1, 2, 3, 4])),
    ),
  );

  group('ImageCodecDecoder', () {
    test('reports a frame sequence as one playing, animated entry', () async {
      final progress = await _decode(_request(_threeFrames));

      final advance = progress.advances.single;
      expect(advance.stage, AssetStage.full);
      expect(advance.tier, AssetTier.animated);
      expect(advance.paintable.isAnimated, isTrue);
      // The frame shown and the one decoded ahead, at 16 x 16, and the
      // encoded data the codec keeps to decode them from.
      expect(advance.bytes, 2 * 16 * 16 * 4 + _threeFrames.length);
      advance.paintable.dispose();
    });

    test('reports one frame as a still in the still tier', () async {
      final progress = await _decode(_request(_still));

      final advance = progress.advances.single;
      expect(advance.stage, AssetStage.full);
      expect(advance.tier, AssetTier.still);
      expect(advance.paintable.isAnimated, isFalse);
      expect(advance.bytes, 32 * 16 * 4);
      advance.paintable.dispose();
    });

    test('decodes no larger than the spec, keeping the aspect ratio', () async {
      final progress = await _decode(
        _request(_still, spec: const AssetSpec(pixelWidth: 8, pixelHeight: 8)),
      );

      // 32 x 16 fitted into 8 x 8 is 8 x 4.
      expect(progress.advances.single.bytes, 8 * 4 * 4);
      progress.advances.single.paintable.dispose();
    });

    test('leaves what it handed over alone when the progress throws', () async {
      final progress = _ThrowingProgress();
      final errors = <Object>[];
      final reported = Completer<void>();

      runZonedGuarded(
        () =>
            const ImageCodecDecoder().decode(_request(_threeFrames), progress),
        (error, _) {
          errors.add(error);
          reported.complete();
        },
      );
      await reported.future.timeout(const Duration(seconds: 10));

      // The progress's own error, not a dispose of the frame it was given.
      expect(errors.single, isA<StateError>());
      expect(progress.failures, isEmpty);
      // Still drawable: the decoder did not dispose it.
      expect(await _centreAt(progress.paintable!, Duration.zero), _red);
      progress.paintable!.dispose();
    });

    test('reports nothing for a decode cancelled before it ends', () async {
      final progress = _Progress();
      const ImageCodecDecoder()
          .decode(_request(_threeFrames), progress)
          .cancel();

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(progress.advances, isEmpty);
      expect(progress.error, isNull);
    });
  });

  group('PlayingImagePaintable', () {
    late AssetPaintable paintable;

    setUp(() async {
      paintable = (await _decode(
        _request(_threeFrames),
      )).advances.single.paintable;
    });

    tearDown(() => paintable.dispose());

    test('shows each frame for its own duration', () async {
      // The clock is at 1 s when the image is first seen.
      const start = Duration(seconds: 1);
      expect(await _settledAt(paintable, start), _red);
      expect(
        await _settledAt(paintable, start + const Duration(milliseconds: 39)),
        _red,
      );
      expect(
        await _settledAt(paintable, start + const Duration(milliseconds: 40)),
        _blue,
      );
      expect(
        await _settledAt(paintable, start + const Duration(milliseconds: 99)),
        _blue,
      );
      expect(
        await _settledAt(paintable, start + const Duration(milliseconds: 100)),
        _green,
      );
      // Looping: green lasts 80 ms, then red again.
      expect(
        await _settledAt(paintable, start + const Duration(milliseconds: 180)),
        _red,
      );
    });

    test(
      'restarts its timing after a jump instead of racing to catch up',
      () async {
        expect(await _settledAt(paintable, Duration.zero), _red);

        // Paused for ten seconds: one step to the next frame, not a burst.
        const resumed = Duration(seconds: 10);
        expect(await _settledAt(paintable, resumed), _blue);
        expect(
          await _settledAt(
            paintable,
            resumed + const Duration(milliseconds: 59),
          ),
          _blue,
        );
        expect(
          await _settledAt(
            paintable,
            resumed + const Duration(milliseconds: 60),
          ),
          _green,
        );
      },
    );

    test('a surface that does not animate neither steps it nor starts its '
        'first frame, sharing it with one that plays', () async {
      // The still surface paints first, long before the playing one.
      expect(await _settledAt(paintable, Duration.zero, animate: false), _red);
      expect(
        await _settledAt(paintable, const Duration(seconds: 5), animate: false),
        _red,
      );

      // The first frame lasts its full 40 ms from when the playing surface
      // first sees it.
      const seen = Duration(seconds: 10);
      expect(await _settledAt(paintable, seen), _red);
      expect(
        await _settledAt(paintable, seen + const Duration(milliseconds: 39)),
        _red,
      );
      // A still paint at its own, older time leaves the timing alone.
      expect(
        await _settledAt(paintable, Duration.zero, animate: false),
        _red,
      );
      expect(
        await _settledAt(paintable, seen + const Duration(milliseconds: 40)),
        _blue,
      );
    });

    test('drops a frame that lands after it is disposed', () async {
      final own = (await _decode(
        _request(_threeFrames),
      )).advances.single.paintable;
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      // The paint starts decoding the next frame; dispose does not wait.
      await _centreAt(own, Duration.zero);
      own.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(errors, isEmpty);
    });

    test(
      'keeps playing when the clock starts again from an earlier time',
      () async {
        expect(await _settledAt(paintable, const Duration(seconds: 10)), _red);

        // A new clock: its time is behind the one the frame went up at.
        expect(await _settledAt(paintable, Duration.zero), _red);
        expect(
          await _settledAt(paintable, const Duration(milliseconds: 40)),
          _blue,
        );
      },
    );
  });
}

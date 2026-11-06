import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/src/engine/video_engine.dart';
import 'package:video_native/video_native.dart';

/// What a [VideoEngineContract] run needs besides the engine.
final class VideoEngineHarness {
  /// Creates a harness whose engines come from [open].
  VideoEngineHarness({
    required this.open,
    required this.validBytes,
    required this.expectedInfo,
    required this.frameCount,
    required this.malformedBytes,
    this.width = 16,
    this.height = 12,
  });

  /// Opens a fresh engine over an available binding; the contract closes it.
  final Future<VideoEngine> Function() open;

  /// A file the engine opens.
  final Uint8List validBytes;

  /// What [validBytes] declares.
  final VideoInfo expectedInfo;

  /// How many frames [validBytes] holds.
  final int frameCount;

  /// Bytes the engine refuses (not a video).
  final Uint8List malformedBytes;

  /// The target width the contract opens at.
  final int width;

  /// The target height the contract opens at.
  final int height;
}

/// The behaviour every [VideoEngine] shares: the in-process and isolate
/// engines on the fake and the real binding, and the pure-Dart fake.
abstract final class VideoEngineContract {
  /// Registers the contract's tests; [create] builds a fresh harness for
  /// each.
  static void run(VideoEngineHarness Function() create) {
    group('VideoEngine contract', () {
      late VideoEngineHarness harness;
      late VideoEngine engine;

      setUp(() async {
        harness = create();
        engine = await harness.open();
      });
      tearDown(() => engine.dispose());

      Future<VideoClip> open() async {
        final result = await engine.open(
          harness.validBytes,
          width: harness.width,
          height: harness.height,
        );
        expect(result, isA<VideoClipOpened>());
        return (result as VideoClipOpened).clip;
      }

      test(
        'valid bytes open as a clip that carries the declared info',
        () async {
          final clip = await open();

          expect(clip.info, harness.expectedInfo);
          expect(clip.width, harness.width);
          expect(clip.height, harness.height);
        },
      );

      test(
        'bytes that are not a video are rejected with the binding reason',
        () async {
          final result = await engine.open(
            harness.malformedBytes,
            width: harness.width,
            height: harness.height,
          );

          expect(result, isA<VideoClipRejected>());
          expect(
            (result as VideoClipRejected).reason,
            isNot(VideoRejection.internal),
          );
        },
      );

      test('a zero target size is rejected as a bad size', () async {
        final result = await engine.open(
          harness.validBytes,
          width: 0,
          height: harness.height,
        );

        expect(
          result,
          isA<VideoClipRejected>().having(
            (r) => r.reason,
            'reason',
            VideoRejection.badSize,
          ),
        );
      });

      test('frames come in order into the destination, then the end, which '
          'stays', () async {
        final clip = await open();
        final destination = Uint8List(clip.frameBytes);

        final times = <int>[];
        for (var i = 0; i < harness.frameCount; i++) {
          destination.fillRange(0, destination.length, 0);
          final result = await engine.nextFrame(clip, destination: destination);
          expect(result.status, VideoFrameStatus.frame, reason: 'frame $i');
          expect(destination.any((byte) => byte != 0), isTrue, reason: '$i');
          times.add(result.ptsMs);
        }

        expect(times, orderedEquals([...times]..sort()));
        expect(times.first, 0);
        for (var i = 0; i < 2; i++) {
          final end = await engine.nextFrame(clip, destination: destination);
          expect(end.status, VideoFrameStatus.endOfStream);
        }
      });

      test('the end leaves the destination alone', () async {
        final clip = await open();
        final destination = Uint8List(clip.frameBytes);
        for (var i = 0; i < harness.frameCount; i++) {
          await engine.nextFrame(clip, destination: destination);
        }
        destination.fillRange(0, destination.length, 0x7f);

        await engine.nextFrame(clip, destination: destination);

        expect(destination, everyElement(0x7f));
      });

      test('rewind restarts the clip from its first frame', () async {
        final clip = await open();
        final destination = Uint8List(clip.frameBytes);
        final first = await engine.nextFrame(clip, destination: destination);
        final firstPixels = Uint8List.fromList(destination);
        while ((await engine.nextFrame(
              clip,
              destination: destination,
            )).status ==
            VideoFrameStatus.frame) {}

        expect(await engine.rewind(clip), isTrue);

        final again = await engine.nextFrame(clip, destination: destination);
        expect(again, first);
        expect(destination, orderedEquals(firstPixels));
      });

      test('a destination that is too short is a bad size and costs the clip '
          'no frame', () async {
        final clip = await open();

        final refused = await engine.nextFrame(
          clip,
          destination: Uint8List(clip.frameBytes - 1),
        );
        final first = await engine.nextFrame(
          clip,
          destination: Uint8List(clip.frameBytes),
        );

        expect(refused.status, VideoFrameStatus.badSize);
        expect(first.status, VideoFrameStatus.frame);
        expect(first.ptsMs, 0);
      });

      test(
        'a destination longer than a frame is written from its start',
        () async {
          final clip = await open();
          final destination = Uint8List(clip.frameBytes + 8)
            ..fillRange(clip.frameBytes, clip.frameBytes + 8, 0x7f);

          await engine.nextFrame(clip, destination: destination);

          expect(destination.sublist(clip.frameBytes), everyElement(0x7f));
        },
      );

      test('a clip the engine never issued is a bad argument', () async {
        const unknown = VideoClip(
          id: 987654,
          info: VideoInfo(
            width: 1,
            height: 1,
            duration: null,
            frameRate: 0,
            hasAlpha: false,
          ),
          width: 1,
          height: 1,
        );

        final result = await engine.nextFrame(
          unknown,
          destination: Uint8List(4),
        );

        expect(result.status, VideoFrameStatus.badArgument);
        expect(await engine.rewind(unknown), isFalse);
      });

      test('a closed clip is refused; close is idempotent', () async {
        final clip = await open();

        await engine.close(clip);
        await engine.close(clip);

        final result = await engine.nextFrame(
          clip,
          destination: Uint8List(clip.frameBytes),
        );
        expect(result.status, VideoFrameStatus.badArgument);
        expect(await engine.rewind(clip), isFalse);
      });

      test('clips are independent', () async {
        final a = await open();
        final b = await open();
        final destination = Uint8List(a.frameBytes);
        await engine.nextFrame(a, destination: destination);
        await engine.nextFrame(a, destination: destination);

        final first = await engine.nextFrame(b, destination: destination);
        expect(first.ptsMs, 0, reason: 'b is still at its first frame');
        await engine.close(a);
        final second = await engine.nextFrame(b, destination: destination);
        expect(second.status, VideoFrameStatus.frame);
      });

      test('requests made without awaiting are served in order', () async {
        final clip = await open();
        final destinations = [
          for (var i = 0; i < 3; i++) Uint8List(clip.frameBytes),
        ];

        final results = await Future.wait([
          for (final destination in destinations)
            engine.nextFrame(clip, destination: destination),
        ]);

        final times = [for (final result in results) result.ptsMs];
        expect(times, orderedEquals([...times]..sort()));
        expect(times.toSet(), hasLength(3));
      });

      test('after dispose open, nextFrame and rewind throw VideoEngineClosed '
          'and close is harmless', () async {
        final clip = await open();

        await engine.dispose();
        await engine.dispose();

        await engine.close(clip);
        await expectLater(
          engine.open(
            harness.validBytes,
            width: harness.width,
            height: harness.height,
          ),
          throwsA(isA<VideoEngineClosed>()),
        );
        await expectLater(
          engine.nextFrame(clip, destination: Uint8List(clip.frameBytes)),
          throwsA(isA<VideoEngineClosed>()),
        );
        await expectLater(
          engine.rewind(clip),
          throwsA(isA<VideoEngineClosed>()),
        );
      });
    });
  }
}

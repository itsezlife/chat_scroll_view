import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_native/src/video_availability.dart';
import 'package:video_native/src/video_binding.dart';
import 'package:video_native/src/video_frame_result.dart';
import 'package:video_native/src/video_handle.dart';
import 'package:video_native/src/video_open_result.dart';

/// What a [VideoBindingContract] run needs besides the binding.
final class VideoBindingHarness {
  /// Creates a harness around [binding].
  VideoBindingHarness({
    required this.binding,
    required this.validBytes,
    required this.expectedInfo,
    required this.frameCount,
    required this.malformedBytes,
    this.width = 16,
    this.height = 12,
    this.unavailable,
  });

  /// The binding under test; it must be available.
  final VideoBinding binding;

  /// A file the binding opens.
  final Uint8List validBytes;

  /// What [validBytes] declares.
  final VideoInfo expectedInfo;

  /// How many frames [validBytes] holds.
  final int frameCount;

  /// Bytes the binding refuses (not a video).
  final Uint8List malformedBytes;

  /// The target width the contract opens at.
  final int width;

  /// The target height the contract opens at.
  final int height;

  /// Builds a binding that is not available, if the implementation can; its
  /// case is skipped otherwise.
  final VideoBinding Function()? unavailable;
}

/// The behaviour every [VideoBinding] shares, run over its fake and over the
/// native binding alike.
abstract final class VideoBindingContract {
  /// Registers the contract's tests; [create] builds a fresh harness for
  /// each.
  static void run(VideoBindingHarness Function() create) {
    group('VideoBinding contract', () {
      late VideoBindingHarness harness;
      late Pointer<Uint8> target;
      late int stride;

      setUp(() {
        harness = create();
        stride = harness.width * 4 + 8;
        target = calloc<Uint8>(stride * harness.height);
      });
      tearDown(() => calloc.free(target));

      VideoHandle open() {
        final result = harness.binding.open(
          harness.validBytes,
          width: harness.width,
          height: harness.height,
        );
        expect(result, isA<VideoOpened>());
        return (result as VideoOpened).handle;
      }

      VideoFrameResult next(VideoHandle handle) => harness.binding.nextFrame(
        handle,
        target: target,
        strideBytes: stride,
      );

      test('the probe says available, and stays so', () {
        expect(harness.binding.isAvailable, isTrue);
        expect(harness.binding.availability, VideoAvailability.available);
        open();
        expect(harness.binding.availability, VideoAvailability.available);
      });

      test('valid bytes open with the expected info', () {
        final result = harness.binding.open(
          harness.validBytes,
          width: harness.width,
          height: harness.height,
        );

        expect(result, isA<VideoOpened>());
        expect((result as VideoOpened).info, harness.expectedInfo);
      });

      test('bytes that are not a video are rejected, never thrown on', () {
        final result = harness.binding.open(
          harness.malformedBytes,
          width: harness.width,
          height: harness.height,
        );

        expect(result, isA<VideoRejected>());
        expect(
          (result as VideoRejected).reason,
          isNot(VideoRejection.internal),
        );
      });

      test('a zero target size is a bad size', () {
        final result = harness.binding.open(
          harness.validBytes,
          width: 0,
          height: harness.height,
        );

        expect(
          result,
          isA<VideoRejected>().having(
            (r) => r.reason,
            'reason',
            VideoRejection.badSize,
          ),
        );
      });

      test('frames come in order, then the end of the stream, which stays', () {
        final handle = open();

        final times = <int>[];
        for (var i = 0; i < harness.frameCount; i++) {
          final result = next(handle);
          expect(result.status, VideoFrameStatus.frame, reason: 'frame $i');
          times.add(result.ptsMs);
        }

        expect(times, orderedEquals([...times]..sort()));
        expect(times.first, 0);
        expect(next(handle).status, VideoFrameStatus.endOfStream);
        expect(next(handle).status, VideoFrameStatus.endOfStream);
      });

      test('rewind restarts the stream from its first frame', () {
        final handle = open();
        final first = next(handle);
        final firstPixels = Uint8List.fromList(
          target.asTypedList(stride * harness.height),
        );
        while (next(handle).status == VideoFrameStatus.frame) {}

        expect(harness.binding.rewind(handle), isTrue);

        final again = next(handle);
        expect(again, first);
        expect(
          target.asTypedList(stride * harness.height),
          orderedEquals(firstPixels),
        );
      });

      test('a frame leaves the stride padding of its rows alone', () {
        final handle = open();
        target
            .asTypedList(stride * harness.height)
            .fillRange(0, stride * harness.height, 0x7f);

        next(handle);

        final bytes = target.asTypedList(stride * harness.height);
        for (var y = 0; y < harness.height; y++) {
          expect(
            bytes.sublist(y * stride + harness.width * 4, (y + 1) * stride),
            everyElement(0x7f),
            reason: 'row $y',
          );
        }
      });

      test('a stride under the row width is a bad size', () {
        final handle = open();

        final result = harness.binding.nextFrame(
          handle,
          target: target,
          strideBytes: harness.width * 4 - 1,
        );

        expect(result.status, VideoFrameStatus.badSize);
      });

      test('an unknown handle is a bad argument, and rewind refuses it', () {
        const unknown = VideoHandle(987654);

        expect(next(unknown).status, VideoFrameStatus.badArgument);
        expect(harness.binding.rewind(unknown), isFalse);
      });

      test('a disposed handle is refused; dispose is idempotent', () {
        final handle = open();

        harness.binding
          ..dispose(handle)
          ..dispose(handle);

        expect(next(handle).status, VideoFrameStatus.badArgument);
        expect(harness.binding.rewind(handle), isFalse);
      });

      test('handles are independent', () {
        final a = open();
        final b = open();
        next(a);
        next(a);

        expect(next(b).ptsMs, 0, reason: 'b is still at its first frame');
        harness.binding.dispose(a);
        expect(next(b).status, VideoFrameStatus.frame);
      });

      test(
        'close retires the binding: open throws, dispose stays harmless',
        () {
          final handle = open();

          harness.binding
            ..close()
            ..close()
            ..dispose(handle);

          expect(
            () => harness.binding.open(
              harness.validBytes,
              width: harness.width,
              height: harness.height,
            ),
            throwsStateError,
          );
        },
      );

      test('an unavailable binding throws StateError from open', () {
        final factory = harness.unavailable;
        if (factory == null) {
          markTestSkipped('this implementation cannot be made unavailable');
          return;
        }
        final binding = factory();

        expect(binding.isAvailable, isFalse);
        expect(
          () => binding.open(
            harness.validBytes,
            width: harness.width,
            height: harness.height,
          ),
          throwsStateError,
        );
      });
    });
  }
}

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_native/video_native.dart';

// ignore: always_use_package_imports
import 'support/fixtures.dart';

void main() {
  final binding = NativeVideoBinding.probe();

  group('NativeVideoBinding.probe', () {
    test('finds the built library and its ABI version', () {
      expect(binding.availability, VideoAvailability.available);
    });
  });

  group('open', skip: nativeSkipReason(binding), () {
    test('describes each fixture as its generator made it', () {
      for (final fixture in fixtures) {
        final result = binding.open(fixture.bytes, width: 32, height: 24);

        expect(result, isA<VideoOpened>(), reason: fixture.file);
        final info = (result as VideoOpened).info;
        expect(info.width, fixture.width, reason: fixture.file);
        expect(info.height, fixture.height, reason: fixture.file);
        expect(info.frameRate, fixture.frameRate, reason: fixture.file);
        expect(info.hasAlpha, fixture.hasAlpha, reason: fixture.file);
        // 60 frames at 30 fps, 30 at 30, 10 at 10: one or two seconds.
        final seconds = fixture.frames / fixture.frameRate;
        expect(
          info.duration!.inMilliseconds,
          closeTo(seconds * 1000, 100),
          reason: fixture.file,
        );
        binding.dispose(result.handle);
      }
    });
  });

  group('nextFrame', skip: nativeSkipReason(binding), () {
    test('yields every frame of each fixture, then the end of the stream', () {
      for (final fixture in fixtures) {
        final decoded = _decodeAll(binding, fixture, width: 32, height: 24);

        expect(decoded.frames.length, fixture.frames, reason: fixture.file);
        expect(decoded.afterEnd, VideoFrameStatus.endOfStream);
        final times = [for (final f in decoded.frames) f.ptsMs];
        expect(times.first, 0, reason: fixture.file);
        expect(times, orderedEquals([...times]..sort()), reason: fixture.file);
        // One frame period apart, give or take rounding to milliseconds.
        final period = 1000 / fixture.frameRate;
        expect(
          times.last,
          closeTo(period * (fixture.frames - 1), 2 * fixture.frames),
          reason: fixture.file,
        );
      }
    });
  });

  group('pixels', skip: nativeSkipReason(binding), () {
    test('are premultiplied BGRA, and only the webm has alpha', () {
      final withAlpha = _decodeAll(binding, webm, width: 64, height: 64);
      final first = withAlpha.frames.first.pixels;

      var transparent = 0;
      var opaque = 0;
      var partial = 0;
      var faint = 0;
      for (var i = 0; i < first.length; i += 4) {
        final a = first[i + 3];
        // Premultiplied: no colour channel exceeds its alpha.
        expect(first[i], lessThanOrEqualTo(a), reason: 'blue at $i');
        expect(first[i + 1], lessThanOrEqualTo(a), reason: 'green at $i');
        expect(first[i + 2], lessThanOrEqualTo(a), reason: 'red at $i');
        if (a == 0) transparent++;
        if (a == 255) opaque++;
        if (a > 0 && a < 255) partial++;
        // The disc is grey at luma 200, which is 214 of 255 (limited-range
        // YUV): a straight-alpha pixel of coverage c has colour 0.84 * a at
        // best, one premultiplied again has 0.84 * c * a. So at low alpha
        // premultiplied colour is far under 0.6 * a and a straight one is
        // not; `colour <= alpha` alone would pass for both.
        if (a > 0 && a < 128) {
          faint++;
          expect(first[i + 2], lessThanOrEqualTo(a * 0.6), reason: 'at $i');
        }
      }
      expect(faint, greaterThan(0), reason: 'a faint rim pixel to judge');
      // The disc: opaque inside, clear outside, a soft rim from scaling.
      expect(transparent, greaterThan(0));
      expect(opaque, greaterThan(0));
      expect(partial, greaterThan(0), reason: 'a semi-transparent rim');

      for (final fixture in [mp4, gif]) {
        final decoded = _decodeAll(binding, fixture, width: 32, height: 24);
        for (final frame in decoded.frames) {
          for (var i = 3; i < frame.pixels.length; i += 4) {
            expect(frame.pixels[i], 255, reason: fixture.file);
          }
        }
      }
    });

    test('are scaled to the target size and stay inside the slot', () {
      const width = 40;
      const height = 30;
      const stride = 48 * 4;
      final opened =
          binding.open(mp4.bytes, width: width, height: height) as VideoOpened;
      final page = calloc<Uint8>(stride * height);
      try {
        page.asTypedList(stride * height).fillRange(0, stride * height, 0x7f);

        final result = binding.nextFrame(
          opened.handle,
          target: page,
          strideBytes: stride,
        );

        expect(result.status, VideoFrameStatus.frame);
        final bytes = page.asTypedList(stride * height);
        for (var y = 0; y < height; y++) {
          final row = bytes.sublist(y * stride, (y + 1) * stride);
          expect(
            row.sublist(width * 4),
            everyElement(0x7f),
            reason: 'padding of row $y',
          );
          expect(row.sublist(0, width * 4), isNot(everyElement(0x7f)));
        }
      } finally {
        calloc.free(page);
        binding.dispose(opened.handle);
      }
    });
  });
}

/// Every frame of [fixture] at [width] by [height], and what a further call
/// after the end answered.
({List<_Frame> frames, VideoFrameStatus afterEnd}) _decodeAll(
  VideoBinding binding,
  Fixture fixture, {
  required int width,
  required int height,
}) {
  final opened =
      binding.open(fixture.bytes, width: width, height: height) as VideoOpened;
  final target = calloc<Uint8>(width * height * 4);
  try {
    final frames = <_Frame>[];
    while (true) {
      final result = binding.nextFrame(
        opened.handle,
        target: target,
        strideBytes: width * 4,
      );
      if (result.status != VideoFrameStatus.frame) {
        final again = binding.nextFrame(
          opened.handle,
          target: target,
          strideBytes: width * 4,
        );
        expect(result.status, VideoFrameStatus.endOfStream);
        return (frames: frames, afterEnd: again.status);
      }
      frames.add(
        _Frame(
          result.ptsMs,
          Uint8List.fromList(target.asTypedList(width * height * 4)),
        ),
      );
    }
  } finally {
    calloc.free(target);
    binding.dispose(opened.handle);
  }
}

final class _Frame {
  const _Frame(this.ptsMs, this.pixels);
  final int ptsMs;
  final Uint8List pixels;
}

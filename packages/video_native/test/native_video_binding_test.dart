import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_native/video_native.dart';

// ignore: always_use_package_imports
import 'support/fixtures.dart';

void main() {
  final binding = NativeVideoBinding.probe();

  group('NativeVideoBinding.probe', () {
    test(
      'finds the built library and its ABI version',
      skip: nativeSkipReason(binding),
      () {
        expect(binding.availability, VideoAvailability.available);
      },
    );
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

  group('rewind', skip: nativeSkipReason(binding), () {
    test('restarts the stream with an identical first frame', () {
      for (final fixture in fixtures) {
        final opened =
            binding.open(fixture.bytes, width: 32, height: 24) as VideoOpened;
        final target = calloc<Uint8>(32 * 24 * 4);
        Uint8List next() {
          final result = binding.nextFrame(
            opened.handle,
            target: target,
            strideBytes: 32 * 4,
          );
          expect(result.status, VideoFrameStatus.frame, reason: fixture.file);
          return Uint8List.fromList(target.asTypedList(32 * 24 * 4));
        }

        try {
          final first = next();
          // Mid-stream, then to the very end, then back.
          next();
          expect(binding.rewind(opened.handle), isTrue);
          expect(next(), orderedEquals(first), reason: fixture.file);

          var count = 1;
          while (binding
                  .nextFrame(opened.handle, target: target, strideBytes: 128)
                  .status ==
              VideoFrameStatus.frame) {
            count++;
          }
          expect(count, fixture.frames, reason: fixture.file);
          expect(binding.rewind(opened.handle), isTrue);
          expect(next(), orderedEquals(first), reason: fixture.file);
        } finally {
          calloc.free(target);
          binding.dispose(opened.handle);
        }
      }
    });

    test('is refused for a handle that is not open', () {
      expect(binding.rewind(const VideoHandle(9999)), isFalse);
    });
  });

  group('hostile input', skip: nativeSkipReason(binding), () {
    VideoRejection? rejection(
      Uint8List bytes, {
      int width = 32,
      int height = 24,
    }) => switch (binding.open(bytes, width: width, height: height)) {
      VideoRejected(:final reason) => reason,
      final VideoOpened opened => () {
        binding.dispose(opened.handle);
        return null;
      }(),
    };

    test('input over the byte cap is refused before it is read', () {
      expect(
        rejection(Uint8List(10 * 1024 * 1024 + 1)),
        VideoRejection.tooLarge,
      );
    });

    test('empty and garbage input is malformed', () {
      expect(rejection(Uint8List(0)), VideoRejection.malformed);
      expect(rejection(Uint8List(4096)), VideoRejection.malformed);
      expect(
        rejection(Uint8List.fromList(List.generate(4096, (i) => i * 31))),
        VideoRejection.malformed,
      );
    });

    test('a target size of zero or over the cap is a bad size', () {
      for (final (w, h) in [(0, 24), (32, 0), (2049, 24), (32, 2049)]) {
        expect(
          rejection(mp4.bytes, width: w, height: h),
          VideoRejection.badSize,
          reason: '${w}x$h',
        );
      }
      expect(rejection(mp4.bytes, width: 2048, height: 2048), isNull);
    });

    test('a source over the dimension cap is refused', () {
      // Over the area cap and over the edge cap, each by one step.
      expect(
        rejection(_gif(width: 3000, height: 2900, frames: 1)),
        VideoRejection.limitExceeded,
      );
      expect(
        rejection(_gif(width: 3841, height: 1, frames: 1)),
        VideoRejection.limitExceeded,
      );
      // At the caps it opens.
      expect(rejection(_gif(width: 3840, height: 1, frames: 1)), isNull);
      expect(rejection(_gif(width: 3000, height: 2700, frames: 1)), isNull);
      // FFmpeg's own size check refuses this one before the wrapper's cap.
      expect(
        rejection(_gif(width: 60000, height: 60000, frames: 1)),
        anyOf(VideoRejection.malformed, VideoRejection.limitExceeded),
      );
    });

    test('a stream past the frame budget fails, and a rewind revives it', () {
      final opened =
          binding.open(
                _gif(width: 1, height: 1, frames: 10100),
                width: 1,
                height: 1,
              )
              as VideoOpened;
      final target = calloc<Uint8>(4);
      try {
        var frames = 0;
        late VideoFrameResult last;
        do {
          last = binding.nextFrame(
            opened.handle,
            target: target,
            strideBytes: 4,
          );
          if (last.status == VideoFrameStatus.frame) frames++;
        } while (last.status == VideoFrameStatus.frame);

        expect(last.status, VideoFrameStatus.failed);
        expect(frames, 10000);
        // Spent: it stays failed until a rewind.
        expect(
          binding
              .nextFrame(opened.handle, target: target, strideBytes: 4)
              .status,
          VideoFrameStatus.failed,
        );
        expect(binding.rewind(opened.handle), isTrue);
        expect(
          binding
              .nextFrame(opened.handle, target: target, strideBytes: 4)
              .status,
          VideoFrameStatus.frame,
        );
      } finally {
        calloc.free(target);
        binding.dispose(opened.handle);
      }
    });

    test('damaged copies of each fixture end in a defined status', () {
      for (final fixture in fixtures) {
        final good = fixture.bytes;
        final damaged = <String, Uint8List>{
          'truncated to a tenth': good.sublist(0, good.length ~/ 10),
          'truncated to half': good.sublist(0, good.length ~/ 2),
          'truncated by a byte': good.sublist(0, good.length - 1),
          'every 97th byte flipped': Uint8List.fromList([
            for (var i = 0; i < good.length; i++)
              i % 97 == 0 ? good[i] ^ 0xff : good[i],
          ]),
          'every 7th byte flipped': Uint8List.fromList([
            for (var i = 0; i < good.length; i++)
              i % 7 == 0 ? good[i] ^ 0xa5 : good[i],
          ]),
          'middle zeroed': Uint8List.fromList([
            for (var i = 0; i < good.length; i++)
              i > good.length ~/ 4 && i < good.length * 3 ~/ 4 ? 0 : good[i],
          ]),
          'all zeroed': Uint8List(good.length),
        };
        for (final MapEntry(key: how, value: bytes) in damaged.entries) {
          final reason = '${fixture.file} $how';
          final opened = binding.open(bytes, width: 32, height: 24);
          if (opened is! VideoOpened) continue;
          final target = calloc<Uint8>(32 * 24 * 4);
          try {
            var last = VideoFrameStatus.frame;
            // Bounded by the frame budget; a run that does not stop is a bug.
            for (var i = 0; i < 10100 && last == VideoFrameStatus.frame; i++) {
              last = binding
                  .nextFrame(opened.handle, target: target, strideBytes: 128)
                  .status;
            }
            expect(
              last,
              anyOf(VideoFrameStatus.endOfStream, VideoFrameStatus.failed),
              reason: reason,
            );
          } finally {
            calloc.free(target);
            binding.dispose(opened.handle);
          }
        }
      }
    });
  });

  group('memory', skip: nativeSkipReason(binding), () {
    test('open, decode and free cycles do not grow the process', () {
      final damaged = Uint8List.fromList([
        for (var i = 0; i < mp4.bytes.length; i++)
          i % 97 == 0 ? mp4.bytes[i] ^ 0xff : mp4.bytes[i],
      ]);
      final target = calloc<Uint8>(64 * 48 * 4);
      void cycle(Uint8List bytes) {
        final result = binding.open(bytes, width: 64, height: 48);
        if (result is! VideoOpened) return;
        for (var i = 0; i < 3; i++) {
          binding.nextFrame(result.handle, target: target, strideBytes: 256);
        }
        binding.rewind(result.handle);
        binding.dispose(result.handle);
      }

      try {
        // Warm up allocator pools, then measure.
        for (var i = 0; i < 50; i++) {
          cycle(webm.bytes);
        }
        final before = ProcessInfo.currentRss;
        for (var i = 0; i < 200; i++) {
          cycle(
            [mp4.bytes, webm.bytes, gif.bytes, damaged, Uint8List(64)][i % 5],
          );
        }
        final grown = ProcessInfo.currentRss - before;

        // A leaked decoder context is hundreds of KB; 200 leaks would be
        // tens of MB.
        expect(grown, lessThan(8 * 1024 * 1024));
      } finally {
        calloc.free(target);
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

/// A GIF of [frames] one-pixel images on a [width] by [height] screen: the
/// only fixture-less way to make a hostile size or a very long stream.
Uint8List _gif({required int width, required int height, required int frames}) {
  final out = BytesBuilder()
    ..add('GIF89a'.codeUnits)
    ..add([width & 0xff, width >> 8, height & 0xff, height >> 8, 0x80, 0, 0])
    // A two-colour global table: without a palette no frame decodes.
    ..add([0, 0, 0, 255, 255, 255]);
  for (var i = 0; i < frames; i++) {
    out
      // Graphic control: 1/100 s delay.
      ..add([0x21, 0xf9, 4, 0, 1, 0, 0, 0])
      // Image descriptor: 1x1 at the origin, no local table.
      ..add([0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0])
      // LZW minimum code size 2: clear, pixel 0, end.
      ..add([2, 2, 0x44, 0x01, 0]);
  }
  out.addByte(0x3b);
  return out.toBytes();
}

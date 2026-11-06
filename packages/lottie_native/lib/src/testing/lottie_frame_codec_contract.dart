import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_native/src/lottie_frame_codec.dart';

/// What a [LottieFrameCodecContract] run needs besides the codec.
final class LottieFrameCodecHarness {
  /// Creates a harness around [codec].
  LottieFrameCodecHarness({required this.codec, this.unavailable});

  /// The codec under test; it must be available.
  final LottieFrameCodec codec;

  /// Builds a codec that is not available, if the implementation can; its
  /// case is skipped otherwise.
  final LottieFrameCodec Function()? unavailable;
}

/// The behaviour every [LottieFrameCodec] shares, run over its fake and over
/// the native codec alike.
abstract final class LottieFrameCodecContract {
  static const _guard = 0xAB;
  static const _side = 24;
  static const _slotX = 5;
  static const _slotY = 3;

  /// Registers the contract's tests; [create] builds a fresh harness for each.
  static void run(LottieFrameCodecHarness Function() create) {
    group('LottieFrameCodec contract', () {
      late LottieFrameCodecHarness harness;

      setUp(() => harness = create());

      test('the codec is available', () {
        expect(harness.codec.isAvailable, isTrue);
      });

      for (final kind in _RegionKind.values) {
        test('a ${kind.name} region round trips byte for byte', () {
          final source = _Page(_side, _side)..fill(kind.pixels(_side, _side));
          final target = _Page(_side, _side);
          addTearDown(source.free);
          addTearDown(target.free);

          final packed = harness.codec.compress(source.region);
          expect(packed, isNotNull);

          expect(harness.codec.decompress(packed!, target.region), isTrue);
          expect(target.slot(), source.slot());
        });
      }

      test('decompress leaves every byte outside the region alone', () {
        final source = _Page(_side, _side)
          ..fill(_RegionKind.noise.pixels(_side, _side));
        final target = _Page(_side, _side);
        addTearDown(source.free);
        addTearDown(target.free);

        final packed = harness.codec.compress(source.region)!;
        harness.codec.decompress(packed, target.region);

        expect(target.outsideIsGuard(), isTrue);
      });

      test('compress reads the region and not its row gaps', () {
        final page = _Page(_side, _side)
          ..fill(_RegionKind.gradient.pixels(_side, _side));
        addTearDown(page.free);
        final clean = harness.codec.compress(page.region)!;

        page.scribbleOutside(0x11);

        expect(harness.codec.compress(page.region), clean);
      });

      test('corrupt data is refused and leaves the target unchanged', () {
        final source = _Page(_side, _side)
          ..fill(_RegionKind.gradient.pixels(_side, _side));
        final target = _Page(_side, _side);
        addTearDown(source.free);
        addTearDown(target.free);
        final packed = harness.codec.compress(source.region)!;
        final before = target.snapshot();

        for (final corrupt in [
          Uint8List(0),
          Uint8List.sublistView(packed, 0, packed.length ~/ 2),
          Uint8List.sublistView(packed, 0, 1),
        ]) {
          expect(
            harness.codec.decompress(corrupt, target.region),
            isFalse,
            reason: '${corrupt.length} bytes of ${packed.length}',
          );
          expect(target.snapshot(), before);
        }
      });

      test('data for other dimensions is refused, target unchanged', () {
        final small = _Page(_side ~/ 2, _side ~/ 2)
          ..fill(_RegionKind.gradient.pixels(_side ~/ 2, _side ~/ 2));
        final target = _Page(_side, _side);
        addTearDown(small.free);
        addTearDown(target.free);
        final packed = harness.codec.compress(small.region)!;
        final before = target.snapshot();

        expect(harness.codec.decompress(packed, target.region), isFalse);
        expect(target.snapshot(), before);
      });

      test('a rejected region compresses to null', () {
        final page = _Page(_side, _side);
        addTearDown(page.free);
        final region = page.region;

        for (final rejected in [
          page.regionWith(width: 0),
          page.regionWith(height: 0),
          page.regionWith(width: LottieFrameRegion.maxEdge + 1),
          page.regionWith(strideBytes: region.width * 4 - 1),
        ]) {
          expect(harness.codec.compress(rejected), isNull);
        }
      });

      test('a rejected region refuses to decompress, target unchanged', () {
        final source = _Page(_side, _side)
          ..fill(_RegionKind.gradient.pixels(_side, _side));
        final target = _Page(_side, _side);
        addTearDown(source.free);
        addTearDown(target.free);
        final packed = harness.codec.compress(source.region)!;
        final before = target.snapshot();

        expect(
          harness.codec.decompress(packed, target.regionWith(width: 0)),
          isFalse,
        );
        expect(target.snapshot(), before);
      });

      test('a codec that is not available throws StateError', () {
        final make = harness.unavailable;
        if (make == null) {
          markTestSkipped('The implementation cannot be made unavailable.');
          return;
        }
        final off = make();
        final page = _Page(_side, _side);
        addTearDown(page.free);

        expect(off.isAvailable, isFalse);
        expect(() => off.compress(page.region), throwsStateError);
        expect(
          () => off.decompress(Uint8List(1), page.region),
          throwsStateError,
        );
      });
    });
  }

  /// Decompresses corrupt data into a guard-filled region and fails unless the
  /// region is untouched: the check a decompress that writes before it
  /// validates fails.
  static void checkCorruptDataLeavesTargetUnchanged(
    LottieFrameCodecHarness harness,
  ) {
    final source = _Page(_side, _side)
      ..fill(_RegionKind.gradient.pixels(_side, _side));
    final target = _Page(_side, _side);
    try {
      final packed = harness.codec.compress(source.region)!;
      final before = target.snapshot();
      harness.codec.decompress(
        Uint8List.sublistView(packed, 0, packed.length ~/ 2),
        target.region,
      );
      expect(
        target.snapshot(),
        before,
        reason: 'a failed decompress changed the target',
      );
    } finally {
      source.free();
      target.free();
    }
  }
}

/// The three kinds of region the frame cache sees.
enum _RegionKind {
  /// Premultiplied colour fading in with alpha.
  gradient,

  /// Nothing drawn.
  transparent,

  /// Incompressible bytes: the lz4 worst case.
  noise;

  Uint8List pixels(int width, int height) {
    final bytes = Uint8List(width * height * 4);
    switch (this) {
      case gradient:
        for (var i = 0; i < width * height; i++) {
          final alpha = 255 * (i % width + i ~/ width) ~/ (width + height - 2);
          bytes.setAll(i * 4, [alpha ~/ 2, alpha ~/ 3, alpha ~/ 4, alpha]);
        }
      case transparent:
        break;
      case noise:
        var state = 0x2545F491;
        for (var i = 0; i < bytes.length; i++) {
          state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
          bytes[i] = state >> 16;
        }
    }
    return bytes;
  }
}

/// A guard-filled page with a [width] x [height] region inside it, so a write
/// past any edge of the region, or into a row gap, lands on a guard byte.
final class _Page {
  _Page(this.width, this.height)
    : _stride = (width + 2 * LottieFrameCodecContract._slotX) * 4 + 8,
      _rows = height + 2 * LottieFrameCodecContract._slotY {
    _memory = calloc<Uint8>(_stride * _rows);
    _bytes.fillRange(0, _bytes.length, LottieFrameCodecContract._guard);
    fill(Uint8List(width * height * 4));
  }

  final int width;
  final int height;
  final int _stride;
  final int _rows;
  late final Pointer<Uint8> _memory;

  Uint8List get _bytes => _memory.asTypedList(_stride * _rows);

  int get _origin =>
      LottieFrameCodecContract._slotY * _stride +
      LottieFrameCodecContract._slotX * 4;

  LottieFrameRegion get region => regionWith();

  LottieFrameRegion regionWith({int? width, int? height, int? strideBytes}) =>
      LottieFrameRegion(
        target: Pointer<Uint8>.fromAddress(_memory.address + _origin),
        width: width ?? this.width,
        height: height ?? this.height,
        strideBytes: strideBytes ?? _stride,
      );

  bool _inRegion(int offset) {
    final y = offset ~/ _stride - LottieFrameCodecContract._slotY;
    final x = (offset % _stride) ~/ 4 - LottieFrameCodecContract._slotX;
    return y >= 0 && y < height && x >= 0 && x < width;
  }

  void fill(Uint8List pixels) {
    for (var y = 0; y < height; y++) {
      _bytes.setRange(
        _origin + y * _stride,
        _origin + y * _stride + width * 4,
        pixels,
        y * width * 4,
      );
    }
  }

  /// The region's bytes, row by row.
  List<int> slot() {
    final all = _bytes;
    return [
      for (var i = 0; i < all.length; i++)
        if (_inRegion(i)) all[i],
    ];
  }

  Uint8List snapshot() => Uint8List.fromList(_bytes);

  bool outsideIsGuard() {
    final all = _bytes;
    for (var i = 0; i < all.length; i++) {
      if (!_inRegion(i) && all[i] != LottieFrameCodecContract._guard) {
        return false;
      }
    }
    return true;
  }

  void scribbleOutside(int value) {
    final all = _bytes;
    for (var i = 0; i < all.length; i++) {
      if (!_inRegion(i)) all[i] = value;
    }
  }

  void free() => calloc.free(_memory);
}

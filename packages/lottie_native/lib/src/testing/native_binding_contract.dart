import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lottie_native/src/lottie_binding.dart';
import 'package:lottie_native/src/lottie_load_result.dart';

/// What a [NativeBindingContract] run needs besides the binding.
final class NativeBindingHarness {
  /// Creates a harness around [binding].
  NativeBindingHarness({
    required this.binding,
    required this.validBytes,
    required this.expectedInfo,
    required this.malformedBytes,
    this.earlyFrame = 0,
    this.laterFrame = 1,
    this.unavailable,
  });

  /// The binding under test; it must be available.
  final LottieBinding binding;

  /// A file the binding loads.
  final Uint8List validBytes;

  /// What [validBytes] declares.
  final LottieInfo expectedInfo;

  /// Bytes the binding refuses (not a Lottie file).
  final Uint8List malformedBytes;

  /// A frame of [validBytes] that draws something.
  final double earlyFrame;

  /// A frame of [validBytes] whose pixels differ from [earlyFrame]'s.
  final double laterFrame;

  /// Builds a binding that is not available, if the implementation can; its
  /// case is skipped otherwise.
  final LottieBinding Function()? unavailable;
}

/// The behaviour every [LottieBinding] shares, run over its fake and over the
/// native binding alike.
abstract final class NativeBindingContract {
  static const _side = 16;
  static const _pageSide = 48;
  static const _slotX = 16;
  static const _slotY = 16;
  static const _stride = _pageSide * 4;

  /// Registers the contract's tests; [create] builds a fresh harness for each.
  static void run(NativeBindingHarness Function() create) {
    group('LottieBinding contract', () {
      late NativeBindingHarness harness;

      setUp(() => harness = create());

      LottieHandle load() {
        final result = harness.binding.load(harness.validBytes);
        expect(result, isA<LottieLoaded>());
        return (result as LottieLoaded).handle;
      }

      test('the probe says available, and stays so', () {
        expect(harness.binding.isAvailable, isTrue);
        expect(harness.binding.availability, LottieAvailability.available);
        load();
        expect(harness.binding.isAvailable, isTrue);
        expect(harness.binding.availability, LottieAvailability.available);
      });

      test('valid bytes load with the expected info', () {
        final result = harness.binding.load(harness.validBytes);

        expect((result as LottieLoaded).info, harness.expectedInfo);
      });

      test('malformed bytes are rejected, never thrown', () {
        expect(
          harness.binding.load(harness.malformedBytes),
          isA<LottieRejected>(),
        );
      });

      test('empty bytes are rejected, never thrown', () {
        expect(harness.binding.load(Uint8List(0)), isA<LottieRejected>());
      });

      test('a render writes premultiplied pixels', () {
        checkWritesPremultiplied(harness);
      });

      test('a render writes inside its slot only', () {
        checkWritesInsideSlot(harness);
      });

      test('a later frame looks different', () {
        final handle = load();
        final early = _renderOne(harness.binding, handle, harness.earlyFrame);
        final later = _renderOne(harness.binding, handle, harness.laterFrame);

        expect(later, isNot(early));
      });

      test('a bad job is reported and spares the others', () {
        final handle = load();
        final page = _Page();
        addTearDown(page.free);
        final bad = page.job(handle, harness.earlyFrame, width: 0);
        final good = page.job(handle, harness.earlyFrame);

        final statuses = harness.binding.renderBatch([bad, good]);

        expect(statuses, [LottieRenderStatus.badSize, LottieRenderStatus.ok]);
        expect(page.slot().any((byte) => byte != 0), isTrue);
      });

      test('an edge over the maximum is a bad size', () {
        final handle = load();
        final page = _Page();
        addTearDown(page.free);
        final wide = page.job(
          handle,
          harness.earlyFrame,
          width: LottieRenderJob.maxEdge + 1,
        );

        expect(harness.binding.renderBatch([wide]), [
          LottieRenderStatus.badSize,
        ]);
      });

      test('a disposed handle is refused, not crashed on', () {
        final handle = load();
        harness.binding.dispose(handle);
        final page = _Page();
        addTearDown(page.free);

        final statuses = harness.binding.renderBatch([
          page.job(handle, harness.earlyFrame),
        ]);

        expect(statuses, [LottieRenderStatus.badArgument]);
      });

      test('dispose twice is harmless', () {
        final handle = load();

        harness.binding.dispose(handle);

        expect(() => harness.binding.dispose(handle), returnsNormally);
      });

      test('a binding that is not available throws StateError on load', () {
        final make = harness.unavailable;
        if (make == null) {
          markTestSkipped('The implementation cannot be made unavailable.');
          return;
        }
        final off = make();

        expect(off.isAvailable, isFalse);
        expect(off.availability, isNot(LottieAvailability.available));
        expect(() => off.load(harness.validBytes), throwsStateError);
      });

      test('close refuses load and renderBatch afterwards', () {
        final handle = load();
        final page = _Page();
        addTearDown(page.free);

        harness.binding.close();

        expect(
          () => harness.binding.load(harness.validBytes),
          throwsStateError,
        );
        expect(
          () => harness.binding.renderBatch([
            page.job(handle, harness.earlyFrame),
          ]),
          throwsStateError,
        );
      });

      test('close twice, and dispose after close, are harmless', () {
        final handle = load();

        harness.binding.close();

        expect(() => harness.binding.close(), returnsNormally);
        expect(() => harness.binding.dispose(handle), returnsNormally);
      });
    });
  }

  /// Renders into a slot of a larger zeroed buffer and fails unless every
  /// byte outside the slot is still zero.
  static void checkWritesInsideSlot(NativeBindingHarness harness) {
    final handle = _loadOrFail(harness);
    final page = _Page();
    try {
      final status = harness.binding.renderBatch([
        page.job(handle, harness.earlyFrame),
      ]);
      expect(status, [LottieRenderStatus.ok]);
      expect(
        page.outsideSlotIsZero(),
        isTrue,
        reason: 'bytes outside the slot were written',
      );
    } finally {
      page.free();
    }
  }

  /// Fails unless the slot holds pixels and no channel is above its alpha.
  static void checkWritesPremultiplied(NativeBindingHarness harness) {
    final handle = _loadOrFail(harness);
    final page = _Page();
    try {
      harness.binding.renderBatch([page.job(handle, harness.earlyFrame)]);
      final pixels = page.slot();
      expect(
        pixels.any((byte) => byte != 0),
        isTrue,
        reason: 'nothing was drawn',
      );
      for (var p = 0; p < pixels.length; p += 4) {
        final alpha = pixels[p + 3];
        expect(
          [pixels[p], pixels[p + 1], pixels[p + 2]].every((c) => c <= alpha),
          isTrue,
          reason: 'pixel ${p ~/ 4} has a channel above its alpha',
        );
      }
    } finally {
      page.free();
    }
  }

  static LottieHandle _loadOrFail(NativeBindingHarness harness) {
    final result = harness.binding.load(harness.validBytes);
    expect(result, isA<LottieLoaded>());
    return (result as LottieLoaded).handle;
  }

  static List<int> _renderOne(
    LottieBinding binding,
    LottieHandle handle,
    double frame,
  ) {
    final page = _Page();
    try {
      binding.renderBatch([page.job(handle, frame)]);
      return page.slot();
    } finally {
      page.free();
    }
  }
}

/// A zeroed page with a 16 x 16 slot in its middle, so a write past any edge
/// of the slot lands in guard bytes.
final class _Page {
  _Page()
    : _memory = calloc<Uint8>(
        NativeBindingContract._pageSide * NativeBindingContract._stride,
      );

  final Pointer<Uint8> _memory;

  Pointer<Uint8> get _slotStart => Pointer<Uint8>.fromAddress(
    _memory.address +
        NativeBindingContract._slotY * NativeBindingContract._stride +
        NativeBindingContract._slotX * 4,
  );

  LottieRenderJob job(LottieHandle handle, double frame, {int? width}) =>
      LottieRenderJob(
        handle: handle,
        frame: frame,
        width: width ?? NativeBindingContract._side,
        height: NativeBindingContract._side,
        target: _slotStart,
        strideBytes: NativeBindingContract._stride,
      );

  Uint8List _all() => _memory.asTypedList(
    NativeBindingContract._pageSide * NativeBindingContract._stride,
  );

  bool _inSlot(int offset) {
    final y = offset ~/ NativeBindingContract._stride;
    final x = (offset % NativeBindingContract._stride) ~/ 4;
    return y >= NativeBindingContract._slotY &&
        y < NativeBindingContract._slotY + NativeBindingContract._side &&
        x >= NativeBindingContract._slotX &&
        x < NativeBindingContract._slotX + NativeBindingContract._side;
  }

  /// The slot's bytes, row by row.
  List<int> slot() {
    final all = _all();
    return [
      for (var i = 0; i < all.length; i++)
        if (_inSlot(i)) all[i],
    ];
  }

  bool outsideSlotIsZero() {
    final all = _all();
    for (var i = 0; i < all.length; i++) {
      if (!_inSlot(i) && all[i] != 0) return false;
    }
    return true;
  }

  void free() => calloc.free(_memory);
}

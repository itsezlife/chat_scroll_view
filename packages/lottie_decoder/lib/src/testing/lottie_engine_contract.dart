import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_native/lottie_native.dart';

/// What a [LottieEngineContract] run needs besides the engine.
final class LottieEngineHarness {
  /// Creates a harness whose engines come from [open].
  LottieEngineHarness({
    required this.open,
    required this.validBytes,
    required this.expectedInfo,
    required this.malformedBytes,
    this.frame = 0,
  });

  /// Opens a fresh engine over an available binding; the contract closes it.
  final Future<LottieEngine> Function() open;

  /// A file the binding loads.
  final Uint8List validBytes;

  /// What [validBytes] declares.
  final LottieInfo expectedInfo;

  /// Bytes the binding refuses (not a Lottie file).
  final Uint8List malformedBytes;

  /// A frame of [validBytes] that draws something.
  final double frame;
}

/// The behaviour every [LottieEngine] shares, run over the in-process engine
/// on the fake and over the isolate engine on the fake and on the real
/// binding alike.
abstract final class LottieEngineContract {
  static const _side = 16;
  static const _pageSide = 48;
  static const _slotX = 16;
  static const _slotY = 16;
  static const _stride = _pageSide * 4;

  /// Registers the contract's tests; [create] builds a fresh harness for each.
  static void run(LottieEngineHarness Function() create) {
    group('LottieEngine contract', () {
      late LottieEngineHarness harness;
      late LottieEngine engine;

      setUp(() async {
        harness = create();
        engine = await harness.open();
        addTearDown(engine.close);
      });

      Future<LottieHandle> load() async {
        final result = await engine.load(harness.validBytes);
        expect(result, isA<LottieLoaded>());
        return (result as LottieLoaded).handle;
      }

      test('valid bytes load with the expected info', () async {
        final result = await engine.load(harness.validBytes);

        expect((result as LottieLoaded).info, harness.expectedInfo);
      });

      test('malformed and empty bytes are rejected, never thrown', () async {
        expect(
          await engine.load(harness.malformedBytes),
          isA<LottieRejected>(),
        );
        expect(await engine.load(Uint8List(0)), isA<LottieRejected>());
      });

      test('a render writes premultiplied pixels inside its slot', () async {
        final handle = await load();
        final page = _Page();
        addTearDown(page.free);

        final statuses = await engine.renderBatch([
          page.job(handle, harness.frame),
        ]);

        expect(statuses, [LottieRenderStatus.ok]);
        final pixels = page.slot();
        expect(
          pixels.any((byte) => byte != 0),
          isTrue,
          reason: 'nothing drawn',
        );
        for (var p = 0; p < pixels.length; p += 4) {
          final alpha = pixels[p + 3];
          expect(
            [pixels[p], pixels[p + 1], pixels[p + 2]].every((c) => c <= alpha),
            isTrue,
            reason: 'pixel ${p ~/ 4} has a channel above its alpha',
          );
        }
        expect(
          page.outsideSlotIsZero(),
          isTrue,
          reason: 'bytes outside the slot were written',
        );
      });

      test('a bad job is reported and spares the others', () async {
        final handle = await load();
        final page = _Page();
        addTearDown(page.free);

        final statuses = await engine.renderBatch([
          page.job(handle, harness.frame, width: 0),
          page.job(handle, harness.frame),
        ]);

        expect(statuses, [LottieRenderStatus.badSize, LottieRenderStatus.ok]);
        expect(page.slot().any((byte) => byte != 0), isTrue);
      });

      test('a disposed handle is refused, not crashed on', () async {
        final handle = await load();
        final page = _Page();
        addTearDown(page.free);

        await engine.dispose(handle);
        final statuses = await engine.renderBatch([
          page.job(handle, harness.frame),
        ]);

        expect(statuses, [LottieRenderStatus.badArgument]);
      });

      test('dispose twice is harmless', () async {
        final handle = await load();

        await engine.dispose(handle);

        await expectLater(engine.dispose(handle), completes);
      });

      test('close is idempotent and later calls throw StateError', () async {
        final handle = await load();

        await engine.close();
        await engine.close();

        await expectLater(engine.load(harness.validBytes), throwsStateError);
        await expectLater(engine.renderBatch(const []), throwsStateError);
        await expectLater(engine.dispose(handle), throwsStateError);
      });
    });
  }
}

/// A zeroed page with a 16 x 16 slot in its middle, so a write past any edge
/// of the slot lands in guard bytes.
final class _Page {
  _Page()
    : _memory = calloc<Uint8>(
        LottieEngineContract._pageSide * LottieEngineContract._stride,
      );

  final Pointer<Uint8> _memory;

  LottieEngineJob job(LottieHandle handle, double frame, {int? width}) =>
      LottieEngineJob(
        handle: handle,
        frame: frame,
        width: width ?? LottieEngineContract._side,
        height: LottieEngineContract._side,
        address:
            _memory.address +
            LottieEngineContract._slotY * LottieEngineContract._stride +
            LottieEngineContract._slotX * 4,
        strideBytes: LottieEngineContract._stride,
      );

  Uint8List _all() => _memory.asTypedList(
    LottieEngineContract._pageSide * LottieEngineContract._stride,
  );

  bool _inSlot(int offset) {
    final y = offset ~/ LottieEngineContract._stride;
    final x = (offset % LottieEngineContract._stride) ~/ 4;
    return y >= LottieEngineContract._slotY &&
        y < LottieEngineContract._slotY + LottieEngineContract._side &&
        x >= LottieEngineContract._slotX &&
        x < LottieEngineContract._slotX + LottieEngineContract._side;
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

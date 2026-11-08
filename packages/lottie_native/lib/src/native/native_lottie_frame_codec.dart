import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:lottie_native/src/lottie_frame_codec.dart';
import 'package:lottie_native/src/native/chat_lottie_symbols.dart';
import 'package:meta/meta.dart';

/// [LottieFrameCodec] over the compiled `chat_lottie` library.
final class NativeLottieFrameCodec implements LottieFrameCodec {
  /// Probes the library once, by the rule of `NativeLottieBinding.probe`: a
  /// missing library or symbol, or an ABI version other than the expected
  /// one, is not available. Any other error propagates.
  factory NativeLottieFrameCodec.probe() => NativeLottieFrameCodec.probing(
    abiVersion: chatLottieAbiVersion,
    bound: chatLottieLz4Bound,
  );

  /// Probes with [abiVersion] and [bound] instead of the real symbols, so a
  /// test can stand in a library that lacks one or speaks another version.
  @visibleForTesting
  NativeLottieFrameCodec.probing({
    required int Function() abiVersion,
    required int Function(int width, int height) bound,
  }) : isAvailable = _probe(abiVersion, bound);

  static bool _probe(int Function() abiVersion, int Function(int, int) bound) {
    try {
      return abiVersion() == ChatLottieAbi.expectedVersion && bound(1, 1) >= 0;
      // A symbol the library lacks surfaces as exactly this Error: it is the
      // dynamic-linking answer being probed for, not a bug to propagate.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return false;
    }
  }

  @override
  final bool isAvailable;

  @override
  Uint8List? compress(LottieFrameRegion region) {
    _requireAvailable();
    final cap = chatLottieLz4Bound(region.width, region.height);
    // Zero is the library refusing the size; the call below would too, but
    // allocating a zero-length buffer is not worth the detour.
    if (cap == 0) return null;
    final dst = calloc<Uint8>(cap);
    final outLen = calloc<Size>();
    try {
      final status = chatLottieCompressRegion(
        region.target,
        region.strideBytes,
        region.width,
        region.height,
        dst,
        cap,
        outLen,
      );
      if (status != ChatLottieStatus.ok) return null;
      return Uint8List.fromList(dst.asTypedList(outLen.value));
    } finally {
      calloc
        ..free(dst)
        ..free(outLen);
    }
  }

  @override
  bool decompress(Uint8List data, LottieFrameRegion region) {
    _requireAvailable();
    // Never a zero-length allocation: the library refuses the empty stream.
    final src = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    try {
      src.asTypedList(data.length).setAll(0, data);
      return chatLottieDecompressRegion(
            src,
            data.length,
            region.target,
            region.strideBytes,
            region.width,
            region.height,
          ) ==
          ChatLottieStatus.ok;
    } finally {
      calloc.free(src);
    }
  }

  void _requireAvailable() {
    if (!isAvailable) {
      throw StateError(
        'The native frame codec is not available; use it only when '
        'isAvailable is true.',
      );
    }
  }
}

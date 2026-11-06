import 'dart:ffi';
import 'dart:typed_data';

import 'package:lottie_native/src/lottie_frame_codec.dart';

/// A [LottieFrameCodec] without a native library: a header and the tight
/// pixels, uncompressed, so it is reversible and deterministic.
final class FakeLottieFrameCodec implements LottieFrameCodec {
  /// Creates a fake; [isAvailable] false makes it behave as an unusable codec.
  FakeLottieFrameCodec({this.isAvailable = true});

  // Magic, width, height: a stream of another shape is refused, as the real
  // codec refuses one of another size.
  static const _magic = 0x4B46;
  static const _headerBytes = 6;

  @override
  final bool isAvailable;

  /// Whether every otherwise valid [compress] answers null.
  bool compressFails = false;

  /// Whether every otherwise valid [decompress] answers false.
  bool decompressFails = false;

  void _requireAvailable() {
    if (!isAvailable) throw StateError('The frame codec is not available.');
  }

  static bool _accepts(LottieFrameRegion region) =>
      region.width > 0 &&
      region.height > 0 &&
      region.width <= LottieFrameRegion.maxEdge &&
      region.height <= LottieFrameRegion.maxEdge &&
      region.strideBytes >= region.width * 4;

  @override
  Uint8List? compress(LottieFrameRegion region) {
    _requireAvailable();
    if (compressFails || !_accepts(region)) return null;
    final rowBytes = region.width * 4;
    final out = Uint8List(_headerBytes + rowBytes * region.height);
    ByteData.sublistView(out)
      ..setUint16(0, _magic)
      ..setUint16(2, region.width)
      ..setUint16(4, region.height);
    final rows = region.target.asTypedList(
      (region.height - 1) * region.strideBytes + rowBytes,
    );
    for (var y = 0; y < region.height; y++) {
      out.setRange(
        _headerBytes + y * rowBytes,
        _headerBytes + (y + 1) * rowBytes,
        rows,
        y * region.strideBytes,
      );
    }
    return out;
  }

  @override
  bool decompress(Uint8List data, LottieFrameRegion region) {
    _requireAvailable();
    if (decompressFails || !_accepts(region)) return false;
    final rowBytes = region.width * 4;
    if (data.length != _headerBytes + rowBytes * region.height) return false;
    final header = ByteData.sublistView(data);
    if (header.getUint16(0) != _magic ||
        header.getUint16(2) != region.width ||
        header.getUint16(4) != region.height) {
      return false;
    }
    final rows = region.target.asTypedList(
      (region.height - 1) * region.strideBytes + rowBytes,
    );
    for (var y = 0; y < region.height; y++) {
      rows.setRange(
        y * region.strideBytes,
        y * region.strideBytes + rowBytes,
        data,
        _headerBytes + y * rowBytes,
      );
    }
    return true;
  }
}

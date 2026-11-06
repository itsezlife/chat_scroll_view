import 'dart:convert';
import 'dart:typed_data';

import 'package:lottie_decoder/src/cache/frame_cache_key.dart';

/// The file layout of one cached animation, all integers little-endian
/// unsigned 32-bit:
///
/// ```text
///  0  magic            0x434D5246, the bytes "FRMC"
///  4  format version   1
///  8  width            display pixels
/// 12  height
/// 16  frame count      N, at least 1
/// 20  payload length   the sum of the frame lengths
/// 24  payload CRC-32   of the payload bytes (IEEE 802.3, as zlib's crc32)
/// 28  engine length    E
/// 32  hash length      H
/// 36  engine version   E bytes of ASCII
///     content hash     H bytes of ASCII
///     offsets          N values: where frame i starts in the payload
///     lengths          N values: how long frame i is
///     payload          the frames, back to back
/// ```
///
/// The key's parts repeat what the file name says, on purpose: a file copied
/// or renamed onto another key's name is caught here rather than served as
/// that key's frames. The offsets and the lengths say the same thing twice;
/// a reader checks that they agree, which catches a table that was damaged
/// without changing the payload CRC.
///
/// Bumping the format version makes every older file a miss that is deleted,
/// which is the migration: a cache is rebuilt by rendering, never converted.
abstract final class FrameCacheCodec {
  /// The magic number: "FRMC" read little-endian.
  static const int magic = 0x434D5246;

  /// The layout version [encode] writes.
  static const int formatVersion = 1;

  static const int _fixedHeaderBytes = 36;

  /// The file for [frames] of [key].
  static Uint8List encode(FrameCacheKey key, List<Uint8List> frames) {
    final engine = ascii.encode(key.engineVersion);
    final hash = ascii.encode(key.contentHash);
    final count = frames.length;
    final payloadLength = frames.fold<int>(0, (sum, f) => sum + f.length);
    final tablesStart = _fixedHeaderBytes + engine.length + hash.length;
    final payloadStart = tablesStart + count * 8;

    final out = Uint8List(payloadStart + payloadLength);
    final data = ByteData.sublistView(out);
    data
      ..setUint32(0, magic, Endian.little)
      ..setUint32(4, formatVersion, Endian.little)
      ..setUint32(8, key.width, Endian.little)
      ..setUint32(12, key.height, Endian.little)
      ..setUint32(16, count, Endian.little)
      ..setUint32(20, payloadLength, Endian.little)
      ..setUint32(28, engine.length, Endian.little)
      ..setUint32(32, hash.length, Endian.little);
    out
      ..setRange(_fixedHeaderBytes, _fixedHeaderBytes + engine.length, engine)
      ..setRange(_fixedHeaderBytes + engine.length, tablesStart, hash);
    var offset = 0;
    for (var i = 0; i < count; i++) {
      data
        ..setUint32(tablesStart + i * 4, offset, Endian.little)
        ..setUint32(
          tablesStart + count * 4 + i * 4,
          frames[i].length,
          Endian.little,
        );
      out.setRange(
        payloadStart + offset,
        payloadStart + offset + frames[i].length,
        frames[i],
      );
      offset += frames[i].length;
    }
    data.setUint32(
      24,
      _crc32(out, payloadStart, payloadStart + payloadLength),
      Endian.little,
    );
    return out;
  }

  /// The frames of [bytes] if it is a well-formed file for [key], else null.
  ///
  /// Never throws for damaged input: a file that is truncated, of another
  /// format version or key, with offsets that do not tile the payload, or
  /// whose CRC does not match is a null. The frames are views into [bytes].
  static List<Uint8List>? decode(FrameCacheKey key, Uint8List bytes) {
    if (bytes.length < _fixedHeaderBytes) return null;
    final data = ByteData.sublistView(bytes);
    int u32(int at) => data.getUint32(at, Endian.little);

    if (u32(0) != magic || u32(4) != formatVersion) return null;
    if (u32(8) != key.width || u32(12) != key.height) return null;
    final count = u32(16);
    final payloadLength = u32(20);
    final engineLength = u32(28);
    final hashLength = u32(32);
    // Bound every size by the file before it sizes anything.
    if (count < 1 || count > bytes.length) return null;
    final tablesStart = _fixedHeaderBytes + engineLength + hashLength;
    final payloadStart = tablesStart + count * 8;
    if (engineLength > bytes.length ||
        hashLength > bytes.length ||
        payloadStart > bytes.length ||
        bytes.length - payloadStart != payloadLength) {
      return null;
    }
    final engineEnd = _fixedHeaderBytes + engineLength;
    if (!_equals(bytes, _fixedHeaderBytes, engineEnd, key.engineVersion) ||
        !_equals(bytes, engineEnd, tablesStart, key.contentHash)) {
      return null;
    }
    if (_crc32(bytes, payloadStart, bytes.length) != u32(24)) return null;

    final frames = <Uint8List>[];
    var expectedOffset = 0;
    for (var i = 0; i < count; i++) {
      final offset = u32(tablesStart + i * 4);
      final length = u32(tablesStart + count * 4 + i * 4);
      if (offset != expectedOffset || length > payloadLength - offset) {
        return null;
      }
      frames.add(
        Uint8List.sublistView(
          bytes,
          payloadStart + offset,
          payloadStart + offset + length,
        ),
      );
      expectedOffset = offset + length;
    }
    return expectedOffset == payloadLength ? frames : null;
  }

  static bool _equals(Uint8List bytes, int start, int end, String text) {
    if (end - start != text.length) return false;
    for (var i = 0; i < text.length; i++) {
      if (bytes[start + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  static final Uint32List _table = () {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      }
      table[n] = c;
    }
    return table;
  }();

  static int _crc32(Uint8List bytes, int start, int end) {
    var crc = 0xFFFFFFFF;
    for (var i = start; i < end; i++) {
      crc = _table[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:lottie_decoder/src/cache/frame_cache_key.dart';
import 'package:meta/meta.dart';

/// The file layout of the frames of one parity of a cached animation
/// ([FrameParity]), all integers little-endian unsigned 32-bit:
///
/// ```text
///  0  magic            0x434D5246, the bytes "FRMC"
///  4  format version   3
///  8  width            display pixels
/// 12  height
/// 16  frame count      N, at least 1: the frames of this parity
/// 20  payload length   the sum of the frame lengths
/// 24  engine length    E
/// 28  hash length      H
/// 32  parity           0 for the even frames, 1 for the odd ones
/// 36  engine version   E bytes of ASCII
///     content hash     H bytes of ASCII
///     offsets          N values: where frame i of the parity starts in the
///                      payload (frame 2i or 2i + 1 of the animation)
///     lengths          N values: how long frame i is
///     payload          the frames, back to back
/// ```
///
/// The header is everything before the payload: a reader reads it once and
/// then one frame at a time, at its offset, never the whole file. The key's
/// parts and the parity repeat what the file name says, on purpose: a file
/// copied or renamed onto another key's name, or the other parity's, is caught
/// here rather than served as those frames. The offsets and the lengths say
/// the same thing twice; a reader checks that they agree, which catches a
/// damaged table.
///
/// There is no payload checksum (version 1 had a CRC-32): checking it meant a
/// pass over every byte of the animation, which on the UI isolate was the
/// cost the cache was meant to save. A damaged frame is caught by the frame
/// codec instead, which decodes to exactly the region's bytes or fails.
///
/// Bumping the format version makes every older file a miss that is deleted,
/// which is the migration: a cache is rebuilt by rendering, never converted.
/// A version 2 file is not even opened: its name has no parity, so no key
/// asks for it, and it ages out through the disk budget or the host's store.
abstract final class FrameCacheCodec {
  /// The magic number: "FRMC" read little-endian.
  static const int magic = 0x434D5246;

  /// The layout version [header] writes. Version 3 split an animation into
  /// its two parities; version 2 held every frame in one file.
  static const int formatVersion = 3;

  /// The bytes before the engine version: what a reader reads first to learn
  /// how long the rest of the header is.
  static const int fixedHeaderBytes = 36;

  /// The header for the [parity] frames of an animation of [key], which are
  /// [lengths] bytes long, in order: the file is this followed by the frames.
  static Uint8List header(
    FrameCacheKey key,
    FrameParity parity,
    List<int> lengths,
  ) {
    final engine = ascii.encode(key.engineVersion);
    final hash = ascii.encode(key.contentHash);
    final count = lengths.length;
    final tablesStart = fixedHeaderBytes + engine.length + hash.length;
    final out = Uint8List(tablesStart + count * 8);
    final data = ByteData.sublistView(out);
    var offset = 0;
    for (var i = 0; i < count; i++) {
      data
        ..setUint32(tablesStart + i * 4, offset, Endian.little)
        ..setUint32(tablesStart + (count + i) * 4, lengths[i], Endian.little);
      offset += lengths[i];
    }
    data
      ..setUint32(0, magic, Endian.little)
      ..setUint32(4, formatVersion, Endian.little)
      ..setUint32(8, key.width, Endian.little)
      ..setUint32(12, key.height, Endian.little)
      ..setUint32(16, count, Endian.little)
      ..setUint32(20, offset, Endian.little)
      ..setUint32(24, engine.length, Endian.little)
      ..setUint32(28, hash.length, Endian.little)
      ..setUint32(32, parity.index, Endian.little);
    out
      ..setRange(fixedHeaderBytes, fixedHeaderBytes + engine.length, engine)
      ..setRange(fixedHeaderBytes + engine.length, tablesStart, hash);
    return out;
  }

  /// The length of the whole header, read from its first [fixedHeaderBytes]
  /// bytes [fixed], or null when they are not the start of a file of this
  /// version for the [parity] frames of [key] that fits in [fileLength] bytes.
  static int? headerLength(
    FrameCacheKey key,
    FrameParity parity,
    Uint8List fixed,
    int fileLength,
  ) {
    if (fixed.length < fixedHeaderBytes) return null;
    final data = ByteData.sublistView(fixed);
    int u32(int at) => data.getUint32(at, Endian.little);
    if (u32(0) != magic || u32(4) != formatVersion) return null;
    if (u32(8) != key.width || u32(12) != key.height) return null;
    if (u32(32) != parity.index) return null;
    final count = u32(16);
    final engineLength = u32(24);
    final hashLength = u32(28);
    // Bound every size by the file before it sizes anything.
    if (count < 1 ||
        count > fileLength ||
        engineLength != key.engineVersion.length ||
        hashLength != key.contentHash.length) {
      return null;
    }
    final length = fixedHeaderBytes + engineLength + hashLength + count * 8;
    if (length > fileLength || fileLength - length != u32(20)) return null;
    return length;
  }

  /// The frame table of a file of [fileLength] bytes whose header is
  /// [header], or null when the header is not a well-formed one for the
  /// [parity] frames of [key] whose frames tile the rest of the file and are
  /// each at most [maxFrameBytes] long. Never throws for damaged input.
  static FrameFileTable? table(
    FrameCacheKey key,
    FrameParity parity,
    Uint8List header,
    int fileLength, {
    required int maxFrameBytes,
  }) {
    final length = headerLength(key, parity, header, fileLength);
    if (length == null || header.length != length) return null;
    final data = ByteData.sublistView(header);
    int u32(int at) => data.getUint32(at, Endian.little);
    final count = u32(16);
    final payloadLength = u32(20);
    final engineEnd = fixedHeaderBytes + key.engineVersion.length;
    final tablesStart = engineEnd + key.contentHash.length;
    if (!_equals(header, fixedHeaderBytes, engineEnd, key.engineVersion) ||
        !_equals(header, engineEnd, tablesStart, key.contentHash)) {
      return null;
    }
    final starts = Uint32List(count);
    final lengths = Uint32List(count);
    var expected = 0;
    for (var i = 0; i < count; i++) {
      final offset = u32(tablesStart + i * 4);
      final frame = u32(tablesStart + (count + i) * 4);
      if (offset != expected ||
          frame > maxFrameBytes ||
          frame > payloadLength - offset) {
        return null;
      }
      starts[i] = length + offset;
      lengths[i] = frame;
      expected = offset + frame;
    }
    return expected == payloadLength ? FrameFileTable._(starts, lengths) : null;
  }

  static bool _equals(Uint8List bytes, int start, int end, String text) {
    if (end - start != text.length) return false;
    for (var i = 0; i < text.length; i++) {
      if (bytes[start + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }
}

/// Where each frame of a cached file is: read once per open file, then one
/// lookup per frame.
@immutable
final class FrameFileTable {
  const FrameFileTable._(this._starts, this._lengths);

  final Uint32List _starts;
  final Uint32List _lengths;

  /// How many frames the file holds.
  int get frameCount => _starts.length;

  /// The position in the file where frame [index] starts.
  int startOf(int index) => _starts[index];

  /// How long frame [index] is.
  int lengthOf(int index) => _lengths[index];
}

import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:lottie_decoder/src/cache/cached_frame.dart';
import 'package:lottie_decoder/src/cache/frame_cache_codec.dart';
import 'package:lottie_decoder/src/cache/frame_cache_key.dart';

/// Reads single frames of cached animation files, on the isolate that
/// restores them (the render isolate, or the caller of an in-process engine).
///
/// A file is opened once and its header parsed and checked once; after that
/// a frame is one positioned read of its own bytes, so a playing animation
/// never loads its whole file and nothing but the frame being restored is in
/// memory. The reads are synchronous on purpose: the isolate that calls this
/// is a worker whose next step is to decompress the bytes, and a frame is a
/// few hundred kilobytes at most.
///
/// A file holds the frames of one parity ([FrameParity]); a frame is found
/// in the file of its own parity, at its place among them.
///
/// At most [maxOpenFiles] files stay open, the least recently read closed
/// first: a file descriptor and a table per parity of an animation that plays
/// (two for one at full rate).
///
/// Native only (`dart:io`); one reader per isolate, never shared.
final class FrameFileReader {
  /// Creates a reader that keeps at most [maxOpenFiles] files open.
  FrameFileReader({this.maxOpenFiles = 64})
    : assert(maxOpenFiles > 0, 'a reader keeps at least one file open');

  /// How many files stay open at once.
  final int maxOpenFiles;

  // Insertion order is recency: a read moves its file to the end.
  final LinkedHashMap<String, _OpenFile> _open = LinkedHashMap();

  /// The bytes of [frame], or null when its file is missing, is not a
  /// well-formed file for its key and the frame's parity, or has no such
  /// frame. Never throws for a
  /// file's content or absence; a file that fails is closed, so the next read
  /// opens it afresh (it may have been written again meanwhile).
  Uint8List? read(CachedFrameFile frame) {
    if (frame.index < 0) return null;
    final file = _openFile(frame.path, frame.key, FrameParity.of(frame.index));
    if (file == null) return null;
    final table = file.table;
    final slot = FrameParity.slotOf(frame.index);
    if (slot >= table.frameCount) {
      forget(frame.path);
      return null;
    }
    final length = table.lengthOf(slot);
    try {
      final bytes = Uint8List(length);
      file.handle.setPositionSync(table.startOf(slot));
      if (file.handle.readIntoSync(bytes) != length) {
        forget(frame.path);
        return null;
      }
      return bytes;
    } on FileSystemException {
      forget(frame.path);
      return null;
    }
  }

  /// Closes the file at [path] if it is open: its frames turned out damaged,
  /// or it is to be deleted. Unknown paths are fine.
  void forget(String path) {
    final file = _open.remove(path);
    if (file == null) return;
    try {
      file.handle.closeSync();
    } on FileSystemException {
      // Closing is all that was asked; a handle that will not close is gone
      // from the reader either way.
    }
  }

  /// Closes every open file. The reader stays usable.
  void close() => List.of(_open.keys).forEach(forget);

  _OpenFile? _openFile(String path, FrameCacheKey key, FrameParity parity) {
    final known = _open.remove(path);
    if (known != null) {
      // A file reopened under another key or parity is damage, not a second
      // entry.
      if (known.key != key || known.parity != parity) {
        _closeQuietly(known.handle);
        return null;
      }
      return _open[path] = known;
    }
    RandomAccessFile? handle;
    try {
      handle = File(path).openSync();
      final length = handle.lengthSync();
      final fixed = handle.readSync(FrameCacheCodec.fixedHeaderBytes);
      final headerLength = FrameCacheCodec.headerLength(
        key,
        parity,
        fixed,
        length,
      );
      if (headerLength == null) {
        _closeQuietly(handle);
        return null;
      }
      final header = Uint8List(headerLength)..setAll(0, fixed);
      handle.readIntoSync(header, fixed.length);
      final table = FrameCacheCodec.table(
        key,
        parity,
        header,
        length,
        maxFrameBytes: _maxFrameBytes(key),
      );
      if (table == null) {
        _closeQuietly(handle);
        return null;
      }
      while (_open.length >= maxOpenFiles) {
        forget(_open.keys.first);
      }
      return _open[path] = _OpenFile(handle, key, parity, table);
    } on FileSystemException {
      if (handle != null) _closeQuietly(handle);
      return null;
    }
  }

  static void _closeQuietly(RandomAccessFile handle) {
    try {
      handle.closeSync();
    } on FileSystemException {
      // See forget.
    }
  }

  /// The longest a compressed frame of [key] can be: lz4's worst case for
  /// the raw region, with room for a codec header. A table that claims more
  /// is damage, and is refused before anything that large is allocated.
  static int _maxFrameBytes(FrameCacheKey key) {
    final raw = key.width * key.height * 4;
    return raw + raw ~/ 255 + 64;
  }
}

final class _OpenFile {
  _OpenFile(this.handle, this.key, this.parity, this.table);

  final RandomAccessFile handle;
  final FrameCacheKey key;
  final FrameParity parity;
  final FrameFileTable table;
}

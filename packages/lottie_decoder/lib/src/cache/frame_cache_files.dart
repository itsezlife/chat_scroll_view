import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// What a scan found for one cached animation.
@immutable
final class FrameCacheFileInfo {
  /// Creates the description of a file.
  const FrameCacheFileInfo({
    required this.stem,
    required this.bytes,
    required this.modified,
  });

  /// The file name without extension: `FrameCacheKey.toFileStem`.
  final String stem;

  /// Its size.
  final int bytes;

  /// When it was last written or used, as the cache's clock told it.
  final DateTime modified;
}

/// The files of one [FrameCache] directory: the only place that touches the
/// file system, so the cache's rules (budgets, recency, damage) are read
/// without any of its mechanics.
///
/// An entry is `<stem>.frames`. A write goes to
/// `<stem>.frames.<pid>.<n>.<random>.tmp` and is renamed into place, so a process that dies mid-write leaves a temp file and
/// never a partial entry under a real name. Temp files are not entries: [scan]
/// deletes them. The directory belongs to one cache at a time; a second cache
/// sharing it could have its in-flight temp file swept.
///
/// [FrameCache]: package:lottie_decoder/lottie_decoder.dart
class FrameCacheFiles {
  /// Creates the files of [directory], which is created on the first write.
  FrameCacheFiles(this.directory);

  /// Where the entries live.
  final Directory directory;

  static const String _entryExtension = '.frames';
  static const String _tempExtension = '.tmp';

  // One name per write: two writes of one stem that overlap must not share a
  // temp file, or the rename could publish bytes of both. The counter keeps
  // the writes of this process apart, the process id the processes that share
  // a directory, and the random part the case where a pid is reused or a
  // container makes every process pid 1.
  static int _nextTemp = 0;
  static final Random _random = Random();

  static String _tempSuffix() {
    final nonce = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '.$pid.${_nextTemp++}.$nonce$_tempExtension';
  }

  File _entry(String stem) =>
      File('${directory.path}${Platform.pathSeparator}$stem$_entryExtension');

  /// Lists the entries and deletes leftover temp files. An absent directory
  /// holds nothing.
  Future<List<FrameCacheFileInfo>> scan() async {
    final infos = <FrameCacheFileInfo>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.endsWith(_tempExtension)) {
          await entity.delete();
        } else if (name.endsWith(_entryExtension)) {
          // Synchronous: one stat per file in a one-off scan, and the async
          // form is the slow one on the platforms this runs on.
          final stat = entity.statSync();
          infos.add(
            FrameCacheFileInfo(
              stem: name.substring(0, name.length - _entryExtension.length),
              bytes: stat.size,
              modified: stat.modified,
            ),
          );
        }
      }
    } on PathNotFoundException {
      // Nothing was ever written.
    }
    return infos;
  }

  /// The bytes of the entry [stem], or null when there is none or when it is
  /// longer than [maxBytes]: the size is asked first, so a file that grew
  /// since the scan (or was swapped for a huge one) is never read whole.
  Future<Uint8List?> read(String stem, {required int maxBytes}) async {
    final file = _entry(stem);
    try {
      if (await file.length() > maxBytes) return null;
      return await file.readAsBytes();
    } on PathNotFoundException {
      return null;
    }
  }

  /// Writes the entry [stem] atomically and stamps it [modified].
  ///
  /// Returns why the stamp failed, or null. The entry is published before it
  /// is stamped, so a stamp that fails (a file system without timestamps) is
  /// not a failed write: the file is there, and only its recency on disk is
  /// off. The caller decides whether to tell anyone.
  Future<FileSystemException?> write(
    String stem,
    Uint8List bytes, {
    required DateTime modified,
  }) async {
    await directory.create(recursive: true);
    final target = _entry(stem);
    final temp = File('${target.path}${_tempSuffix()}');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await publish(temp, target);
    } on Object {
      await discardTemp(temp);
      rethrow;
    }
    try {
      await stamp(target, modified);
    } on FileSystemException catch (e) {
      return e;
    }
    return null;
  }

  /// Sets the time of [target] to [modified].
  @protected
  Future<void> stamp(File target, DateTime modified) =>
      target.setLastModified(modified);

  /// Makes a complete [temp] the entry [target]: the one step that makes a
  /// write visible, and atomic where a rename within a directory is.
  @protected
  Future<void> publish(File temp, File target) => temp.rename(target.path);

  /// Removes a temp file left by a write that failed while the process lived.
  @protected
  Future<void> discardTemp(File temp) async {
    try {
      await temp.delete();
    } on PathNotFoundException {
      // Never created, or already gone.
    }
  }

  /// Stamps the entry [stem] used at [modified].
  Future<void> touch(String stem, DateTime modified) async {
    try {
      await _entry(stem).setLastModified(modified);
    } on PathNotFoundException {
      // Evicted meanwhile.
    }
  }

  /// Deletes the entry [stem]; absent is fine.
  Future<void> delete(String stem) async {
    try {
      await _entry(stem).delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }
}

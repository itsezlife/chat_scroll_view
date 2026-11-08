import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:lottie_decoder/src/cache/frame_cache_files.dart';
import 'package:meta/meta.dart';

/// The [FrameCacheFiles] of one directory on a file system.
///
/// An entry is `<stem>.frames`. A write goes to
/// `<stem>.frames.<pid>.<n>.<random>.tmp` and is renamed into place, so a
/// process that dies mid-write leaves a temp file and never a partial entry
/// under a real name. Temp files are not entries: [scan] deletes them. The
/// directory belongs to one cache at a time; a second cache sharing it could
/// have its in-flight temp file swept.
class DirectoryFrameCacheFiles implements FrameCacheFiles {
  /// Creates the files of the directory at [path], which is created on the
  /// first write.
  DirectoryFrameCacheFiles(String path) : directory = Directory(path);

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
  static final Random _random = Random.secure();

  static String _tempSuffix() {
    final nonce = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '.$pid.${_nextTemp++}.$nonce$_tempExtension';
  }

  File _entry(String stem) =>
      File('${directory.path}${Platform.pathSeparator}$stem$_entryExtension');

  @override
  Future<List<FrameCacheFileInfo>> scan() async {
    final infos = <FrameCacheFileInfo>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.endsWith(_tempExtension)) {
          await discardTemp(entity);
        } else if (name.endsWith(_entryExtension)) {
          // Synchronous: one stat per file in a one-off scan, and the async
          // form is the slow one on the platforms this runs on.
          final stat = entity.statSync();
          // Gone since the listing (another process, or an eviction): not an
          // entry, and not a reason to give up on the others.
          if (stat.type == FileSystemEntityType.notFound) continue;
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

  @override
  String pathOf(String stem) => _entry(stem).path;

  @override
  Future<FileSystemException?> write(
    String stem,
    List<Uint8List> chunks, {
    required DateTime modified,
  }) async {
    await directory.create(recursive: true);
    final target = _entry(stem);
    final temp = File('${target.path}${_tempSuffix()}');
    try {
      final sink = await temp.open(mode: FileMode.writeOnly);
      try {
        for (final chunk in chunks) {
          await sink.writeFrom(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
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

  @override
  Future<void> touch(String stem, DateTime modified) async {
    try {
      await _entry(stem).setLastModified(modified);
    } on PathNotFoundException {
      // Evicted meanwhile.
    }
  }

  @override
  Future<void> delete(String stem) async {
    try {
      await _entry(stem).delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }
}

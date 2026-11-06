import 'dart:io';
import 'dart:typed_data';

import 'package:lottie_decoder/src/cache/frame_cache_files.dart';
import 'package:meta/meta.dart';

/// The [FrameCacheFiles] of one directory on a file system.
///
/// An entry is `<stem>.frames`. A write goes to `<stem>.<n>.tmp` and is
/// renamed into place, so a process that dies mid-write leaves a temp file and
/// never a partial entry under a real name. Temp files are not entries: [scan]
/// deletes them. The directory belongs to one cache at a time; a second cache
/// sharing it could have its in-flight temp file swept.
///
class DirectoryFrameCacheFiles implements FrameCacheFiles {
  /// Creates the files of the directory at [path], which is created on the
  /// first write.
  DirectoryFrameCacheFiles(String path) : directory = Directory(path);

  /// Where the entries live.
  final Directory directory;

  static const String _entryExtension = '.frames';
  static const String _tempExtension = '.tmp';

  // One name per write: two writes of one stem that overlap must not share a
  // temp file, or the rename could publish bytes of both.
  static int _nextTemp = 0;

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

  @override
  Future<Uint8List?> read(String stem) async {
    try {
      return await _entry(stem).readAsBytes();
    } on PathNotFoundException {
      return null;
    }
  }

  @override
  Future<void> write(
    String stem,
    Uint8List bytes, {
    required DateTime modified,
  }) async {
    await directory.create(recursive: true);
    final target = _entry(stem);
    final temp = File('${target.path}.${_nextTemp++}$_tempExtension');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await publish(temp, target);
      await target.setLastModified(modified);
    } on Object {
      await discardTemp(temp);
      rethrow;
    }
  }

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

/// The files of the directory at [path].
FrameCacheFiles openFrameCacheFiles(String path) =>
    DirectoryFrameCacheFiles(path);

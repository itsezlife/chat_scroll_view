import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chat_scroll_view_example/src/features/chat/data/byte_cache.dart';

/// The VM hook behind [ByteCache.directory]: a [ByteCache] of one file per
/// name in [directory].
ByteCache? $directoryByteCache(String directory) =>
    _DirectoryByteCache(Directory(directory));

// No index and no budget: the folder is a tier of the media store, which
// removes files by when they were last used, so a read stamps its file and a
// write is a fresh one. A write goes to a temporary file renamed into place,
// so a crash never leaves half a file under a name (an orphaned temporary
// file ages out of the store like any other).
final class _DirectoryByteCache implements ByteCache {
  _DirectoryByteCache(this._directory);

  final Directory _directory;
  Future<bool>? _made;

  @override
  Future<Uint8List?> read(String name) async {
    final file = _file(name);
    try {
      final bytes = await file.readAsBytes();
      unawaited(
        file.setLastModified(DateTime.now()).then((_) {}, onError: (_) {}),
      );
      return bytes;
    } on FileSystemException {
      // Never written, or removed by the store: a miss.
      return null;
    }
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    if (!await (_made ??= _make())) return;
    final file = _file(name);
    try {
      final temporary = File('${file.path}.part');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } on FileSystemException {
      return;
    }
  }

  File _file(String name) => File('${_directory.path}/$name');

  // False when the folder cannot be made: the cache then keeps nothing.
  Future<bool> _make() async {
    try {
      await _directory.create(recursive: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

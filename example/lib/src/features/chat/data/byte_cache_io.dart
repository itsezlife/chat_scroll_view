import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:chat_scroll_view_example/src/features/chat/data/byte_cache.dart';

/// A [ByteCache] of one file per name in [directory].
ByteCache? directoryByteCache(String directory, {required int budgetBytes}) =>
    _DirectoryByteCache(Directory(directory), budgetBytes);

// The files' sizes are indexed once, on first use, oldest modified first; a
// read touches its file, so the order survives a restart. A write goes to a
// temporary file renamed into place, so a crash never leaves half a file
// under a name.
final class _DirectoryByteCache implements ByteCache {
  _DirectoryByteCache(this._directory, this._budget)
    : assert(_budget > 0, 'keeps something');

  final Directory _directory;
  final int _budget;
  final LinkedHashMap<String, int> _sizes = LinkedHashMap();
  var _total = 0;
  Future<bool>? _indexed;

  @override
  Future<Uint8List?> read(String name) async {
    if (!await (_indexed ??= _index())) return null;
    final size = _sizes.remove(name);
    if (size == null) return null;
    final file = _file(name);
    try {
      final bytes = await file.readAsBytes();
      _sizes[name] = size;
      unawaited(
        file.setLastModified(DateTime.now()).then((_) {}, onError: (_) {}),
      );
      return bytes;
    } on FileSystemException {
      _total -= size;
      return null;
    }
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    if (!await (_indexed ??= _index())) return;
    final file = _file(name);
    try {
      final temporary = File('${file.path}.part');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } on FileSystemException {
      return;
    }
    _total += bytes.length - (_sizes.remove(name) ?? 0);
    _sizes[name] = bytes.length;
    while (_total > _budget && _sizes.length > 1) {
      final oldest = _sizes.keys.first;
      _total -= _sizes.remove(oldest)!;
      try {
        await _file(oldest).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }

  File _file(String name) => File('${_directory.path}/$name');

  // False when the folder cannot be made: the cache then keeps nothing.
  Future<bool> _index() async {
    try {
      await _directory.create(recursive: true);
      final found = <(String, int, DateTime)>[];
      await for (final entry in _directory.list()) {
        if (entry is! File) continue;
        if (entry.path.endsWith('.part')) {
          // A write a crash interrupted.
          await entry.delete();
          continue;
        }
        final stat = entry.statSync();
        found.add((entry.uri.pathSegments.last, stat.size, stat.modified));
      }
      found.sort((a, b) => a.$3.compareTo(b.$3));
      for (final (name, size, _) in found) {
        _sizes[name] = size;
        _total += size;
      }
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

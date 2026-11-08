import 'dart:io';
import 'dart:isolate';

/// The VM hook behind `MediaDiskCache.sweep`: removes the files under [root]
/// last used before [keepFor] ago, then, with [limitBytes], the least
/// recently used of the rest until they fit, sparing any used within [inUse]
/// of [now].
///
/// The walk runs in an isolate of its own: listing and stating every file of
/// a month of media is blocking calls, milliseconds to seconds of them, which
/// on the UI isolate would be dropped frames. A file that cannot be stated or
/// removed is left for the next sweep; a tier that finds one of its files
/// gone counts a miss and fetches or renders it again.
Future<void> $sweepMediaFolder(
  String root, {
  required DateTime now,
  required Duration keepFor,
  required int? limitBytes,
  required Duration inUse,
}) => Isolate.run(
  () => _sweep(
    root,
    now: now,
    keepFor: keepFor,
    limitBytes: limitBytes,
    inUse: inUse,
  ),
  debugName: 'media disk sweep',
);

void _sweep(
  String root, {
  required DateTime now,
  required Duration keepFor,
  required int? limitBytes,
  required Duration inUse,
}) {
  final List<FileSystemEntity> entries;
  try {
    entries = Directory(root).listSync(recursive: true, followLinks: false);
  } on FileSystemException {
    // Never made (nothing kept yet), or unreadable: nothing to sweep.
    return;
  }
  final expired = now.subtract(keepFor);
  final kept = <(File, int, DateTime)>[];
  for (final entry in entries) {
    if (entry is! File) continue;
    final stat = entry.statSync();
    // Gone since the listing: a tier replaced or dropped it.
    if (stat.type == FileSystemEntityType.notFound) continue;
    if (stat.modified.isBefore(expired)) {
      _remove(entry);
    } else {
      kept.add((entry, stat.size, stat.modified));
    }
  }
  if (limitBytes == null) return;
  var total = kept.fold<int>(0, (sum, file) => sum + file.$2);
  kept.sort((a, b) => a.$3.compareTo(b.$3));
  final busy = now.subtract(inUse);
  for (final (file, size, used) in kept) {
    if (total <= limitBytes) return;
    // Oldest first: once one is in use, so is every one after it. A file
    // used a moment ago may be a write landing (its temporary file) or a
    // read under way; the next sweep weighs it again.
    if (!used.isBefore(busy)) return;
    if (_remove(file)) total -= size;
  }
}

// Whether [file] is gone now.
bool _remove(File file) {
  try {
    file.deleteSync();
    return true;
  } on PathNotFoundException {
    return true;
  } on FileSystemException {
    return false;
  }
}

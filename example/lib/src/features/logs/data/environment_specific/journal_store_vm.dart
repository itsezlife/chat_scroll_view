import 'dart:convert';
import 'dart:io';

import 'package:chat_scroll_view_example/src/features/logs/data/journal_store.dart';

/// The VM hook: a [FileJournalStore] under [directory], or memory when there
/// is none (the platform named no cache folder).
Future<JournalStore> $openJournalStore({
  required String? directory,
  required int capBytes,
}) async => switch (directory) {
  final directory? => FileJournalStore.open(
    Directory(directory),
    capBytes: capBytes,
  ),
  null => MemoryJournalStore(),
};

/// A [JournalStore] in two files of JSON lines that take turns: the current
/// one is appended to until the next write would take it past half the cap,
/// then it becomes the
/// previous one (the old previous one is deleted) and a new current one
/// starts.
///
/// So the files hold at most about the cap, and dropping the oldest lines is
/// one delete and one rename, never a rewrite of 20 MiB. A file trimmed from
/// its front in place would be rewritten on every pass past the cap, and a
/// kill in the middle of the rewrite would lose both halves.
final class FileJournalStore implements JournalStore {
  FileJournalStore._(this._previous, this._current, this._file, this._half);

  /// Opens the store under [directory], creating it when missing.
  static Future<FileJournalStore> open(
    Directory directory, {
    required int capBytes,
  }) async {
    await directory.create(recursive: true);
    final previous = File('${directory.path}/$_previousName');
    final current = File('${directory.path}/$_currentName');
    return FileJournalStore._(
      previous,
      current,
      await current.open(mode: FileMode.append),
      capBytes ~/ 2,
    );
  }

  static const _previousName = 'journal.0.jsonl';
  static const _currentName = 'journal.1.jsonl';

  final File _previous;
  final File _current;
  final int _half;
  RandomAccessFile? _file;

  @override
  bool get isPersistent => true;

  @override
  Future<List<String>> read() async => [
    for (final file in [_previous, _current])
      if (file.existsSync())
        // A kill mid-line leaves bytes that are not UTF-8; the journal drops
        // the line they are in.
        ...const LineSplitter()
            .convert(
              utf8.decode(await file.readAsBytes(), allowMalformed: true),
            )
            .where((line) => line.isNotEmpty),
  ];

  @override
  void append(List<String> lines) {
    if (lines.isEmpty) return;
    final bytes = utf8.encode('${lines.join('\n')}\n');
    final length = switch (_file) {
      final file? => file.lengthSync(),
      null => throw StateError('The journal store is closed.'),
    };
    // Turned before the write that would take the current file past half,
    // so neither file holds more than half (a batch larger than half alone
    // aside).
    if (length > 0 && length + bytes.length > _half) _turn();
    _file!.writeFromSync(bytes);
  }

  void _turn() {
    _file!.closeSync();
    _file = null;
    if (_previous.existsSync()) _previous.deleteSync();
    _current.renameSync(_previous.path);
    _file = _current.openSync(mode: FileMode.append);
  }

  @override
  Future<void> close() async {
    final file = _file;
    _file = null;
    await file?.close();
  }
}

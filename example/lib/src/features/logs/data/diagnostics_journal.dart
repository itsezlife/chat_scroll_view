import 'dart:async';
import 'dart:collection' show Queue;
import 'dart:convert';

import 'package:chat_scroll_view_example/src/features/logs/data/journal_store.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_record.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:mpx_core/mpx_core.dart' show MpxDiagnostics, MpxEvent;

/// What the journal reports about itself.
enum JournalOp implements DiagnosticOp {
  /// The journal restored what the previous run kept and records from now.
  opened,

  /// A file of the journal went out through the share sheet.
  exported,

  /// Sharing the export failed.
  exportFailed,

  /// The store refused a write; the journal keeps recording in memory only.
  storeFailed,
}

/// Every diagnostics event of the process, newest last, in a ring of
/// [capBytes] kept in memory and in a [JournalStore], so the minutes before a
/// kill are there at the next start.
///
/// The host routes the policies into it once at start ([chatDiagnostics],
/// [mediaDiagnostics], or [bytesDiagnostics] for a bytes cache not bridged
/// into the media side's). Lines go to the store in batches, at most
/// [batchInterval] after they arrive; a warning or an error is written with
/// everything before it before [add] returns, since it is the event a kill
/// right after would otherwise take with it.
///
/// It never reports from [add]: its own events go through
/// `ChatDiagnostics.current`, which routes back into [add], so a report from
/// there would loop.
final class DiagnosticsJournal with ChangeNotifier {
  /// A journal over [store], empty until [restore].
  DiagnosticsJournal({
    required JournalStore store,
    this.capBytes = defaultCapBytes,
    this.batchInterval = const Duration(seconds: 1),
    DateTime Function() clock = DateTime.now,
  }) : _store = store,
       _clock = clock;

  /// A journal over memory alone, for a host that keeps no file (tests).
  DiagnosticsJournal.memory({int capBytes = defaultCapBytes})
    : this(store: MemoryJournalStore(), capBytes: capBytes);

  /// The default ring: 20 MiB, about a day of a busy chat's events.
  static const defaultCapBytes = 20 * 1024 * 1024;

  /// The most the records take, as the store's lines; the oldest go past it.
  final int capBytes;

  /// The longest a line waits before it is written.
  final Duration batchInterval;

  final JournalStore _store;
  final DateTime Function() _clock;
  final Queue<(JournalRecord, int)> _records = Queue();
  final List<String> _$pending = [];
  Timer? _$batch;
  int _$bytes = 0;
  bool _$restored = false;
  bool _$storeFailed = false;
  bool _$disposed = false;

  /// The records, oldest first.
  Iterable<JournalRecord> get records => _records.map((entry) => entry.$1);

  /// How many records there are.
  int get length => _records.length;

  /// The records' size as lines, in bytes.
  int get sizeBytes => _$bytes;

  /// Whether the records outlive the process.
  bool get isPersistent => _store.isPersistent && !_$storeFailed;

  /// The chat packages' policy, into this journal.
  ChatDiagnostics get chatDiagnostics => ChatDiagnostics.onEvent(addChatEvent);

  /// The bytes cache's policy, into this journal.
  BytesDiagnostics get bytesDiagnostics =>
      BytesDiagnostics.onEvent(addBytesEvent);

  /// The media side's policy, into this journal.
  MpxDiagnostics get mediaDiagnostics => MpxDiagnostics.onEvent(addMediaEvent);

  /// Records a chat package's [event].
  void addChatEvent(ChatEvent event) => add(JournalRecord.fromChatEvent(event));

  /// Records the bytes cache's [event], stamped now.
  void addBytesEvent(BytesLogEvent event) =>
      add(JournalRecord.fromBytesEvent(event, time: _clock()));

  /// Records the media side's [event].
  void addMediaEvent(MpxEvent event) => add(JournalRecord.fromMpxEvent(event));

  /// Records [record], dropping the oldest past [capBytes].
  void add(JournalRecord record) {
    if (_$disposed) return;
    final line = record.encode();
    _push(record, line);
    _$pending.add(line);
    if (record.level.index >= ChatEventLevel.warning.index) {
      flush();
    } else {
      _$batch ??= Timer(batchInterval, flush);
    }
    notifyListeners();
  }

  /// Reads what the previous runs kept into the journal, before what arrived
  /// since it was made, then reports [JournalOp.opened] with the count.
  ///
  /// Lines that do not read as records (the torn line of a kill mid-write)
  /// are skipped and counted. Once only; a second call restores nothing.
  Future<int> restore() async {
    if (_$restored) return 0;
    _$restored = true;
    final lines = await _store.read();
    final live = List.of(_records);
    _records.clear();
    _$bytes = 0;
    var restored = 0;
    var skipped = 0;
    for (final line in lines) {
      switch (JournalRecord.tryParse(line)) {
        case final record?:
          _push(record, line);
          restored++;
        case null:
          skipped++;
      }
    }
    for (final (record, bytes) in live) {
      _records.add((record, bytes));
      _$bytes += bytes;
      _trim();
    }
    if (!_$disposed) notifyListeners();
    ChatDiagnostics.current.emit(
      ChatEventLevel.info,
      ChatEventCategory.diagnostics,
      JournalOp.opened,
      fields: () => {
        'restored': restored,
        'skipped': skipped,
        'kept': _records.length,
        'bytes': _$bytes,
        'capBytes': capBytes,
        'persistent': isPersistent,
      },
    );
    return restored;
  }

  /// Writes the lines waiting for the next batch now.
  void flush() {
    _$batch?.cancel();
    _$batch = null;
    if (_$pending.isEmpty) return;
    final lines = List.of(_$pending);
    _$pending.clear();
    if (_$storeFailed) return;
    try {
      _store.append(lines);
    } on Object catch (error, stackTrace) {
      // Switched off before the report: the report is a warning, which
      // flushes, and a store that failed once would fail it again.
      _$storeFailed = true;
      ChatDiagnostics.current.emit(
        ChatEventLevel.warning,
        ChatEventCategory.diagnostics,
        JournalOp.storeFailed,
        fields: () => {'lines': lines.length},
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Writes what is waiting and releases the store.
  Future<void> close() async {
    flush();
    await _store.close();
  }

  void _push(JournalRecord record, String line) {
    // The line and its newline, as the store holds it.
    final bytes = utf8.encode(line).length + 1;
    _records.add((record, bytes));
    _$bytes += bytes;
    _trim();
  }

  void _trim() {
    while (_$bytes > capBytes && _records.length > 1) {
      _$bytes -= _records.removeFirst().$2;
    }
  }

  @override
  void dispose() {
    if (_$disposed) return;
    flush();
    _$disposed = true;
    unawaited(_store.close());
    super.dispose();
  }
}

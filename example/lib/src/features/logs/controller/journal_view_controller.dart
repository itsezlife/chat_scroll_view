import 'dart:async';
import 'dart:convert';

import 'package:chat_scroll_view_example/src/features/logs/data/diagnostics_journal.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_export.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_record.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_view.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Rect;

/// An export file on its way out: its name, its bytes and their type.
typedef JournalExportFile = ({String name, Uint8List bytes, String mimeType});

/// Hands [file] to the platform's share sheet, anchored at [origin] where the
/// platform asks for one (an iPad's popover).
typedef JournalShare =
    Future<void> Function(JournalExportFile file, {Rect? origin});

/// Projects a [DiagnosticsJournal] into the Logs screen: the filter, the
/// paused list, the export.
///
/// A plain [ChangeNotifier], not a `control` `StateController`: the
/// controller observer reports every state change as an event, the event
/// lands in the journal, and the journal would notify this controller again,
/// an endless loop.
final class JournalViewController with ChangeNotifier {
  /// Starts projecting [journal] through [filter]; journal changes are
  /// applied at most once per [refreshInterval].
  JournalViewController({
    required DiagnosticsJournal journal,
    required JournalShare share,
    JournalFilter? filter,
    this.refreshInterval = const Duration(milliseconds: 250),
    DateTime Function() clock = DateTime.now,
  }) : _journal = journal,
       _share = share,
       _clock = clock,
       _filter = filter ?? JournalFilter.all() {
    _snapshot = JournalSnapshot.of(_journal.records, _filter);
    _$anchor = _journal.records.lastOrNull;
    _journal.addListener(_onJournalChanged);
  }

  final DiagnosticsJournal _journal;
  final JournalShare _share;
  final DateTime Function() _clock;

  /// Longest delay between a journal change and the list showing it.
  final Duration refreshInterval;

  Timer? _$refresh;
  JournalFilter _filter;
  late JournalSnapshot _snapshot;

  /// Newest record when [_snapshot] was taken; records after it are new.
  JournalRecord? _$anchor;
  bool _paused = false;
  int _newCount = 0;
  bool _$exporting = false;
  bool _$disposed = false;

  /// What the list shows now.
  JournalSnapshot get snapshot => _snapshot;

  /// The active filter.
  JournalFilter get filter => _filter;

  /// Whether journal changes are held back so the list stays still.
  bool get isPaused => _paused;

  /// Records that arrived while paused and pass the filter.
  int get newCount => _newCount;

  /// Whether an export is on its way to the share sheet.
  bool get isExporting => _$exporting;

  /// Holds the list still; new records only raise [newCount].
  void pause() {
    if (_paused) return;
    _paused = true;
    notifyListeners();
  }

  /// Shows everything that arrived while paused.
  void resume() {
    if (!_paused) return;
    _paused = false;
    _refresh();
  }

  /// Turns [level] on or off.
  void toggleLevel(ChatEventLevel level) =>
      _setFilter(_filter.toggleLevel(level));

  /// Shows only [level], or every level when it is already the only one.
  void soloLevel(ChatEventLevel level) => _setFilter(_filter.soloLevel(level));

  /// Shows only [category], or every one when it is already the only one.
  void soloCategory(String category) =>
      _setFilter(_filter.soloCategory(category));

  /// Shows only the records whose [kind] is [id]; blank drops the id.
  void filterById(JournalIdKind kind, String id) =>
      _setFilter(_filter.withId(kind, id));

  /// Shares the records that pass the filter as a file.
  ///
  /// A tap while an export is on its way is dropped: the share sheet takes a
  /// moment to come up, and a second tap meanwhile would build and share a
  /// second file (or, on some platforms, fail because a sheet is already
  /// up).
  Future<void> export({Rect? origin}) async {
    if (_$exporting) return;
    _$exporting = true;
    notifyListeners();
    // What passes the filter now, not the last refresh: the list may be
    // paused, or a refresh not yet due.
    final records = JournalSnapshot.of(_journal.records, _filter).visible;
    final exportedAt = _clock();
    try {
      final bytes = utf8.encode(
        JournalExport.encode(
          records,
          JournalExportHeader.ofThisProcess(
            exportedAt: exportedAt,
            filter: _filter.toJson(),
            persistent: _journal.isPersistent,
          ),
        ),
      );
      await _share((
        name: JournalExport.fileName(exportedAt),
        bytes: bytes,
        mimeType: 'application/x-ndjson',
      ), origin: origin);
      ChatDiagnostics.current.emit(
        ChatEventLevel.info,
        ChatEventCategory.diagnostics,
        JournalOp.exported,
        fields: () => {'records': records.length, 'bytes': bytes.length},
      );
    } on Object catch (error, stackTrace) {
      ChatDiagnostics.current.emit(
        ChatEventLevel.error,
        ChatEventCategory.diagnostics,
        JournalOp.exportFailed,
        fields: () => {'records': records.length},
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _$exporting = false;
      if (!_$disposed) notifyListeners();
    }
  }

  void _setFilter(JournalFilter filter) {
    _filter = filter;
    _refresh();
  }

  void _onJournalChanged() =>
      _$refresh ??= Timer(refreshInterval, _onRefreshDue);

  void _onRefreshDue() {
    _$refresh = null;
    if (!_paused) return _refresh();
    final count = _countNew();
    if (count == _newCount) return;
    _newCount = count;
    notifyListeners();
  }

  void _refresh() {
    _$refresh?.cancel();
    _$refresh = null;
    _snapshot = JournalSnapshot.of(_journal.records, _filter);
    _$anchor = _journal.records.lastOrNull;
    _newCount = 0;
    notifyListeners();
  }

  /// Walks back from the newest record to [_$anchor]. When the anchor left
  /// the ring, every record counts as new.
  int _countNew() {
    final records = _journal.records.toList();
    var count = 0;
    for (var i = records.length - 1; i >= 0; i--) {
      final record = records[i];
      if (identical(record, _$anchor)) break;
      if (_filter.accepts(record)) count++;
    }
    return count;
  }

  @override
  void dispose() {
    _$disposed = true;
    _journal.removeListener(_onJournalChanged);
    _$refresh?.cancel();
    super.dispose();
  }
}

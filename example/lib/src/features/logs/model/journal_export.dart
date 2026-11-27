import 'dart:convert';

import 'package:chat_scroll_view_example/src/common/environment_specific/host_environment.dart'
    as environment_specific;
import 'package:chat_scroll_view_example/src/features/logs/model/journal_record.dart';
import 'package:flutter/foundation.dart';

/// What an export says about where it was made, on its first line: enough to
/// read a device check's log without asking which build ran where.
@immutable
final class JournalExportHeader {
  /// A header.
  const JournalExportHeader({
    required this.exportedAt,
    required this.platform,
    required this.build,
    this.osVersion,
    this.filter = const {},
    this.persistent = false,
  });

  /// The header of this process: its platform, operating system version and
  /// build mode, stamped [exportedAt].
  factory JournalExportHeader.ofThisProcess({
    required DateTime exportedAt,
    Map<String, Object> filter = const {},
    bool persistent = false,
  }) => JournalExportHeader(
    exportedAt: exportedAt,
    platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
    osVersion: environment_specific.$operatingSystemVersion(),
    build: switch ((kReleaseMode, kProfileMode)) {
      (true, _) => 'release',
      (_, true) => 'profile',
      _ => 'debug',
    },
    filter: filter,
    persistent: persistent,
  );

  /// When the file was made.
  final DateTime exportedAt;

  /// The platform (`android`, `iOS`, `macOS`, `web`, ...).
  final String platform;

  /// The operating system's version, where it can be read.
  final String? osVersion;

  /// The build mode: `debug`, `profile` or `release`.
  final String build;

  /// The filter the records passed (`JournalFilter.toJson`).
  final Map<String, Object> filter;

  /// Whether the journal was on disk, so the records reach back past the
  /// last start.
  final bool persistent;

  /// The header line's object.
  Map<String, Object> toJson() => {
    'journal': JournalExport.formatVersion,
    'exportedAt': exportedAt.toIso8601String(),
    'platform': platform,
    'osVersion': ?osVersion,
    'build': build,
    'persistent': persistent,
    'filter': filter,
  };
}

/// The journal's export file: a header line, then one JSON line per record,
/// oldest first, as the journal's own store writes them.
///
/// JSON lines rather than a spreadsheet: a device check's log is read by
/// scripts (`jq`, `grep` by id) and by the journal's own record parser, and
/// every record already is one line.
abstract final class JournalExport {
  /// The version of the file's layout, in the header.
  static const formatVersion = 1;

  /// The file of [newestFirst] (the journal's order) under [header].
  static String encode(
    List<JournalRecord> newestFirst,
    JournalExportHeader header,
  ) {
    final buffer = StringBuffer(
      jsonEncode({...header.toJson(), 'records': newestFirst.length}),
    )..write('\n');
    for (final record in newestFirst.reversed) {
      buffer
        ..write(record.encode())
        ..write('\n');
    }
    return buffer.toString();
  }

  /// One record as indented JSON, for the clipboard.
  static String entryText(JournalRecord record) =>
      const JsonEncoder.withIndent('  ').convert(record.toJson());

  /// The file's name, stamped with [exportedAt]; sorts chronologically.
  static String fileName(DateTime exportedAt) {
    final t = exportedAt;
    return 'chat_log_${t.year}-${_pad2(t.month)}-${_pad2(t.day)}_'
        '${_pad2(t.hour)}-${_pad2(t.minute)}-${_pad2(t.second)}.jsonl';
  }
}

/// Locale-free journal timestamps: machine data, not prose.
extension JournalTimestampFormat on DateTime {
  /// Wall-clock time with milliseconds, e.g. `20:54:20.622`.
  String get clockTime =>
      '${_pad2(hour)}:${_pad2(minute)}:${_pad2(second)}.'
      '${millisecond.toString().padLeft(3, '0')}';

  /// Date and [clockTime], e.g. `2026-10-07 20:54:20.622`.
  String get journalDateTime =>
      '$year-${_pad2(month)}-${_pad2(day)} $clockTime';
}

String _pad2(int n) => n.toString().padLeft(2, '0');

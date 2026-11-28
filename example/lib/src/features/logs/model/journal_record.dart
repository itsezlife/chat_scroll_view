import 'dart:convert';

import 'package:content_model/content_model.dart';
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:meta/meta.dart';
import 'package:mpx_core/mpx_core.dart' show MpxEvent, MpxEventLevel;

/// Where a [JournalRecord] came from: each source has its own event type and
/// policy, and the journal holds them side by side so one log follows a
/// message from the composer to the bytes on disk.
enum JournalSource {
  /// The chat packages' `ChatDiagnostics`.
  chat,

  /// The bytes cache's `BytesDiagnostics`.
  bytes,

  /// The media side's `MpxDiagnostics`, the bytes cache's events among
  /// them (category `cache`, through mpx's cache bridge).
  media,
}

/// One diagnostics event as the journal keeps it: plain values only, so it
/// encodes to one JSON line and comes back after a restart unchanged.
///
/// Not a `ChatEvent`: the journal also holds events of the bytes cache and
/// the media side, whose categories and operations are not the chat's closed
/// enums. The category and the operation are kept by name, the level on the
/// chat's scale.
@immutable
final class JournalRecord {
  /// A record; [fields] holds numbers, booleans and strings only.
  JournalRecord({
    required this.time,
    required this.level,
    required this.source,
    required this.category,
    required this.op,
    this.correlation = ChatCorrelation.none,
    Map<String, Object> fields = const {},
    this.error,
    this.stackTrace,
  }) : fields = Map.unmodifiable(fields);

  /// The record of a chat package's [event].
  ///
  /// Enum fields are kept by name. The error is kept as its text with every
  /// URL cut to its host: an error message is the one place a URL path or a
  /// query could slip into an event (an HTTP exception names its URI).
  factory JournalRecord.fromChatEvent(ChatEvent event) => JournalRecord(
    time: event.time,
    level: event.level,
    source: JournalSource.chat,
    category: event.category.name,
    op: event.op.name,
    correlation: event.correlation,
    fields: {
      for (final MapEntry(:key, :value) in event.fields.entries)
        key: switch (value) {
          Enum(:final name) => name,
          _ => value,
        },
    },
    error: switch (event.error) {
      final error? => withoutUrlPaths('$error'),
      null => null,
    },
    stackTrace: _trace(event.stackTrace),
  );

  /// The record of the bytes cache's [event], stamped [time].
  ///
  /// The event's message is dropped: it names the cache key, which is the
  /// request's URL, and the error text of the failed write or fetch. What the
  /// journal keeps is the operation, the level and whether a stack came with
  /// it; the stack itself, which holds code locations only, is kept.
  factory JournalRecord.fromBytesEvent(
    BytesLogEvent event, {
    required DateTime time,
  }) => JournalRecord(
    time: time,
    level: switch (event.level) {
      BytesLogLevel.debug => ChatEventLevel.debug,
      BytesLogLevel.warning => ChatEventLevel.warning,
      BytesLogLevel.error => ChatEventLevel.error,
    },
    source: JournalSource.bytes,
    category: bytesCategory,
    op: event.op,
    stackTrace: _trace(event.stackTrace),
  );

  /// The record of the media side's [event].
  ///
  /// The job, item and media key become the record's ids; the tag, which is
  /// the host's own label, is kept as a field. The event's fields are plain
  /// and short already; the error is kept as text with URLs cut to their
  /// host, as for a chat event.
  factory JournalRecord.fromMpxEvent(MpxEvent event) => JournalRecord(
    time: event.time,
    level: switch (event.level) {
      MpxEventLevel.trace => ChatEventLevel.trace,
      MpxEventLevel.debug => ChatEventLevel.debug,
      MpxEventLevel.info => ChatEventLevel.info,
      MpxEventLevel.warning => ChatEventLevel.warning,
      MpxEventLevel.error => ChatEventLevel.error,
    },
    source: JournalSource.media,
    category: event.category,
    op: event.op.name,
    correlation: ChatCorrelation(
      jobId: event.jobId,
      mediaItemId: event.itemId,
      mediaKey: event.mediaKey?.encoded,
    ),
    fields: {...event.fields, 'tag': ?event.tag},
    error: switch (event.error) {
      final error? => withoutUrlPaths('$error'),
      null => null,
    },
    stackTrace: _trace(event.stackTrace),
  );

  /// Reads a record [toJson] wrote; null for a line that is not one (the
  /// torn last line of a process killed mid-write, a record of a newer
  /// format).
  static JournalRecord? tryParse(String line) {
    try {
      return switch (jsonDecode(line)) {
        {
              't': final int micros,
              'l': final String level,
              's': final String source,
              'c': final String category,
              'o': final String op,
            } &&
            final Map<String, Object?> json =>
          JournalRecord(
            time: DateTime.fromMicrosecondsSinceEpoch(micros),
            level: ChatEventLevel.values.byName(level),
            source: JournalSource.values.byName(source),
            category: category,
            op: op,
            correlation: switch (json['ids']) {
              final Map<String, Object?> ids => ChatCorrelation(
                chatId: ids['chatId'] as String?,
                scrollId: ids['scrollId'] as String?,
                clientMessageId: ids['clientMessageId'] as String?,
                mediaItemId: ids['mediaItemId'] as String?,
                mediaKey: ids['mediaKey'] as String?,
                jobId: ids['jobId'] as String?,
              ),
              _ => ChatCorrelation.none,
            },
            fields: switch (json['f']) {
              final Map<String, Object?> fields => {
                for (final MapEntry(:key, :value) in fields.entries)
                  key: ?_plain(value),
              },
              _ => const {},
            },
            error: json['e'] as String?,
            stackTrace: json['st'] as String?,
          ),
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  /// The category name of [JournalSource.bytes] records.
  static const bytesCategory = 'bytes';

  /// When it happened.
  final DateTime time;

  /// How much it matters.
  final ChatEventLevel level;

  /// Which diagnostics it came from.
  final JournalSource source;

  /// The area, by name: a `ChatEventCategory` name, or the source's own.
  final String category;

  /// What happened, by the operation's stable name.
  final String op;

  /// The chat, message, item or job it concerns.
  final ChatCorrelation correlation;

  /// Its facts: numbers, booleans and short strings.
  final Map<String, Object> fields;

  /// The failure's text, URLs cut to their host.
  final String? error;

  /// Where the failure was thrown.
  final String? stackTrace;

  /// The record as one compact JSON object, the line the journal writes.
  Map<String, Object> toJson() => {
    't': time.microsecondsSinceEpoch,
    'l': level.name,
    's': source.name,
    'c': category,
    'o': op,
    if (!correlation.isEmpty)
      'ids': {for (final (name, id) in correlation.entries) name: id},
    if (fields.isNotEmpty) 'f': fields,
    'e': ?error,
    'st': ?stackTrace,
  };

  /// [toJson] encoded.
  String encode() => jsonEncode(toJson());

  /// [text] with every URL reduced to its scheme and host.
  ///
  /// Events end up in files users share; a URL's path, query and fragment
  /// can carry what the user sent or a token.
  static String withoutUrlPaths(String text) =>
      text.replaceAllMapped(_url, (match) => '${match[1]}://${match[2]}');

  static final _url = RegExp(r'([a-zA-Z][a-zA-Z0-9+.-]*)://([^/\s?#]+)\S*');

  static Object? _plain(Object? value) => switch (value) {
    final num number => number,
    final bool flag => flag,
    final String text => text,
    _ => null,
  };

  static String? _trace(StackTrace? trace) => switch ('${trace ?? ''}'.trim()) {
    '' => null,
    final text => text,
  };

  @override
  String toString() =>
      'JournalRecord(${level.name} $category.$op, $correlation, $fields)';
}

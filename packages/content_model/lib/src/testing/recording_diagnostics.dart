import 'package:content_model/src/diagnostics/chat_diagnostics.dart';
import 'package:content_model/src/diagnostics/chat_event.dart';
import 'package:test/test.dart';

/// A diagnostics policy that keeps every event, for tests of the events a
/// path emits.
///
/// Enabled at every level, so a test sees the events a host's journal would.
/// Install it with [RecordingDiagnostics.install], which puts the previous
/// policy back after the test.
final class RecordingDiagnostics extends ChatDiagnosticsOnEvent {
  /// A recorder holding no events.
  RecordingDiagnostics() : this._(<ChatEvent>[]);

  RecordingDiagnostics._(List<ChatEvent> events)
    : _events = events,
      super(events.add);

  /// Installs a new recorder as [ChatDiagnostics.current] for the running
  /// test and returns it.
  ///
  /// The previous policy comes back in the test's tear-down, which runs
  /// whether the test passed or failed; call it inside a test or a `setUp`.
  factory RecordingDiagnostics.install() {
    final previous = ChatDiagnostics.current;
    addTearDown(() => ChatDiagnostics.current = previous);
    return ChatDiagnostics.current = RecordingDiagnostics();
  }

  final List<ChatEvent> _events;

  /// Every event reported, oldest first.
  List<ChatEvent> get events => List.unmodifiable(_events);

  /// The events of [category], oldest first.
  List<ChatEvent> whereCategory(ChatEventCategory category) => [
    for (final event in _events)
      if (event.category == category) event,
  ];

  /// The events of [op], oldest first.
  List<ChatEvent> whereOp(DiagnosticOp op) => [
    for (final event in _events)
      if (event.op == op) event,
  ];

  /// The events whose correlation holds every id given, oldest first.
  List<ChatEvent> whereCorrelated({
    String? chatId,
    String? scrollId,
    String? clientMessageId,
    String? mediaItemId,
    String? mediaKey,
    String? jobId,
  }) {
    final wanted = ChatCorrelation(
      chatId: chatId,
      scrollId: scrollId,
      clientMessageId: clientMessageId,
      mediaItemId: mediaItemId,
      mediaKey: mediaKey,
      jobId: jobId,
    ).entries.toList();
    return [
      for (final event in _events)
        if (wanted.every(event.correlation.entries.toList().contains)) event,
    ];
  }

  /// Forgets the events recorded so far.
  void clear() => _events.clear();
}

/// Matches one [ChatEvent] by the parts given; a part left out matches
/// anything, and `time` is never compared.
///
/// Each part is a value or a matcher, so `fields: containsPair('attempt', 2)`
/// checks one field and `fields: {'attempt': 2}` all of them.
Matcher isChatEvent({
  Object? level,
  Object? category,
  Object? op,
  Object? correlation,
  Object? fields,
  Object? error,
}) {
  var matcher = isA<ChatEvent>();
  if (level != null) {
    matcher = matcher.having((event) => event.level, 'level', level);
  }
  if (category != null) {
    matcher = matcher.having((event) => event.category, 'category', category);
  }
  if (op != null) {
    matcher = matcher.having((event) => event.op, 'op', op);
  }
  if (correlation != null) {
    matcher = matcher.having(
      (event) => event.correlation,
      'correlation',
      correlation,
    );
  }
  if (fields != null) {
    matcher = matcher.having((event) => event.fields, 'fields', fields);
  }
  if (error != null) {
    matcher = matcher.having((event) => event.error, 'error', error);
  }
  return matcher;
}

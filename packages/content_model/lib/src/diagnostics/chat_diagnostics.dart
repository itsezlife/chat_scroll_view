import 'dart:developer' as developer;

import 'package:content_model/src/diagnostics/chat_event.dart';
import 'package:meta/meta.dart';

/// Where [ChatDiagnostics.developer] writes a line: `dart:developer`'s `log`
/// unless a test passes its own.
typedef ChatDeveloperLog =
    void Function(
      String message, {
      required String name,
      required int level,
      Object? error,
      StackTrace? stackTrace,
      DateTime? time,
    });

/// Where chat packages' diagnostics events go: nowhere, the developer log, or
/// the host.
///
/// One policy per process, [current], set once by the host at start;
/// packages read it at the call site and take no diagnostics parameter, so
/// no constructor threads it through. A test that changes it restores it
/// (`RecordingDiagnostics.install` in `testing.dart` does), since a package's
/// tests share one process.
///
/// A call site reports through [emit], which checks [isEnabled] before it
/// builds the event's fields, so the silent default costs one check:
///
/// ```dart
/// ChatDiagnostics.current.emit(
///   ChatEventLevel.debug,
///   ChatEventCategory.capabilities,
///   CapabilitiesOp.denied,
///   correlation: ChatCorrelation(chatId: chatId),
///   fields: () => {'action': action.name},
/// );
/// ```
@immutable
sealed class ChatDiagnostics {
  const ChatDiagnostics();

  /// Reports nothing (the default).
  const factory ChatDiagnostics.silent() = ChatDiagnosticsSilent;

  /// Writes every event to the `dart:developer` log, under one name per
  /// category: `chat.<category>`, for example `chat.outbox`.
  ///
  /// [log] stands in for `dart:developer`'s `log` in tests.
  const factory ChatDiagnostics.developer({
    @visibleForTesting ChatDeveloperLog log,
  }) = ChatDiagnosticsDeveloper;

  /// Hands every event at [minLevel] or above to the host's [onEvent], which
  /// routes it (a journal, a crash reporter for warnings and errors).
  ///
  /// [onEvent] must not throw; a throw is swallowed so diagnostics never
  /// fail the path they describe.
  const factory ChatDiagnostics.onEvent(
    void Function(ChatEvent event) onEvent, {
    ChatEventLevel minLevel,
  }) = ChatDiagnosticsOnEvent;

  /// The process-wide policy; silent until the host sets one.
  static ChatDiagnostics current = const ChatDiagnostics.silent();

  /// Whether an event at [level] goes anywhere.
  ///
  /// A call site that builds more than [emit]'s field builder covers (a
  /// correlation from a lookup, say) checks this first.
  bool isEnabled(ChatEventLevel level);

  /// Sends [event] where this policy routes it, if its level is enabled.
  ///
  /// Never throws: a sink that throws is ignored, so a report inside a
  /// failure path (a `catchError`, an unawaited future) cannot raise a second,
  /// unhandled error over the first. Debug builds write the sink's failure
  /// to the `dart:developer` log (`chat.diagnostics`), so a broken sink is
  /// seen during development; release builds drop it.
  void report(ChatEvent event) {
    if (!isEnabled(event.level)) return;
    try {
      _deliver(event);
    } on Object catch (error, stackTrace) {
      // Not an assert: it would throw inside the failure path the event
      // describes, the second error this method exists to prevent. The log
      // is the sink of last resort.
      assert(() {
        developer.log(
          'A diagnostics sink threw on ${event.op.name}',
          name: 'chat.diagnostics',
          level: 1000,
          error: error,
          stackTrace: stackTrace,
        );
        return true;
      }(), 'unreachable');
    }
  }

  /// Reports an event stamped now, building [fields] only when [level] is
  /// enabled.
  void emit(
    ChatEventLevel level,
    ChatEventCategory category,
    DiagnosticOp op, {
    ChatCorrelation correlation = ChatCorrelation.none,
    Map<String, Object> Function()? fields,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!isEnabled(level)) return;
    report(
      ChatEvent(
        time: DateTime.now(),
        level: level,
        category: category,
        op: op,
        correlation: correlation,
        fields: fields?.call() ?? const {},
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  void _deliver(ChatEvent event);
}

/// [ChatDiagnostics.silent].
final class ChatDiagnosticsSilent extends ChatDiagnostics {
  /// The silent policy.
  const ChatDiagnosticsSilent();

  @override
  bool isEnabled(ChatEventLevel level) => false;

  @override
  void _deliver(ChatEvent event) {}
}

/// [ChatDiagnostics.developer].
final class ChatDiagnosticsDeveloper extends ChatDiagnostics {
  /// The developer-log policy.
  const ChatDiagnosticsDeveloper({this.log = developer.log});

  /// Where lines go.
  final ChatDeveloperLog log;

  @override
  bool isEnabled(ChatEventLevel level) => true;

  @override
  void _deliver(ChatEvent event) {
    final message = StringBuffer(event.op.name);
    for (final (name, id) in event.correlation.entries) {
      message.write(' $name=$id');
    }
    for (final MapEntry(:key, :value) in event.fields.entries) {
      final shown = switch (value) {
        Enum(:final name) => name,
        _ => value,
      };
      message.write(' $key=$shown');
    }
    log(
      message.toString(),
      name: 'chat.${event.category.name}',
      // The `package:logging` values the developer tools read.
      level: switch (event.level) {
        ChatEventLevel.trace => 300,
        ChatEventLevel.debug => 500,
        ChatEventLevel.info => 800,
        ChatEventLevel.warning => 900,
        ChatEventLevel.error => 1000,
      },
      error: event.error,
      stackTrace: event.stackTrace,
      time: event.time,
    );
  }
}

/// [ChatDiagnostics.onEvent].
///
/// Open to extension so the recorder in `testing.dart` can be one.
base class ChatDiagnosticsOnEvent extends ChatDiagnostics {
  /// Forwards every event at [minLevel] or above to [onEvent].
  const ChatDiagnosticsOnEvent(
    this.onEvent, {
    this.minLevel = ChatEventLevel.trace,
  });

  /// The host's callback.
  final void Function(ChatEvent event) onEvent;

  /// The lowest level forwarded.
  final ChatEventLevel minLevel;

  @override
  bool isEnabled(ChatEventLevel level) => level.index >= minLevel.index;

  @override
  void _deliver(ChatEvent event) => onEvent(event);
}

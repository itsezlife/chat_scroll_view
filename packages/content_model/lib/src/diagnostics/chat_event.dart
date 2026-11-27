import 'package:meta/meta.dart';

/// How much a [ChatEvent] matters, from the noisiest to the most severe.
///
/// The order is the threshold order: a policy enabled for [warning] is
/// enabled for [error] too.
enum ChatEventLevel {
  /// Per-frame or per-item detail: layouts computed, transitions started.
  trace,

  /// A decision worth following when a path misbehaves: a fallback taken, a
  /// tap dropped by an input guard.
  debug,

  /// A step of a path's normal life: a message queued, a viewer opened.
  info,

  /// A recoverable problem: a retry, a missing origin, an unknown kind drawn
  /// as a fallback.
  warning,

  /// A path that failed.
  error,
}

/// The area of the chat a [ChatEvent] belongs to.
///
/// Closed: a category is added by amending the diagnostics ADR, so a log can
/// be filtered by a set every reader knows.
enum ChatEventCategory {
  /// Chat capabilities: what a chat allows, and denials.
  capabilities,

  /// Message media: layout, cells, hits, the viewer.
  media,

  /// Link previews: resolving, cancelling, the card.
  linkPreview,

  /// Outgoing messages: the outbox and its publish jobs.
  outbox,

  /// The engine's provisional tail being rebased onto confirmed messages.
  rebase,

  /// Saving media to the device.
  save,

  /// Overlays over the chat, the scrim's phases among them.
  overlay,

  /// The host's diagnostics pipeline itself: its journal opening, restoring
  /// what a previous run kept, exporting, a store that failed.
  diagnostics,
}

/// What happened, as one value of an emitting package's closed operation
/// enum.
///
/// The shared leaf declares only this contract and no package's operations:
/// each package keeps its own enum implementing it, so adding a path touches
/// that package alone. Implementing [Enum] keeps operations closed (only an
/// enum can implement this) and gives each a stable `name`, the one logs and
/// filters use. An operation is never a free-form message.
abstract interface class DiagnosticOp implements Enum {}

/// The ids that let one chat, message, item or job be followed through every
/// package's events, and into the media side's events for the same job.
///
/// Every id is an opaque string: a media key goes in as its stable string
/// form, so this leaf knows no media type. None of them may carry user
/// content.
@immutable
final class ChatCorrelation {
  /// Ids of an event; each is optional.
  const ChatCorrelation({
    this.chatId,
    this.scrollId,
    this.clientMessageId,
    this.mediaItemId,
    this.mediaKey,
    this.jobId,
  });

  /// An event about no particular chat, message or item.
  static const none = ChatCorrelation();

  /// The chat.
  final String? chatId;

  /// The engine's id of the message.
  final String? scrollId;

  /// The id the client gave an outgoing message before the server confirmed
  /// it.
  final String? clientMessageId;

  /// A media item of a message, in its string form.
  final String? mediaItemId;

  /// The media key of an item's content, in its stable string form.
  final String? mediaKey;

  /// A publish job (the outbox) or a save job.
  final String? jobId;

  /// Whether no id is set.
  bool get isEmpty =>
      chatId == null &&
      scrollId == null &&
      clientMessageId == null &&
      mediaItemId == null &&
      mediaKey == null &&
      jobId == null;

  /// The set ids as `name=value` pairs, in a fixed order.
  Iterable<(String, String)> get entries sync* {
    if (chatId case final id?) yield ('chatId', id);
    if (scrollId case final id?) yield ('scrollId', id);
    if (clientMessageId case final id?) yield ('clientMessageId', id);
    if (mediaItemId case final id?) yield ('mediaItemId', id);
    if (mediaKey case final id?) yield ('mediaKey', id);
    if (jobId case final id?) yield ('jobId', id);
  }

  @override
  bool operator ==(Object other) =>
      other is ChatCorrelation &&
      other.chatId == chatId &&
      other.scrollId == scrollId &&
      other.clientMessageId == clientMessageId &&
      other.mediaItemId == mediaItemId &&
      other.mediaKey == mediaKey &&
      other.jobId == jobId;

  @override
  int get hashCode => Object.hash(
    chatId,
    scrollId,
    clientMessageId,
    mediaItemId,
    mediaKey,
    jobId,
  );

  @override
  String toString() =>
      'ChatCorrelation(${entries.map((e) => '${e.$1}: ${e.$2}').join(', ')})';
}

/// One structured diagnostics event a chat package reports through
/// `ChatDiagnostics`.
///
/// Equal by value, so a test can compare whole events.
@immutable
final class ChatEvent {
  /// An event; [fields] is copied and checked in debug builds.
  ChatEvent({
    required this.time,
    required this.level,
    required this.category,
    required this.op,
    this.correlation = ChatCorrelation.none,
    Map<String, Object> fields = const {},
    this.error,
    this.stackTrace,
  }) : assert(_fieldsProblem(fields) == null, _fieldsProblem(fields)),
       fields = Map.unmodifiable(fields);

  /// The longest string a field may hold: room for a reason, a code or a
  /// host, too short for a sentence of user text.
  static const maxStringFieldLength = 64;

  /// [value] cut to [maxStringFieldLength] characters: a host tag, a panel
  /// id or a type name that may run longer than a field holds.
  ///
  /// A call site whose string comes from outside the package clips it, so
  /// an event never fails its own assert on a host's long tag.
  static String clip(String value) => value.length <= maxStringFieldLength
      ? value
      : value.substring(0, maxStringFieldLength);

  /// When it happened.
  final DateTime time;

  /// How much it matters.
  final ChatEventLevel level;

  /// The area of the chat.
  final ChatEventCategory category;

  /// What happened.
  final DiagnosticOp op;

  /// The chat, message, item or job it concerns.
  final ChatCorrelation correlation;

  /// A few facts about it: sizes, counts, durations, attempts, reasons,
  /// codes.
  ///
  /// Values are numbers, booleans, enum values (logged by name) and strings
  /// of at most [maxStringFieldLength] characters; anything else, a nested
  /// map or a list among them, fails an assert.
  ///
  /// No user content, ever: no message text, captions, file names, page
  /// titles, URL paths, queries or fragments, tokens or credentials. A URL is
  /// reported by its host only. Events end up in files users export and
  /// share.
  final Map<String, Object> fields;

  /// The error of a failed path.
  final Object? error;

  /// Where [error] was thrown.
  final StackTrace? stackTrace;

  static String? _fieldsProblem(Map<String, Object> fields) {
    for (final MapEntry(:key, :value) in fields.entries) {
      switch (value) {
        case num() || bool() || Enum():
          continue;
        case String(:final length) when length <= maxStringFieldLength:
          continue;
        case String(:final length):
          return 'Field "$key" is a string of $length characters; a field '
              'holds at most $maxStringFieldLength, so user text cannot '
              'slip into an event.';
        default:
          return 'Field "$key" is a ${value.runtimeType}; fields hold only '
              'numbers, booleans, enum values and short strings.';
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ChatEvent ||
        other.time != time ||
        other.level != level ||
        other.category != category ||
        other.op != op ||
        other.correlation != correlation ||
        other.error != error ||
        other.stackTrace != stackTrace ||
        other.fields.length != fields.length) {
      return false;
    }
    for (final MapEntry(:key, :value) in fields.entries) {
      if (other.fields[key] != value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    time,
    level,
    category,
    op,
    correlation,
    Object.hashAllUnordered(
      fields.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    error,
    stackTrace,
  );

  @override
  String toString() =>
      'ChatEvent(${level.name} ${category.name}.${op.name}, $correlation, '
      'fields: $fields${switch (error) {
        final error? => ', error: $error',
        null => '',
      }})';
}

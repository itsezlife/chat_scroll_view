/// The dart-define keys the runner compiles into a build and the app reads.
///
/// Pure Dart, imported by both sides: the runner (`tool/chat_perf/`) and the
/// on-device suite. A key spelled in one place cannot drift between them.
library;

// ignore_for_file: implementation_imports, invalid_use_of_internal_member
// The engine's trace level key is defined once, beside the gate that reads it.
import 'package:chat_scroll_view/src/util/trace_section.dart' show TraceLevel;

/// The defines of a chat performance build.
abstract final class ChatPerfDefine {
  /// `impeller` or `skia`, recorded as given.
  static const String backend = 'CHAT_PERF_BACKEND';

  /// Comma-separated globs over scenario ids; empty runs all.
  static const String scenario = 'CHAT_PERF_SCENARIO';

  /// Messages in the seeded history.
  static const String history = 'CHAT_PERF_HISTORY';

  /// `true` runs the cold scenarios, one launch each.
  static const String cold = 'CHAT_PERF_COLD';

  /// `off` (the default), `on` or `pair`.
  static const String semantics = 'CHAT_PERF_SEMANTICS';

  /// `true` is the traced launch: scripted scenarios only, each captured on
  /// the timeline, for the structural counts.
  static const String traced = 'CHAT_PERF_TRACED';

  /// The engine's trace level (`off`, `phase`, `fine`); the traced launch
  /// sets `phase`.
  static const String engineTrace = TraceLevel.defineKey;
}

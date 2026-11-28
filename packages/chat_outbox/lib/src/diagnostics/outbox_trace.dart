import 'dart:developer' show Timeline, TimelineTask;

import 'package:meta/meta.dart';

/// This package's named timeline sections, in the engine's namespace
/// (`chat_scroll_view.<name>`), compiled in only with
/// `--dart-define=chat_scroll_view.trace=phase` (or `fine`).
@internal
enum OutboxTrace {
  /// One `watchJobs` update projected onto a chat's outgoing messages.
  project('outbox.project'),

  /// One call of the chat publisher, its conflict loop included.
  publish('outbox.publish');

  const OutboxTrace(String name) : label = 'chat_scroll_view.$name';

  /// The section's name on the timeline.
  final String label;

  static const String _define = String.fromEnvironment(
    'chat_scroll_view.trace',
  );

  /// Whether this build records sections; a constant, so an off build folds
  /// every call site away.
  static const bool enabled = _define == 'phase' || _define == 'fine';

  /// Runs [body] inside this section when tracing is on.
  T run<T>(T Function() body) {
    if (!enabled) return body();
    Timeline.startSync(label);
    try {
      return body();
    } finally {
      Timeline.finishSync();
    }
  }

  /// Runs [body], which spans frames, inside this section as an async task
  /// when tracing is on.
  Future<T> runAsync<T>(Future<T> Function() body) async {
    if (!enabled) return body();
    final task = TimelineTask()..start(label);
    try {
      return await body();
    } finally {
      task.finish();
    }
  }
}

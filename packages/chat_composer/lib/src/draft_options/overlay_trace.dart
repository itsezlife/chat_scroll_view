import 'dart:developer' show Timeline, TimelineTask;

import 'package:meta/meta.dart';

/// The draft options overlay's named timeline sections, in the engine's
/// namespace (`chat_scroll_view.<name>`), compiled in only with
/// `--dart-define=chat_scroll_view.trace=phase` (or `fine`).
///
/// Closed: a section is added here with the path it wraps. Call sites pass
/// a constant and nothing else, so an off build folds every call away and
/// allocates nothing; a closure-taking wrapper would allocate even when
/// tracing is off.
@internal
enum OverlayTrace {
  /// The scrim's capture of the window, around the owner's opening of its
  /// controller (synchronous: [begin] and [end]).
  scrimCapture('overlay.scrimCapture'),

  /// The scrim's CPU still, from the capture to the still made, failed or
  /// let go (made off the frame: [start] and [finish]).
  scrimStill('overlay.scrimStill'),

  /// The host's bubble builder drawing the live preview.
  previewBuild('overlay.previewBuild');

  const OverlayTrace(String name) : label = 'chat_scroll_view.$name';

  /// The section's name on the timeline.
  final String label;

  static const String _define = String.fromEnvironment(
    'chat_scroll_view.trace',
  );

  // A constant, so the gate folds away in a build without the define.
  static const bool _on = _define == 'phase' || _define == 'fine';

  /// Starts [section]; pair with [end] in the same synchronous scope.
  static void begin(OverlayTrace section) {
    if (!_on) return;
    Timeline.startSync(section.label);
  }

  /// Ends the section [begin] started.
  static void end(OverlayTrace section) {
    if (!_on) return;
    Timeline.finishSync();
  }

  /// Starts [section] as an asynchronous span; null when tracing is off.
  /// The owner keeps it and hands it to [finish].
  static TimelineTask? start(OverlayTrace section) {
    if (!_on) return null;
    return TimelineTask()..start(section.label);
  }

  /// Ends a span [start] returned; nothing for null.
  static void finish(TimelineTask? span) => span?.finish();
}

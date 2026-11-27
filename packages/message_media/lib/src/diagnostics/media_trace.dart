import 'dart:developer' show Timeline;

import 'package:meta/meta.dart';

/// This package's named timeline sections, in the engine's namespace
/// (`chat_scroll_view.<name>`), compiled in only with
/// `--dart-define=chat_scroll_view.trace=phase` (or `fine`).
///
/// Closed: a section is added here with the path it wraps. Call sites pass
/// a constant to [MediaTrace.begin] and [MediaTrace.end] and nothing else,
/// so an off build folds every call away and allocates nothing; a
/// closure-taking wrapper would allocate even when tracing is off.
@internal
enum MediaTrace {
  /// The layout step and the corner radii (`MessageMediaPolicy.layout`).
  layout('media.layout'),

  /// One frame of a layout transition (`MediaLayout.lerp`).
  lerp('media.lerp'),

  /// One cell's builder (`fine` only: one span per cell per build).
  cellBuild('media.cellBuild', fine: true);

  const MediaTrace(String name, {this.fine = false})
    : label = 'chat_scroll_view.$name';

  /// The section's name on the timeline.
  final String label;

  /// Whether the section is recorded at the `fine` level only.
  final bool fine;

  static const String _define = String.fromEnvironment(
    'chat_scroll_view.trace',
  );

  // Constants, so the gate folds away in a build without the define.
  static const bool _phase = _define == 'phase' || _define == 'fine';
  static const bool _fine = _define == 'fine';

  /// Starts [section]; pair with [end] in the same synchronous scope.
  static void begin(MediaTrace section) {
    if (!_phase) return;
    if (section.fine && !_fine) return;
    Timeline.startSync(section.label);
  }

  /// Ends the section [begin] started with the same [section].
  static void end(MediaTrace section) {
    if (!_phase) return;
    if (section.fine && !_fine) return;
    Timeline.finishSync();
  }
}

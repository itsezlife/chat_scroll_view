import 'dart:developer' show Timeline;

import 'package:meta/meta.dart';

/// Build-time level of the engine's timeline sections, read from
/// `--dart-define=chat_scroll_view.trace=` (`off` by default, `phase`,
/// `fine`). Anything else reads as off.
@internal
enum TraceLevel {
  /// No sections; every call site folds away.
  off,

  /// One section per layout step, tick, fetch poll and paint stage.
  phase,

  /// [phase] plus per-child layout and paint spans.
  fine;

  static const String _define = String.fromEnvironment(
    'chat_scroll_view.trace',
  );

  /// The level this build was compiled with.
  static const TraceLevel compiled = _define == 'phase'
      ? phase
      : _define == 'fine'
      ? fine
      : off;
}

/// Every named timeline section of the engine, in one namespace
/// (`chat_scroll_view.<name>`). Names are glossary terms.
@internal
enum TraceSection {
  // Layout pipeline steps (docs/architecture/04-layout-pipeline.md).
  layoutMode('layout.mode'),
  layoutCompensate('layout.compensate'),
  layoutOverlay('layout.overlay'),
  layoutJumpGc('layout.jumpGc'),
  layoutNormalizeTail('layout.normalizeTail'),
  layoutDeleteRecovery('layout.deleteRecovery'),
  layoutFanOut('layout.fanOut'),
  layoutPreserve('layout.preserve'),
  layoutHold('layout.hold'),
  layoutRenormalize('layout.renormalize'),
  layoutTailFit('layout.tailFit'),
  layoutAlign('layout.align'),
  layoutTailPin('layout.tailPin'),
  layoutGapMatch('layout.gapMatch'),
  layoutClamp('layout.clamp'),
  layoutGc('layout.gc'),
  layoutFetch('layout.fetch'),
  layoutPublish('layout.publish'),

  // Ticks.
  tickTier1('tick.tier1'),
  tickFling('tick.fling'),
  tickAnimator('animator.tick'),

  // Fetch.
  fetchPoll('fetch.poll'),

  // Paint stages.
  paintMessages('paint.messages'),
  paintScrollbar('paint.scrollbar'),
  paintHighlight('paint.highlight'),
  paintSelection('paint.selection'),

  // Per-child build, counted by the traced pass (a `phase` section); layout
  // and paint spans are `fine` only.
  childBuild('child.build'),
  childLayout('child.layout', fine: true),
  childPaint('child.paint', fine: true);

  const TraceSection(String name, {this.fine = false})
    : label = 'chat_scroll_view.$name';

  /// The timeline event name.
  final String label;

  /// Whether the section is recorded at the `fine` level only.
  final bool fine;
}

/// Opens and closes [TraceSection]s on the timeline.
///
/// The gate is a compile-time constant, so in the default build every
/// `begin` / `end` call is an empty body. Call sites pass enum constants only:
/// no closures, no maps, nothing allocated outside the gate.
@internal
abstract final class Trace {
  static const TraceLevel level = TraceLevel.compiled;

  static const bool _phase = level != TraceLevel.off;
  static const bool _fine = level == TraceLevel.fine;

  /// Starts [section]; pair with [end] in the same synchronous scope.
  static void begin(TraceSection section) {
    if (!_phase) return;
    if (section.fine && !_fine) return;
    Timeline.startSync(section.label);
  }

  /// Ends the section [begin] started with the same [section].
  static void end(TraceSection section) {
    if (!_phase) return;
    if (section.fine && !_fine) return;
    Timeline.finishSync();
  }
}

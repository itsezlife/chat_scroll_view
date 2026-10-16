import 'dart:async';
import 'dart:math' as math;

import 'package:catalog_assets/src/atlas/bake_frame_source.dart';
import 'package:catalog_assets/src/atlas/bake_governor.dart';
import 'package:catalog_assets/src/atlas/bake_pause_signals.dart';
import 'package:catalog_assets/src/atlas/glyph_baker.dart';
import 'package:catalog_assets/src/atlas/report_glyph_atlas_error.dart';
import 'package:flutter/foundation.dart';

/// Drives a [GlyphBaker] one step per frame, so baking never costs the user a
/// dropped frame.
///
/// Each frame it asks the [BakeGovernor] how many glyphs the frame can afford
/// and runs one [GlyphBaker.step]. It watches how long that step took on the
/// injected [BakeClock] and what the engine says the last frame cost, and
/// feeds both back, so a slow device slows the bake instead of dropping
/// frames. It runs only while [BakePauseSignals.allowsBaking]: a scroll start,
/// the open animation or a hidden panel stop it at once, and it resumes after
/// [settleFrames] quiet frames, so the step never lands on the frame the user
/// just finished moving in.
///
/// While paused or complete it holds no frame request, no timer and no
/// pending work beyond its listeners; [dispose] removes those too. Time comes
/// only from the injected frame source and clock, so a test drives it frame by
/// frame.
///
/// Which glyphs bake first is the host's to say through [prioritise]; the
/// baker turns that into page order (see [GlyphBaker.prioritise]).
final class GlyphBakeScheduler {
  /// Creates a scheduler for [baker]. Nothing runs until [start].
  ///
  /// [onPageBaked] is called with a page index each time a page is composed
  /// and stored, so a host can repaint the cells it covers.
  GlyphBakeScheduler({
    required GlyphBaker baker,
    required BakeFrameSource frames,
    required BakeClock clock,
    required BakePauseSignals signals,
    BakeGovernor? governor,
    this.settleFrames = 2,
    this.onPageBaked,
  }) : _baker = baker,
       _frames = frames,
       _clock = clock,
       _signals = signals,
       _governor = governor ?? BakeGovernor();

  /// Frames that must pass quietly after baking is allowed again before the
  /// next step runs.
  final int settleFrames;

  /// Called with the index of each page as it becomes drawable.
  final ValueChanged<int>? onPageBaked;

  final GlyphBaker _baker;
  final BakeFrameSource _frames;
  final BakeClock _clock;
  final BakePauseSignals _signals;
  final BakeGovernor _governor;

  BakeFrameCancel? _cancelFrame;
  _Phase _phase = _Phase.notStarted;
  int _quietFrames = 0;
  // How long the last strip step took, until the next frame folds it into one
  // observation with the engine's own measurement.
  Duration? _lastStepCost;

  /// Glyphs the next frame will bake.
  int get glyphsPerFrame => _governor.glyphsPerFrame;

  /// Whether every page is baked.
  bool get isComplete => _baker.isComplete;

  /// Starts baking, as far as the pause signals allow. Calling it twice, or
  /// after [dispose], does nothing.
  void start() {
    if (_phase != _Phase.notStarted) return;
    _phase = _Phase.running;
    _signals.addListener(_onSignal);
    _resumeIfAllowed();
  }

  /// Asks for a frame again if there is work and baking is allowed. The
  /// scheduler stops asking once every page is baked; call this after the
  /// baker was given work again (a page forgotten with
  /// [GlyphBaker.markUnbaked]). Does nothing while a frame is already
  /// requested, a step is running, or after a failure or [dispose].
  void resume() => _resumeIfAllowed();

  /// Bakes the pages holding [glyphs] (the visible band, most important
  /// first) before the others. Safe to call at any time, including while a
  /// step is running; it takes effect on the next step.
  void prioritise(Iterable<String> glyphs) => _baker.prioritise(glyphs);

  /// Stops baking and releases every listener and pending frame request.
  /// Idempotent. Does not dispose the baker: stored pages and the baker belong
  /// to whoever made them, and a step already running finishes harmlessly.
  void dispose() {
    final wasStarted = _phase != _Phase.notStarted;
    if (_phase == _Phase.disposed) return;
    _phase = _Phase.disposed;
    _cancelPendingFrame();
    if (wasStarted) _signals.removeListener(_onSignal);
  }

  // --- Pause rules -----------------------------------------------------------

  void _onSignal() {
    if (_signals.allowsBaking) {
      _resumeIfAllowed();
    } else {
      // Pause now, not at the next frame: no step may start after the user
      // began to scroll. Settling starts over when the pause ends.
      _cancelPendingFrame();
      _quietFrames = 0;
      // An unobserved step cost belongs to the run that just ended; folded
      // into the first frame after the pause it would slow the pace for a
      // step the user never waited on.
      _lastStepCost = null;
    }
  }

  void _resumeIfAllowed() {
    if (_phase != _Phase.running ||
        _cancelFrame != null ||
        _baker.isComplete ||
        !_signals.allowsBaking) {
      return;
    }
    _cancelFrame = _frames.requestFrame(_onFrame);
  }

  void _cancelPendingFrame() {
    _cancelFrame?.call();
    _cancelFrame = null;
  }

  // --- Frame loop ------------------------------------------------------------

  void _onFrame(BakeFrame frame) {
    _cancelFrame = null;
    if (_phase != _Phase.running || !_signals.allowsBaking) return;

    _observe(frame);
    if (_quietFrames < settleFrames) {
      _quietFrames++;
      _resumeIfAllowed();
      return;
    }
    unawaited(_runStep());
  }

  /// Folds the engine's measurement of the previous frame and the bake's own
  /// step time into one observation. The engine figure includes raster work
  /// the step cannot see; the step figure is immediate where the engine's
  /// arrives in batches. Alone, the step figure can only lower the pace.
  void _observe(BakeFrame frame) {
    final step = _lastStepCost;
    _lastStepCost = null;
    final engine = frame.cost;
    if (engine == null && step == null) return;
    _governor.observe(
      cost: Duration(
        microseconds: math.max(
          engine?.inMicroseconds ?? 0,
          step?.inMicroseconds ?? 0,
        ),
      ),
      budget: frame.budget,
      mayRise: engine != null,
    );
  }

  Future<void> _runStep() async {
    _phase = _Phase.stepping;
    try {
      final started = _clock();
      final result = await _baker.step(glyphs: _governor.glyphsPerFrame);
      switch (result) {
        case BakeStep.strip:
          _lastStepCost = _clock() - started;
        case BakeStep.page:
          // A page composes in one step whatever the pace and its time is
          // mostly the store's, so it is not held against the governor.
          if (_phase != _Phase.disposed) {
            onPageBaked?.call(_baker.lastBakedPage!);
          }
        case BakeStep.done:
          break;
      }
    } on Object catch (error, stack) {
      // Never swallowed, and never retried in a loop: a rasteriser or store
      // that throws once will throw every frame.
      _phase = _Phase.failed;
      reportGlyphAtlasError(error, stack, 'while baking glyph atlas pages');
    }
    if (_phase == _Phase.stepping) _phase = _Phase.running;
    _resumeIfAllowed();
  }
}

/// Where the scheduler is in its life. One value instead of independent
/// flags: it cannot be stepping before it started, or failed and disposed.
enum _Phase {
  /// Created; [GlyphBakeScheduler.start] has not run.
  notStarted,

  /// Started, between steps: waiting for a frame or for the signals.
  running,

  /// A [GlyphBaker.step] is in flight.
  stepping,

  /// A step threw. It would throw every frame, so nothing runs again.
  failed,

  /// Torn down; a step still in flight finishes harmlessly.
  disposed,
}

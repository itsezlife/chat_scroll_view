import 'dart:async';
import 'dart:typed_data';

import 'package:emoji_data/src/glyph_probe/missing_glyph_probe.dart';

/// The probe's own rasterisation pass, for a host that has no bake to share:
/// it draws the cells a [MissingGlyphProbe] still needs, a few per frame, and
/// feeds them in.
///
/// With a glyph atlas the pass is not needed: the bake draws every glyph
/// anyway and hands its cells to the probe, so nothing is rasterised twice.
/// This pass is the replacement for a platform that bakes nothing; it is
/// swappable because it only talks to the probe through [MissingGlyphProbe]'s
/// evidence methods.
///
/// ## Pacing
///
/// Work happens on frames only. In each frame [run] first asks [isPaused]: while
/// the host reports the panel opening or a scroll in progress, nothing is
/// drawn and the frame passes. Otherwise it draws at most [glyphsPerFrame]
/// cells (read afresh each frame, so a frame-time governor can lower it),
/// references first. The renderer is awaited cell by cell, so a slow cell
/// delays this pass, never the next frame.
final class PacedGlyphProbePass {
  /// Creates a pass feeding [probe] with the cells [cellOf] renders.
  ///
  /// [cellOf] must render every glyph, references included, to a cell of one
  /// fixed size (the probe compares cells). [nextFrame] completes at the next
  /// frame; [isPaused] and [glyphsPerFrame] are read on each one.
  PacedGlyphProbePass({
    required this.probe,
    required this.cellOf,
    required this.nextFrame,
    required this.isPaused,
    required this.glyphsPerFrame,
  });

  /// The probe fed.
  final MissingGlyphProbe probe;

  /// Renders one glyph to its cell: RGBA bytes.
  final Future<Uint8List> Function(String glyph) cellOf;

  /// Completes at the next frame.
  final Future<void> Function() nextFrame;

  /// Whether work must wait: the open animation or a scroll is active.
  final bool Function() isPaused;

  /// How many glyphs the next frame may draw. At least one.
  final int Function() glyphsPerFrame;

  bool _cancelled = false;
  final Set<String> _failed = <String>{};

  /// Draws until the probe has every cell it needs, then completes. Cells that
  /// fail to render are reported to the zone and left without a verdict (shown,
  /// as with no probe); they are not retried by this pass.
  Future<void> run() async {
    await probe.start();
    while (!_cancelled) {
      final todo = _todo();
      if (todo.isEmpty) return;
      await nextFrame();
      if (_cancelled || isPaused()) continue;
      for (final glyph in todo.take(glyphsPerFrame().clamp(1, todo.length))) {
        if (_cancelled) return;
        await _draw(glyph);
      }
    }
  }

  /// Stops the pass at its next step. A pass is not restarted: make a new one.
  void cancel() => _cancelled = true;

  List<String> _todo() => <String>[
    ...probe.pendingReferences,
    ...probe.pendingGlyphs,
  ].where((glyph) => !_failed.contains(glyph)).toList();

  Future<void> _draw(String glyph) async {
    try {
      probe.observe(glyph, await cellOf(glyph));
    } on Object catch (error, stack) {
      _failed.add(glyph);
      Zone.current.handleUncaughtError(error, stack);
    }
  }
}

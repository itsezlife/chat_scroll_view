import 'dart:math' as math;

import 'package:meta/meta.dart';

/// The numbers that shape [BakeGovernor]: how many glyphs one frame may bake
/// and what share of the frame budget counts as cheap or expensive.
///
/// The ceiling of 16 glyphs per frame is about a thousand glyphs a second at
/// 60 Hz; the governor lowers it when frames get expensive and raises it back
/// when they are cheap. The two fractions are starting points, not tuned
/// values: a host that has measured its device passes its own.
@immutable
final class BakePacing {
  /// Creates a pacing.
  const BakePacing({
    this.maxGlyphsPerFrame = 16,
    this.minGlyphsPerFrame = 1,
    this.cheapFraction = 0.5,
    this.expensiveFraction = 0.85,
    this.rise = 2,
  }) : assert(minGlyphsPerFrame > 0, 'a paced bake still bakes something'),
       assert(
         maxGlyphsPerFrame >= minGlyphsPerFrame,
         'maxGlyphsPerFrame is below minGlyphsPerFrame',
       ),
       assert(
         0 < cheapFraction && cheapFraction < expensiveFraction,
         'cheapFraction must be positive and below expensiveFraction',
       ),
       assert(rise > 0, 'the pace must be able to recover');

  /// Glyphs per frame when frames are cheap: the default pace.
  final int maxGlyphsPerFrame;

  /// Glyphs per frame under sustained pressure. Never zero: pausing is the
  /// scheduler's decision, not the governor's.
  final int minGlyphsPerFrame;

  /// A frame costing at most this share of its budget is cheap: the pace rises.
  final double cheapFraction;

  /// A frame costing at least this share of its budget is expensive: the pace
  /// is halved. Below 1.0 on purpose, since a frame this close to the budget
  /// is one slow frame away from a drop.
  final double expensiveFraction;

  /// Glyphs per frame gained by each cheap frame.
  final int rise;
}

/// Decides how many glyphs the next frame may bake, from how much the last
/// frames cost.
///
/// Additive increase, multiplicative decrease: the pace falls fast when a frame
/// gets expensive (a drop costs the user more than a slower bake does) and
/// climbs back slowly, so a device that is only just coping settles below the
/// maximum instead of oscillating. Frames in between hold the pace. Pure: no
/// clock, no frames; the caller feeds it observations.
final class BakeGovernor {
  /// Creates a governor that starts at [BakePacing.maxGlyphsPerFrame].
  BakeGovernor({this.pacing = const BakePacing()})
    : _glyphsPerFrame = pacing.maxGlyphsPerFrame;

  /// The limits and thresholds in use.
  final BakePacing pacing;

  int _glyphsPerFrame;

  /// Glyphs the next frame may bake.
  int get glyphsPerFrame => _glyphsPerFrame;

  /// Records that a frame cost [cost] against its vsync [budget].
  ///
  /// A [cost] that is only part of the story (the time the bake itself took,
  /// without the raster work the engine did for the frame) passes
  /// `mayRise: false`: it can show a frame is too expensive, but never that
  /// it is cheap.
  void observe({
    required Duration cost,
    required Duration budget,
    bool mayRise = true,
  }) {
    final share = cost.inMicroseconds / budget.inMicroseconds;
    if (share >= pacing.expensiveFraction) {
      _glyphsPerFrame = math.max(
        pacing.minGlyphsPerFrame,
        _glyphsPerFrame ~/ 2,
      );
    } else if (mayRise && share <= pacing.cheapFraction) {
      _glyphsPerFrame = math.min(
        pacing.maxGlyphsPerFrame,
        _glyphsPerFrame + pacing.rise,
      );
    }
  }
}

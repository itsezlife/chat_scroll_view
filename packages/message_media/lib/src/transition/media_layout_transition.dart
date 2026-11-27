import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/transition/media_transition_policy.dart';

/// How visible and how large one cell paints during a transition.
@immutable
final class MediaCellFade {
  /// A cell at [opacity], scaled by [scale] about its centre.
  const MediaCellFade({required this.opacity, required this.scale});

  /// Fully shown at its own size.
  static const settled = MediaCellFade(opacity: 1, scale: 1);

  /// Opacity in `[0, 1]`.
  final double opacity;

  /// Paint scale about the cell's centre.
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is MediaCellFade &&
      other.opacity == opacity &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(opacity, scale);

  @override
  String toString() => 'MediaCellFade($opacity, $scale)';
}

/// One frame of a message's media transition: the interpolated layout, the
/// fades of the cells entering or leaving, and the move's progress.
///
/// The bubble and the caption follow the same frame: the bubble takes
/// [layout]'s size, and a caption change cross-fades by [progress].
@immutable
final class MediaTransitionFrame {
  /// A frame of [layout] with [fades] at [progress].
  MediaTransitionFrame({
    required this.layout,
    Map<MediaItemId, MediaCellFade> fades = const {},
    this.progress = 1,
  }) : fades = Map.unmodifiable(fades);

  /// [layout] at rest: no fades, the move done.
  MediaTransitionFrame.settled(MediaLayout layout) : this(layout: layout);

  /// The interpolated layout; its exiting cells are the ones still fading
  /// out.
  final MediaLayout layout;

  /// The fades of the cells that are not [MediaCellFade.settled].
  final Map<MediaItemId, MediaCellFade> fades;

  /// The move's curved progress, `0` at the old layout and `1` at the new.
  final double progress;

  /// Whether nothing moves or fades any more.
  bool get isSettled =>
      progress >= 1 && fades.isEmpty && layout.exiting.isEmpty;

  /// The fade of the cell of [id].
  MediaCellFade fadeOf(MediaItemId id) => fades[id] ?? MediaCellFade.settled;

  @override
  bool operator ==(Object other) =>
      other is MediaTransitionFrame &&
      other.layout == layout &&
      other.progress == progress &&
      mapEquals(other.fades, fades);

  @override
  int get hashCode => Object.hash(
    layout,
    progress,
    Object.hashAllUnordered(
      fades.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}

/// One leg of a media transition: from a frame (the old layout at rest, or
/// wherever a running leg had got to) to a new layout, under a policy.
///
/// Pure: [frameAt] gives the frame any time into the leg, so a clock only
/// asks it each tick, and a re-layout mid-flight starts the next leg from
/// the frame this one reached.
@immutable
final class MediaLayoutTransition {
  /// The leg from [from] to [to] under [policy].
  factory MediaLayoutTransition({
    required MediaTransitionFrame from,
    required MediaLayout to,
    required MediaTransitionPolicy policy,
  }) {
    final shown = {for (final cell in from.layout.cells) cell.itemId};
    final entering = {
      for (final cell in to.cells)
        if (!shown.contains(cell.itemId)) cell.itemId,
    };
    final exiting = {
      for (final cell in [...from.layout.cells, ...from.layout.exiting])
        if (to.cellOf(cell.itemId) == null) cell.itemId,
    };
    return MediaLayoutTransition._(
      from: from,
      to: to,
      policy: policy,
      entering: entering,
      exiting: exiting,
    );
  }

  const MediaLayoutTransition._({
    required this.from,
    required this.to,
    required this.policy,
    required this.entering,
    required this.exiting,
  });

  /// The frame the leg starts from.
  final MediaTransitionFrame from;

  /// The layout the leg ends at.
  final MediaLayout to;

  /// The tracks' timings.
  final MediaTransitionPolicy policy;

  /// The items whose cells fade in: new in [to], or back from an exit.
  final Set<MediaItemId> entering;

  /// The items whose cells fade out: in [from], not in [to].
  final Set<MediaItemId> exiting;

  /// How long the move waits: [MediaTransitionPolicy.moveDelayOnExit] while
  /// a cell leaves.
  Duration get moveDelay =>
      exiting.isEmpty ? Duration.zero : policy.moveDelayOnExit;

  /// When the last track ends.
  Duration get duration {
    final micros = [
      if (policy.move > Duration.zero) (moveDelay + policy.move).inMicroseconds,
      if (exiting.isNotEmpty) policy.exitFade.inMicroseconds,
      if (entering.isNotEmpty) policy.enterFade.inMicroseconds,
    ];
    return Duration(microseconds: micros.fold(0, math.max));
  }

  /// The frame [elapsed] into the leg; [to] at rest once [duration] has
  /// passed.
  MediaTransitionFrame frameAt(Duration elapsed) {
    if (elapsed >= duration) return MediaTransitionFrame.settled(to);
    final move = policy.moveCurve.transform(
      _progress(elapsed - moveDelay, policy.move),
    );
    final layout = MediaLayout.lerp(
      from.layout,
      to,
      move,
      radii: policy.lerpRadii,
    );
    final enter = policy.fadeCurve.transform(
      _progress(elapsed, policy.enterFade),
    );
    final exit = _progress(elapsed, policy.exitFade);
    final exitDone = exit >= 1;
    final returning = {for (final cell in from.layout.exiting) cell.itemId};
    final fades = <MediaItemId, MediaCellFade>{};
    for (final id in entering) {
      final start = returning.contains(id)
          ? from.fadeOf(id)
          : MediaCellFade(opacity: 0, scale: policy.enterScale);
      final fade = _lerpFade(start, MediaCellFade.settled, enter);
      if (fade != MediaCellFade.settled) fades[id] = fade;
    }
    if (!exitDone) {
      final faded = policy.fadeCurve.transform(exit);
      for (final id in exiting) {
        fades[id] = _lerpFade(from.fadeOf(id), _gone, faded);
      }
    }
    return MediaTransitionFrame(
      // A cell whose exit has ended is no longer painted.
      layout: exitDone ? layout.withExiting(const []) : layout,
      fades: fades,
      progress: move,
    );
  }

  static const _gone = MediaCellFade(opacity: 0, scale: 1);

  static double _progress(Duration elapsed, Duration duration) {
    if (duration <= Duration.zero) return 1;
    return (elapsed.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
  }

  static MediaCellFade _lerpFade(MediaCellFade a, MediaCellFade b, double t) =>
      MediaCellFade(
        opacity: lerpDouble(a.opacity, b.opacity, t)!.clamp(0.0, 1.0),
        scale: lerpDouble(a.scale, b.scale, t)!,
      );
}

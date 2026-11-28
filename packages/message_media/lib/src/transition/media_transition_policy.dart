import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatMessageChangeParams;
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// What changed a message's media layout, as the transition's diagnostics
/// name it.
enum MediaTransitionTrigger {
  /// Items were added, removed or replaced.
  items,

  /// The same items, laid out again: dimensions arrived late, a descriptor
  /// changed, or the width did.
  descriptor,

  /// The caption was added, removed or edited.
  caption,

  /// The message's `invertMedia` moved the caption or the card.
  invertMedia,

  /// The link preview card changed size or place.
  card,
}

/// How a message's media layout animates from one layout to the next, with
/// each platform's values.
///
/// Three tracks run on one clock per message:
///
/// - **move**: cells present in both layouts move and resize, their corners
///   follow (or snap, without [lerpRadii]), and so do the block rects and
///   the media's size, which the row reports as its height each frame;
/// - **exit**: a cell that left fades out at its last rect over [exitFade];
///   while one does, the move waits [moveDelayOnExit];
/// - **enter**: a new cell fades in over [enterFade], growing from
///   [enterScale] about its centre.
///
/// | | Android | iOS | Desktop |
/// | --- | --- | --- | --- |
/// | move | 250 ms, the list-item cubic | 400 ms, the system list curve; corners snap | none |
/// | exit | 120 ms fade; the move waits 120 ms | 250 ms fade | none |
/// | enter | 250 ms fade, scale 0.9 → 1 | 250 ms fade | none |
///
/// The Android values are the viewport's own list-item change timing
/// (`ChatMessageChangeParams`), so a media change moves with an edit morph
/// and the row chrome. The platform's reduce-motion switch is read by the
/// clock, which then jumps every transition to its end.
@immutable
final class MediaTransitionPolicy {
  /// A policy of the given tracks.
  const MediaTransitionPolicy({
    required this.move,
    required this.moveCurve,
    required this.lerpRadii,
    required this.exitFade,
    required this.moveDelayOnExit,
    required this.enterFade,
    required this.enterScale,
    required this.fadeCurve,
  }) : assert(enterScale > 0, 'enterScale is positive.');

  /// The Android family's tracks.
  const MediaTransitionPolicy.android()
    : this(
        move: ChatMessageChangeParams.duration,
        moveCurve: ChatMessageChangeParams.curve,
        lerpRadii: true,
        exitFade: const Duration(milliseconds: 120),
        moveDelayOnExit: const Duration(milliseconds: 120),
        enterFade: ChatMessageChangeParams.duration,
        enterScale: 0.9,
        // The item animator's default accelerate-decelerate fade.
        fadeCurve: Curves.easeInOutSine,
      );

  /// The iOS family's tracks.
  ///
  /// The move rides the list's system curve, a spring solved into a curve;
  /// its cubic form `(0.23, 1, 0.32, 1)` stands in for the spring, which
  /// settles without overshoot.
  const MediaTransitionPolicy.ios()
    : this(
        move: const Duration(milliseconds: 400),
        moveCurve: const Cubic(0.23, 1, 0.32, 1),
        lerpRadii: false,
        exitFade: const Duration(milliseconds: 250),
        moveDelayOnExit: Duration.zero,
        enterFade: const Duration(milliseconds: 250),
        enterScale: 1,
        fadeCurve: Curves.easeInOut,
      );

  /// The desktop family's tracks: none, every layout change is instant.
  const MediaTransitionPolicy.desktop() : this.none();

  /// No transition: each layout replaces the last at once.
  const MediaTransitionPolicy.none()
    : this(
        move: Duration.zero,
        moveCurve: Curves.linear,
        lerpRadii: false,
        exitFade: Duration.zero,
        moveDelayOnExit: Duration.zero,
        enterFade: Duration.zero,
        enterScale: 1,
        fadeCurve: Curves.linear,
      );

  /// How long cells, blocks and the size move.
  final Duration move;

  /// The curve of the move.
  final Curve moveCurve;

  /// Whether corner radii interpolate with the move; without it they snap
  /// to the new layout's.
  final bool lerpRadii;

  /// How long a cell that left fades out.
  final Duration exitFade;

  /// How long the move waits while a cell fades out.
  final Duration moveDelayOnExit;

  /// How long a new cell fades (and grows) in.
  final Duration enterFade;

  /// The scale a new cell grows from.
  final double enterScale;

  /// The curve of the fades and the enter scale.
  final Curve fadeCurve;

  /// Whether any track takes time; a policy that does not replaces each
  /// layout at once.
  bool get animates =>
      move > Duration.zero ||
      exitFade > Duration.zero ||
      enterFade > Duration.zero;

  /// A copy with the given tracks replaced.
  MediaTransitionPolicy copyWith({
    Duration? move,
    Curve? moveCurve,
    bool? lerpRadii,
    Duration? exitFade,
    Duration? moveDelayOnExit,
    Duration? enterFade,
    double? enterScale,
    Curve? fadeCurve,
  }) => MediaTransitionPolicy(
    move: move ?? this.move,
    moveCurve: moveCurve ?? this.moveCurve,
    lerpRadii: lerpRadii ?? this.lerpRadii,
    exitFade: exitFade ?? this.exitFade,
    moveDelayOnExit: moveDelayOnExit ?? this.moveDelayOnExit,
    enterFade: enterFade ?? this.enterFade,
    enterScale: enterScale ?? this.enterScale,
    fadeCurve: fadeCurve ?? this.fadeCurve,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaTransitionPolicy &&
      other.move == move &&
      other.moveCurve == moveCurve &&
      other.lerpRadii == lerpRadii &&
      other.exitFade == exitFade &&
      other.moveDelayOnExit == moveDelayOnExit &&
      other.enterFade == enterFade &&
      other.enterScale == enterScale &&
      other.fadeCurve == fadeCurve;

  @override
  int get hashCode => Object.hash(
    move,
    moveCurve,
    lerpRadii,
    exitFade,
    moveDelayOnExit,
    enterFade,
    enterScale,
    fadeCurve,
  );
}

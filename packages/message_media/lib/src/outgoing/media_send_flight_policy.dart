import 'dart:ui' show Rect, lerpDouble;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// How a freshly sent media item flies from where it was picked (its send
/// origin) to its cell, with each platform's values.
///
/// | | Android | iOS | Desktop |
/// | --- | --- | --- | --- |
/// | flight | none | 300 ms; x on `(0.23, 1, 0.32, 1)`, y on `(0.199, 0.011, 0.279, 0.910)` | none |
///
/// The flight is the cell's only: the row's own appearance (a slide up, a
/// fade and scale) is the host's. A cell asks the chat's
/// `MessageMediaState.takeSendOrigin` once, on its first build, and only
/// where the policy [flies]; without an origin, or under the platform's
/// reduce-motion switch, it shows in place.
@immutable
final class MediaSendFlightPolicy {
  /// A flight of [duration], each axis on its own curve.
  const MediaSendFlightPolicy({
    required this.duration,
    required this.horizontalCurve,
    required this.verticalCurve,
  });

  /// iOS: 300 ms, the horizontal axis on the system list curve, the
  /// vertical on the list-item cubic.
  const MediaSendFlightPolicy.ios()
    : this(
        duration: const Duration(milliseconds: 300),
        horizontalCurve: const Cubic(0.23, 1, 0.32, 1),
        verticalCurve: const Cubic(0.199, 0.011, 0.279, 0.910),
      );

  /// No flight: a sent item shows in its cell at once (Android, desktop).
  const MediaSendFlightPolicy.none()
    : this(
        duration: Duration.zero,
        horizontalCurve: Curves.linear,
        verticalCurve: Curves.linear,
      );

  /// How long the flight takes.
  final Duration duration;

  /// The curve the horizontal edges move on.
  final Curve horizontalCurve;

  /// The curve the vertical edges move on.
  final Curve verticalCurve;

  /// Whether a sent item flies at all; a cell asks for its origin only then.
  bool get flies => duration > Duration.zero;

  /// The flying rect at [t] (0 to 1) of a flight from [from] to [to]: each
  /// edge moves on its axis's curve, so the picture's size changes with its
  /// place.
  Rect rectAt(Rect from, Rect to, double t) {
    final x = horizontalCurve.transform(t);
    final y = verticalCurve.transform(t);
    return Rect.fromLTRB(
      lerpDouble(from.left, to.left, x)!,
      lerpDouble(from.top, to.top, y)!,
      lerpDouble(from.right, to.right, x)!,
      lerpDouble(from.bottom, to.bottom, y)!,
    );
  }

  /// A copy with the given values replaced.
  MediaSendFlightPolicy copyWith({
    Duration? duration,
    Curve? horizontalCurve,
    Curve? verticalCurve,
  }) => MediaSendFlightPolicy(
    duration: duration ?? this.duration,
    horizontalCurve: horizontalCurve ?? this.horizontalCurve,
    verticalCurve: verticalCurve ?? this.verticalCurve,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaSendFlightPolicy &&
      other.duration == duration &&
      other.horizontalCurve == horizontalCurve &&
      other.verticalCurve == verticalCurve;

  @override
  int get hashCode => Object.hash(
    MediaSendFlightPolicy,
    duration,
    horizontalCurve,
    verticalCurve,
  );
}

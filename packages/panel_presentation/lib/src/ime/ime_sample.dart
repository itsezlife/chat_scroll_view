import 'package:meta/meta.dart';

/// One raw reading of the soft keyboard, as the host measures it.
///
/// Raw means unfiltered: it may be a mid-animation frame, a one-frame spike
/// or a transient zero. Interpreting a stream of samples is the keyboard
/// strategy's job, so the host forwards every reading it has and invents none.
@immutable
final class ImeSample {
  /// A reading of [height] logical pixels of keyboard, [animating] while the
  /// system moves it, with [safeAreaBottom] pixels of bottom safe area.
  const ImeSample({
    required this.height,
    this.animating = false,
    this.safeAreaBottom = 0,
  }) : assert(height >= 0, 'height must not be negative'),
       assert(safeAreaBottom >= 0, 'safeAreaBottom must not be negative');

  /// A hidden keyboard, at rest, with no safe area.
  static const ImeSample hidden = ImeSample(height: 0);

  /// The keyboard height in logical pixels, including the bottom safe area
  /// when the platform reports it that way; 0 when hidden.
  final double height;

  /// Whether the system is currently animating the keyboard. A height read
  /// while animating is not a settled keyboard size.
  final bool animating;

  /// The bottom safe area (home indicator, navigation bar) in logical pixels.
  final double safeAreaBottom;

  @override
  bool operator ==(Object other) =>
      other is ImeSample &&
      other.height == height &&
      other.animating == animating &&
      other.safeAreaBottom == safeAreaBottom;

  @override
  int get hashCode => Object.hash(height, animating, safeAreaBottom);

  @override
  String toString() =>
      'ImeSample(height: $height, animating: $animating, '
      'safeAreaBottom: $safeAreaBottom)';
}

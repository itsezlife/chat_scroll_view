import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart'
    show FrictionSimulation, Simulation, Tolerance;

/// **Scroll physics** of the chat viewport: one [fling] paired with one
/// [edgeEffect], governing user-driven motion.
///
/// Only the drag path — touch, stylus, trackpad pan — drives the fling and
/// the edge effect. Mouse wheel, keyboard, scrollbar drag, and programmatic
/// scrolling stay hard-clamped at the conversation edges.
///
/// The edge effect is paint-only on every pairing: layout stays pinned at a
/// reached conversation edge and the message layer alone is transformed.
/// Hit-testing, the paint transform reported to descendants, and row chrome
/// paint inputs include that transform; the floating day header and the
/// scrollbar stay outside it.
///
/// Both axes are closed sets. The presets are named after their edge
/// effect; a custom pairing is a different pair of variants and
/// parameters, not a new strategy type.
///
/// Immutable and value-equal. Passing an equal value to a live viewport
/// changes nothing. An unequal value stops any fling in flight — the viewport
/// emits its usual fling-end scroll event — and drops the current edge
/// effect at once; the next gesture runs on the new pair.
@immutable
final class ChatScrollPhysics {
  /// Pairs [fling] with [edgeEffect].
  const ChatScrollPhysics({required this.fling, required this.edgeEffect});

  /// The spline fling with the stretch edge effect, both at default
  /// parameters.
  const ChatScrollPhysics.stretch()
    : fling = const ChatFling.spline(),
      edgeEffect = const ChatEdgeEffect.stretch();

  /// The decay fling with the rubber-band edge effect, both at default
  /// parameters.
  const ChatScrollPhysics.rubberBand()
    : fling = const ChatFling.decay(),
      edgeEffect = const ChatEdgeEffect.rubberBand();

  /// The spline fling with no edge effect: motion stops hard at a reached
  /// edge.
  const ChatScrollPhysics.clamped()
    : fling = const ChatFling.spline(),
      edgeEffect = const ChatEdgeEffect.none();

  /// The preset matching the OS family of [platform], or of
  /// [defaultTargetPlatform] when [platform] is `null`:
  ///
  /// | Platform           | Preset         |
  /// |--------------------|----------------|
  /// | Android, Fuchsia   | [stretch]      |
  /// | iOS, macOS         | [rubberBand]   |
  /// | Windows, Linux     | [clamped]      |
  ///
  /// On the web, [defaultTargetPlatform] reports the browser's OS, so a
  /// browser follows the same table as the native app on that OS.
  ///
  /// The platform comes from [defaultTargetPlatform] only — never from
  /// `ThemeData.platform` or the ambient `ScrollConfiguration`. Pass
  /// [platform] (or set `debugDefaultTargetPlatformOverride`) to pin the
  /// row. Each row returns a constant, so repeated calls on one platform
  /// are equal and a rebuild that re-resolves the default changes nothing.
  factory ChatScrollPhysics.forPlatform({TargetPlatform? platform}) =>
      switch (platform ?? defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.fuchsia => const ChatScrollPhysics.stretch(),
        TargetPlatform.iOS ||
        TargetPlatform.macOS => const ChatScrollPhysics.rubberBand(),
        TargetPlatform.windows ||
        TargetPlatform.linux => const ChatScrollPhysics.clamped(),
      };

  /// Inertial travel after a release with velocity.
  final ChatFling fling;

  /// Paint-only response when user motion presses past a reached edge.
  final ChatEdgeEffect edgeEffect;

  @override
  bool operator ==(Object other) =>
      other is ChatScrollPhysics &&
      other.fling == fling &&
      other.edgeEffect == edgeEffect;

  @override
  int get hashCode => Object.hash(fling, edgeEffect);

  @override
  String toString() =>
      'ChatScrollPhysics(fling: $fling, edgeEffect: $edgeEffect)';
}

/// **Fling**: inertial travel after a release with velocity, following one
/// deceleration curve.
///
/// A fling stops at a boundary pin; its leftover velocity at that frame goes
/// to the paired [ChatEdgeEffect]. A fling never starts when the whole
/// conversation fits in the scroll band.
@immutable
sealed class ChatFling {
  const ChatFling();

  /// Spline curve with a long tail — see [ChatFling$Spline].
  const factory ChatFling.spline({double friction}) = ChatFling$Spline;

  /// Exponential decay — see [ChatFling$Decay].
  const factory ChatFling.decay({double decelerationRate}) = ChatFling$Decay;
}

/// **Spline** fling: travel follows a fixed spline shape stretched over a
/// duration that grows with release velocity.
///
/// Distance and duration both follow from velocity and [friction]. Most of
/// the travel happens early; the curve then eases into a long, slow tail, so
/// the fling — and any chrome that waits for scrolling to go idle — settles
/// only at the very end of that tail.
final class ChatFling$Spline extends ChatFling {
  /// Spline fling decelerating with [friction].
  const ChatFling$Spline({this.friction = 0.015})
    : assert(friction > 0, 'friction must be positive');

  /// Scroll friction; default `0.015`.
  ///
  /// Travel distance scales with `friction^(-0.74)` for a given velocity:
  /// doubling friction cuts travel by about 40 % and shortens the fling.
  final double friction;

  @override
  bool operator ==(Object other) =>
      other is ChatFling$Spline && other.friction == friction;

  @override
  int get hashCode => Object.hash(ChatFling$Spline, friction);

  @override
  String toString() => 'ChatFling.spline(friction: $friction)';
}

/// **Decay** fling: velocity decays exponentially, losing the same fraction
/// every millisecond.
///
/// Runs Flutter's [FrictionSimulation] with drag `decelerationRate^1000`.
/// Travel from release
/// velocity `v` approaches `v / ln(1 / drag)`; the fling ends once speed
/// falls below 10 px/s, dropping the last few pixels of an asymptotic tail.
final class ChatFling$Decay extends ChatFling {
  /// Decay fling losing `1 − decelerationRate` of its velocity per ms.
  const ChatFling$Decay({this.decelerationRate = 0.998})
    : assert(
        decelerationRate > 0 && decelerationRate < 1,
        'decelerationRate must lie in (0, 1)',
      );

  /// Fraction of velocity kept per millisecond; default `0.998`.
  ///
  /// Travel scales with `1 / ln(1 / decelerationRate)`: `0.99` travels
  /// about a fifth as far as `0.998` from the same release velocity.
  final double decelerationRate;

  @override
  bool operator ==(Object other) =>
      other is ChatFling$Decay && other.decelerationRate == decelerationRate;

  @override
  int get hashCode => Object.hash(ChatFling$Decay, decelerationRate);

  @override
  String toString() => 'ChatFling.decay(decelerationRate: $decelerationRate)';
}

/// **Edge effect**: the paint-only response of the message layer when user
/// motion presses past a reached conversation edge.
///
/// The anchor origin never passes a boundary pin; only the painted message
/// layer moves. Short content (the whole conversation fits) still shows the
/// effect on drag.
@immutable
sealed class ChatEdgeEffect {
  const ChatEdgeEffect();

  /// Scale from the pressed edge — see [ChatEdgeEffect$Stretch].
  const factory ChatEdgeEffect.stretch({
    double intensity,
    double naturalFrequency,
    double dampingRatio,
  }) = ChatEdgeEffect$Stretch;

  /// Translate past the pressed edge — see [ChatEdgeEffect$RubberBand].
  const factory ChatEdgeEffect.rubberBand({
    double resistance,
    double naturalFrequency,
    double dampingRatio,
  }) = ChatEdgeEffect$RubberBand;

  /// No edge effect — see [ChatEdgeEffect$None].
  const factory ChatEdgeEffect.none() = ChatEdgeEffect$None;
}

/// **Stretch**: scales the message layer from the pressed edge.
///
/// Pull grows the scale along an eased curve of the gesture's unconsumed
/// travel. Motion back toward content scrolls content at once while the
/// stretch releases on its own spring. On release, velocity away from the
/// edge clears the stretch so content can fling; velocity into the edge, or
/// a fling that reaches it, deepens the stretch briefly before it springs
/// back.
final class ChatEdgeEffect$Stretch extends ChatEdgeEffect {
  /// Stretch at the default intensity and spring.
  const ChatEdgeEffect$Stretch({
    this.intensity = 0.016,
    this.naturalFrequency = 24.657,
    this.dampingRatio = 0.98,
  }) : assert(intensity >= 0, 'intensity must not be negative'),
       assert(naturalFrequency > 0, 'naturalFrequency must be positive'),
       assert(dampingRatio > 0, 'dampingRatio must be positive');

  /// Scale added per unit of pull, where one unit is a pull as long as the
  /// viewport is tall. The painted scale saturates near `2 × intensity`.
  final double intensity;

  /// Natural frequency of the return spring, in radians per second.
  final double naturalFrequency;

  /// Damping ratio of the return spring; below `1` the release overshoots
  /// rest before settling.
  final double dampingRatio;

  @override
  bool operator ==(Object other) =>
      other is ChatEdgeEffect$Stretch &&
      other.intensity == intensity &&
      other.naturalFrequency == naturalFrequency &&
      other.dampingRatio == dampingRatio;

  @override
  int get hashCode => Object.hash(
    ChatEdgeEffect$Stretch,
    intensity,
    naturalFrequency,
    dampingRatio,
  );

  @override
  String toString() =>
      'ChatEdgeEffect.stretch(intensity: $intensity, '
      'naturalFrequency: $naturalFrequency, dampingRatio: $dampingRatio)';
}

/// **Rubber-band**: translates the message layer past the pressed edge
/// with growing resistance, then springs back.
///
/// Pull of `x` px on a viewport `d` px tall translates by the curve
/// `d·c·x / (d + c·x)` with `c` = [resistance]: about `c` px per pixel
/// at first, approaching but never reaching `d`. The curve is
/// path-independent — a pull caught mid-spring resumes from the pull that
/// yields the caught translation.
///
/// Motion back toward content first walks the translation back down that
/// curve; content scrolls only once the layer is back at the pin. A flick
/// back toward content while displaced carries into a content fling that
/// unwinds the translation first. Any other release while displaced
/// springs back to the pin from the layer's own speed and starts no
/// content fling. A fling that reaches the edge overshoots on the same
/// spring, launched by its leftover velocity, so a faster fling bounces
/// further. A spring never carries the layer past rest into the opposite
/// edge.
final class ChatEdgeEffect$RubberBand extends ChatEdgeEffect {
  /// Rubber-band at the default resistance and spring.
  const ChatEdgeEffect$RubberBand({
    this.resistance = 0.55,
    this.naturalFrequency = 14.142135623730951,
    this.dampingRatio = 1,
  }) : assert(resistance > 0, 'resistance must be positive'),
       assert(naturalFrequency > 0, 'naturalFrequency must be positive'),
       assert(dampingRatio > 0, 'dampingRatio must be positive');

  /// Translation per pixel of pull at the start of the band; default
  /// `0.55`. Lower is stiffer.
  final double resistance;

  /// Natural frequency of the return spring, in radians per second;
  /// default `√200`.
  final double naturalFrequency;

  /// Damping ratio of the return spring; default `1` (critically damped:
  /// the quickest return with no overshoot). Above `1` the return creeps
  /// in with a longer tail; below `1` it is faster but still stops at the
  /// pin instead of crossing it.
  final double dampingRatio;

  @override
  bool operator ==(Object other) =>
      other is ChatEdgeEffect$RubberBand &&
      other.resistance == resistance &&
      other.naturalFrequency == naturalFrequency &&
      other.dampingRatio == dampingRatio;

  @override
  int get hashCode => Object.hash(
    ChatEdgeEffect$RubberBand,
    resistance,
    naturalFrequency,
    dampingRatio,
  );

  @override
  String toString() =>
      'ChatEdgeEffect.rubberBand(resistance: $resistance, '
      'naturalFrequency: $naturalFrequency, dampingRatio: $dampingRatio)';
}

/// No edge effect: motion past a reached edge is dropped.
///
/// The message layer never moves past the pin, and a fling that reaches an
/// edge ends there with its leftover velocity discarded.
final class ChatEdgeEffect$None extends ChatEdgeEffect {
  /// The hard-clamped edge.
  const ChatEdgeEffect$None();

  @override
  bool operator ==(Object other) => other is ChatEdgeEffect$None;

  @override
  int get hashCode => (ChatEdgeEffect$None).hashCode;

  @override
  String toString() => 'ChatEdgeEffect.none()';
}

/// Runs one [ChatFling] at a time on the viewport ticker.
///
/// Owns the simulation start / tick / cancel and nothing else: boundary
/// handling, fling events, and the edge effect stay with the render object
/// and its edge-effect state.
@internal
final class ChatFlingMotion {
  /// Fling runner for [fling]; defaults to the spline.
  ChatFlingMotion([this.fling = const ChatFling.spline()]);

  /// Curve every [startFling] follows.
  final ChatFling fling;

  Simulation? _simulation;

  /// Ticker `elapsed` at the first tick of the current fling, or `null`
  /// between flings. Nullable on purpose — a [Ticker]'s very first `elapsed`
  /// is exactly [Duration.zero], so zero cannot double as "unset".
  Duration? _flingStartTime;
  double _lastFlingValue = 0;

  /// Where a decay fling ends. The exponential never reaches zero speed on
  /// its own, and [FrictionSimulation]'s default `0.001` px/s stop would
  /// keep a 3000 px/s fling — and the idle-driven chrome waiting on it —
  /// alive for over seven seconds. Below 10 px/s the remaining travel is
  /// about 5 px.
  static const Tolerance _decayTolerance = Tolerance(velocity: 10);

  /// `true` while a fling simulation drives inertial scroll.
  bool get isFlinging => _simulation != null;

  /// Instantaneous fling velocity in px/s, or `0` when idle.
  double flingVelocity(Duration elapsed) {
    final simulation = _simulation;
    if (simulation == null) return 0;
    final start = _flingStartTime ?? elapsed;
    final seconds =
        (elapsed - start).inMicroseconds / Duration.microsecondsPerSecond;
    return simulation.dx(seconds);
  }

  /// Arms a fling at [velocity] (px/s), replacing any fling in flight.
  void startFling(double velocity) {
    _simulation = switch (fling) {
      ChatFling$Spline(:final friction) => ChatSplineFlingSimulation(
        velocity: velocity,
        friction: friction,
      ),
      ChatFling$Decay(:final decelerationRate) => FrictionSimulation(
        math.pow(decelerationRate, 1000).toDouble(),
        0,
        velocity,
        tolerance: _decayTolerance,
      ),
    };
    _lastFlingValue = 0.0;
    _flingStartTime = null;
  }

  /// Stops an in-flight fling and clears simulation state.
  void cancelFling() {
    _simulation = null;
    _flingStartTime = null;
    _lastFlingValue = 0;
  }

  /// Per-frame fling delta (px). Returns `0` when idle or finished; the
  /// frame that finishes the curve clears the fling.
  double tickFling(Duration elapsed) {
    final simulation = _simulation;
    if (simulation == null) return 0;
    final start = _flingStartTime ??= elapsed;
    final seconds =
        (elapsed - start).inMicroseconds / Duration.microsecondsPerSecond;
    if (simulation.isDone(seconds)) {
      cancelFling();
      return 0;
    }
    final value = simulation.x(seconds);
    final delta = value - _lastFlingValue;
    _lastFlingValue = value;
    return delta;
  }
}

/// Android's `OverScroller` fling curve (`SplineOverScroller`), in logical
/// pixels.
///
/// Travels the same distance from the same initial velocity as
/// `ClampingScrollSimulation`, but keeps Android's full duration and slow
/// tail. `ClampingScrollSimulation` fits a power curve that ends after about
/// 0.83 of that duration, so a fling there settles, and idle-driven chrome
/// hides, noticeably sooner than on a native Android list.
final class ChatSplineFlingSimulation extends Simulation {
  /// A fling starting at position `0` with [velocity] in px/s.
  ChatSplineFlingSimulation({required double velocity, this.friction = 0.015}) {
    final speed = velocity.abs();
    if (speed == 0) return;
    final l = math.log(_inflexion * speed / (friction * _physicalCoeff));
    _duration = math.exp(l / (_decelerationRate - 1));
    _distance =
        velocity.sign *
        friction *
        _physicalCoeff *
        math.exp(_decelerationRate / (_decelerationRate - 1) * l);
  }

  /// Android `ViewConfiguration.getScrollFriction()`.
  final double friction;

  /// Seconds until the fling stops.
  double get duration => _duration;
  double _duration = 0;

  /// Signed travel in px.
  double get distance => _distance;
  double _distance = 0;

  static final double _decelerationRate = math.log(0.78) / math.log(0.9);
  static const double _inflexion = 0.35;

  /// Earth gravity × inches per meter × 160 logical px per inch × 0.84.
  static const double _physicalCoeff = 9.80665 * 39.37 * 160.0 * 0.84;

  static const int _samples = 100;
  static final List<double> _splinePosition = _buildSplinePosition();

  static List<double> _buildSplinePosition() {
    const startTension = 0.5;
    const endTension = 1.0;
    const p1 = startTension * _inflexion;
    const p2 = 1.0 - endTension * (1.0 - _inflexion);
    final positions = List<double>.filled(_samples + 1, 1);
    var xMin = 0.0;
    for (var i = 0; i < _samples; i++) {
      final alpha = i / _samples;
      var xMax = 1.0;
      double x;
      double coef;
      while (true) {
        x = xMin + (xMax - xMin) / 2;
        coef = 3 * x * (1 - x);
        final tx = coef * ((1 - x) * p1 + x * p2) + x * x * x;
        if ((tx - alpha).abs() < 1e-5) break;
        if (tx > alpha) {
          xMax = x;
        } else {
          xMin = x;
        }
      }
      positions[i] = coef * ((1 - x) * startTension + x) + x * x * x;
    }
    return positions;
  }

  /// Spline travel fraction and its slope at normalized time [t] in `[0, 1)`.
  static (double, double) _spline(double t) {
    final index = (_samples * t).floor();
    final tInf = index / _samples;
    final dInf = _splinePosition[index];
    final slope = (_splinePosition[index + 1] - dInf) * _samples;
    return (dInf + (t - tInf) * slope, slope);
  }

  @override
  double x(double time) {
    if (time >= duration) return distance;
    if (time <= 0) return 0;
    return distance * _spline(time / duration).$1;
  }

  @override
  double dx(double time) {
    if (time >= duration || duration == 0) return 0;
    return distance / duration * _spline(math.max(time, 0) / duration).$2;
  }

  @override
  bool isDone(double time) => time >= duration;
}

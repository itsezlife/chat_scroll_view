import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_delivery.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_meta.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_row_appearance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// How the time pill's status changes move on each platform.
///
/// | | Android | iOS | Desktop |
/// | --- | --- | --- | --- |
/// | clock → check (or the badge) | cross-fade, the incoming glyph from half size, 150 ms; held back while the row is entering | the check pops from 1.3× in 0.1 s | the glyph swaps |
/// | one check → two | the first check slides aside, 220 ms, even while entering | the second check pops | the glyph swaps |
/// | while sending | the clock stands | the clock's frame turns every 6 s and its hand every second | the clock stands |
///
/// A null duration or period is no motion. The platform's reduce motion
/// switch jumps every change to its end and stops the clock.
@immutable
final class DemoStatusMotionPolicy {
  /// A policy of the given values; every motion is off unless given.
  const DemoStatusMotionPolicy({
    this.crossFade,
    this.crossFadeScaleFrom = 0.5,
    this.checkSlide,
    this.suppressedWhileEntering = false,
    this.clockFramePeriod,
    this.clockHandPeriod,
    this.checkPop,
    this.checkPopFrom = 1.3,
  });

  /// Android's values.
  const DemoStatusMotionPolicy.android()
    : this(
        crossFade: const Duration(milliseconds: 150),
        checkSlide: const Duration(milliseconds: 220),
        suppressedWhileEntering: true,
      );

  /// iOS's values.
  const DemoStatusMotionPolicy.ios()
    : this(
        clockFramePeriod: const Duration(seconds: 6),
        clockHandPeriod: const Duration(seconds: 1),
        checkPop: const Duration(milliseconds: 100),
      );

  /// Desktop's: the glyph swaps.
  const DemoStatusMotionPolicy.desktop() : this();

  /// The preset of [platform], the running one's by default.
  factory DemoStatusMotionPolicy.platform([TargetPlatform? platform]) =>
      switch (platform ?? defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.fuchsia => const DemoStatusMotionPolicy.android(),
        TargetPlatform.iOS => const DemoStatusMotionPolicy.ios(),
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => const DemoStatusMotionPolicy.desktop(),
      };

  /// How long a glyph takes to cross-fade into the next; null swaps it.
  final Duration? crossFade;

  /// The scale the incoming glyph of a cross-fade starts from (and the
  /// outgoing one ends at).
  final double crossFadeScaleFrom;

  /// How long the first check takes to slide aside as the second comes;
  /// null swaps the glyph.
  final Duration? checkSlide;

  /// Whether a cross-fade is held back while the row is entering (the
  /// check's slide never is).
  final bool suppressedWhileEntering;

  /// How long the clock's frame takes to turn once while sending; null
  /// keeps it still.
  final Duration? clockFramePeriod;

  /// How long the clock's hand takes to turn once while sending.
  final Duration? clockHandPeriod;

  /// How long an appearing check takes to settle from [checkPopFrom]; null
  /// shows it at once.
  final Duration? checkPop;

  /// The scale an appearing check pops from.
  final double checkPopFrom;

  @override
  bool operator ==(Object other) =>
      other is DemoStatusMotionPolicy &&
      other.crossFade == crossFade &&
      other.crossFadeScaleFrom == crossFadeScaleFrom &&
      other.checkSlide == checkSlide &&
      other.suppressedWhileEntering == suppressedWhileEntering &&
      other.clockFramePeriod == clockFramePeriod &&
      other.clockHandPeriod == clockHandPeriod &&
      other.checkPop == checkPop &&
      other.checkPopFrom == checkPopFrom;

  @override
  int get hashCode => Object.hash(
    crossFade,
    crossFadeScaleFrom,
    checkSlide,
    suppressedWhileEntering,
    clockFramePeriod,
    clockHandPeriod,
    checkPop,
    checkPopFrom,
  );
}

/// Which motion a status change runs.
enum DemoStatusMotionKind {
  /// The glyph cross-fades into the next one, scaling.
  crossFade,

  /// The single check slides aside as the second comes.
  checkSlide,

  /// The new check pops from larger to its size.
  checkPop,
}

/// One status change in motion: from [from] to [to], [progress] of the way
/// (0 to 1, linear in time; the painter applies the curve).
@immutable
final class DemoStatusTransition {
  /// A change of [kind] from [from] to [to], at [progress].
  const DemoStatusTransition({
    required this.kind,
    required this.from,
    required this.to,
    required this.progress,
  });

  /// The motion it runs.
  final DemoStatusMotionKind kind;

  /// The status it leaves.
  final DemoDelivery? from;

  /// The status it reaches.
  final DemoDelivery? to;

  /// How far it got, linear in time.
  final double progress;
}

/// The status motion of one time pill: which change is in motion and how
/// far the sending clock has turned, as its painter reads them.
///
/// Headless: it hears each status the pill shows ([follow]) and runs the
/// [policy]'s motion for the change; the meta's render object listens and
/// repaints, so a frame of motion lays nothing out and rebuilds nothing.
/// The status itself comes from the outbox (`onStatusChanged`) and the
/// server's read status, through the bubble's `deliveryChanges`.
final class DemoStatusMotion extends ChangeNotifier {
  /// The motion of a pill that first shows [initial], ticking on [vsync].
  DemoStatusMotion({
    required TickerProvider vsync,
    required this.policy,
    DemoDelivery? initial,
  }) : _$delivery = initial {
    _$change = AnimationController(vsync: vsync)
      ..addListener(notifyListeners)
      ..addStatusListener(_onChangeStatus);
    _$clock = AnimationController(vsync: vsync)..addListener(notifyListeners);
  }

  /// The platform's values.
  final DemoStatusMotionPolicy policy;

  late final AnimationController _$change;
  late final AnimationController _$clock;
  DemoDelivery? _$delivery;
  ({DemoStatusMotionKind kind, DemoDelivery? from, DemoDelivery? to})? _$moving;

  /// The status the pill shows.
  DemoDelivery? get delivery => _$delivery;

  /// The change in motion, or null at rest.
  DemoStatusTransition? get transition => switch (_$moving) {
    (:final kind, :final from, :final to) => DemoStatusTransition(
      kind: kind,
      from: from,
      to: to,
      progress: _$change.value,
    ),
    null => null,
  };

  /// Whether the sending clock is turning.
  bool get turning => _$clock.isAnimating;

  /// How far the clock's frame has turned, in turns (0 to 1).
  double get clockTurns => _$clock.value;

  /// How far the clock's hand has turned, in turns (0 to 1).
  double get handTurns {
    final frame = policy.clockFramePeriod;
    final hand = policy.clockHandPeriod;
    if (frame == null || hand == null) return 0;
    final turns = _$clock.value * frame.inMicroseconds / hand.inMicroseconds;
    return turns - turns.floorToDouble();
  }

  /// The pill now shows [to]: the change from what it showed runs its
  /// motion, unless [reduceMotion]; a cross-fade is held back while the row
  /// is [entering] where the policy says so. The clock turns while sending.
  void follow(
    DemoDelivery? to, {
    required bool entering,
    required bool reduceMotion,
  }) {
    final from = _$delivery;
    _$delivery = to;
    _followClock(reduceMotion: reduceMotion);
    if (from == to) return;
    final motion = reduceMotion ? null : _motionOf(from, to, entering);
    if (motion == null) {
      _$change.stop();
      if (_$moving != null) {
        _$moving = null;
        notifyListeners();
      }
      return;
    }
    _$moving = (kind: motion.kind, from: from, to: to);
    _$change
      ..duration = motion.duration
      ..forward(from: 0);
  }

  ({DemoStatusMotionKind kind, Duration duration})? _motionOf(
    DemoDelivery? from,
    DemoDelivery? to,
    bool entering,
  ) {
    if ((from, to, policy.checkSlide) case (
      DemoDelivery.sent,
      DemoDelivery.read,
      final slide?,
    )) {
      return (kind: DemoStatusMotionKind.checkSlide, duration: slide);
    }
    if ((to, policy.checkPop) case (
      DemoDelivery.sent || DemoDelivery.read,
      final pop?,
    )) {
      return (kind: DemoStatusMotionKind.checkPop, duration: pop);
    }
    if (policy.crossFade case final fade?
        when !(entering && policy.suppressedWhileEntering)) {
      return (kind: DemoStatusMotionKind.crossFade, duration: fade);
    }
    return null;
  }

  void _followClock({required bool reduceMotion}) {
    final period = policy.clockFramePeriod;
    final turns =
        period != null && !reduceMotion && _$delivery == DemoDelivery.sending;
    if (turns) {
      if (!_$clock.isAnimating) {
        _$clock
          ..duration = period
          ..repeat();
      }
      return;
    }
    if (_$clock.isAnimating || _$clock.value != 0) {
      _$clock
        ..stop()
        ..value = 0;
    }
  }

  void _onChangeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _$moving = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _$change.dispose();
    _$clock.dispose();
    super.dispose();
  }
}

/// The time pill's meta of the user's own message, moving between its
/// statuses as the platform does ([DemoStatusMotion]); another's message
/// shows its time alone.
///
/// A skin over [DemoStatusMotion]: it owns the tickers, hands each status
/// it is built with to the motion, and lets [DemoMessageMeta] paint it.
class DemoDeliveryMeta extends StatefulWidget {
  /// The meta of a message sent at [createdAt], its status [delivery].
  const DemoDeliveryMeta({
    required this.createdAt,
    required this.color,
    required this.delivery,
    required this.edited,
    this.editedOpacity = 1,
    this.policy,
    super.key,
  });

  /// When the message was sent.
  final DateTime createdAt;

  /// The meta's colour.
  final Color color;

  /// The status of the user's own message, null for another's.
  final DemoDelivery? delivery;

  /// Whether the message was edited.
  final bool edited;

  /// The opacity of the "edited" label.
  final double editedOpacity;

  /// The motion's values, the running platform's unless given.
  final DemoStatusMotionPolicy? policy;

  @override
  State<DemoDeliveryMeta> createState() => _DemoDeliveryMetaState();
}

class _DemoDeliveryMetaState extends State<DemoDeliveryMeta>
    with TickerProviderStateMixin {
  late final DemoStatusMotion _motion = DemoStatusMotion(
    vsync: this,
    policy: widget.policy ?? DemoStatusMotionPolicy.platform(),
    initial: widget.delivery,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(DemoDeliveryMeta oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delivery != widget.delivery) _follow();
  }

  void _follow() => _motion.follow(
    widget.delivery,
    entering: DemoRowEntering.of(context),
    reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
  );

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DemoMessageMeta(
    createdAt: widget.createdAt,
    color: widget.color,
    delivery: widget.delivery,
    edited: widget.edited,
    editedOpacity: widget.editedOpacity,
    motion: _motion,
  );
}

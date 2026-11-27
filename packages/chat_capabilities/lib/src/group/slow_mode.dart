import 'package:meta/meta.dart';

/// The slow mode group of the chat capabilities: none, or one send unit per
/// interval, an album counting as one unit.
///
/// Two forms, so a wait or a pending send without an interval cannot be
/// built: [SlowMode.none] for a chat without slow mode and for users the
/// host exempts (admins, a bypass the user earned), and [SlowMode.active].
/// The value holds no clock: a consumer asks [canSendAt] with its own `now`,
/// so a countdown ticks without a new value.
@immutable
sealed class SlowMode {
  const SlowMode._();

  /// One send unit per [interval]; the next send waits for [nextSendAt]
  /// when set, and for a message still sending when [pending].
  const factory SlowMode.active({
    required Duration interval,
    DateTime? nextSendAt,
    bool pending,
  }) = SlowMode$Active;

  /// No slow mode: the user may send at any time.
  static const SlowMode none = SlowMode$None();

  /// Whether a slow mode applies.
  bool get isActive;

  /// Whether the user may send a unit at [now].
  bool canSendAt(DateTime now);

  /// How long the user waits at [now] for the next send time; zero when the
  /// time has come or there is none.
  ///
  /// A pending send is not a wait of known length, so it is not counted
  /// here.
  Duration remainingAt(DateTime now);
}

/// [SlowMode.none].
final class SlowMode$None extends SlowMode {
  /// No slow mode.
  const SlowMode$None() : super._();

  @override
  bool get isActive => false;

  @override
  bool canSendAt(DateTime now) => true;

  @override
  Duration remainingAt(DateTime now) => Duration.zero;

  @override
  bool operator ==(Object other) => other is SlowMode$None;

  @override
  int get hashCode => (SlowMode$None).hashCode;

  @override
  String toString() => 'SlowMode.none';
}

/// [SlowMode.active].
final class SlowMode$Active extends SlowMode {
  /// A slow mode of [interval].
  ///
  /// [interval] is above zero; `ChatCapabilities.brokenRules` names a value
  /// that breaks it (a const value cannot check a duration itself).
  const SlowMode$Active({
    required this.interval,
    this.nextSendAt,
    this.pending = false,
  }) : super._();

  /// The time between two send units.
  final Duration interval;

  /// When the user may send next; null when the user may send now.
  final DateTime? nextSendAt;

  /// Whether a message of the user's is still sending, which holds the next
  /// send until it settles.
  final bool pending;

  @override
  bool get isActive => true;

  /// The next send time itself is allowed.
  @override
  bool canSendAt(DateTime now) {
    if (pending) return false;
    return switch (nextSendAt) {
      final next? => !now.isBefore(next),
      null => true,
    };
  }

  @override
  Duration remainingAt(DateTime now) => switch (nextSendAt) {
    final next? when now.isBefore(next) => next.difference(now),
    _ => Duration.zero,
  };

  /// A copy with the given fields replaced; [clearNextSendAt] makes the next
  /// send free.
  SlowMode$Active copyWith({
    Duration? interval,
    DateTime? nextSendAt,
    bool clearNextSendAt = false,
    bool? pending,
  }) => SlowMode$Active(
    interval: interval ?? this.interval,
    nextSendAt: clearNextSendAt ? null : nextSendAt ?? this.nextSendAt,
    pending: pending ?? this.pending,
  );

  @override
  bool operator ==(Object other) =>
      other is SlowMode$Active &&
      other.interval == interval &&
      other.nextSendAt == nextSendAt &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(interval, nextSendAt, pending);

  @override
  String toString() =>
      'SlowMode.active(interval: $interval, nextSendAt: $nextSendAt, '
      'pending: $pending)';
}

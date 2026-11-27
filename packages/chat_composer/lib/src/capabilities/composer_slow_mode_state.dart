import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:meta/meta.dart';

/// Slow mode as the composer shows it at one moment: the chat's `SlowMode`
/// read at the composer's clock.
///
/// The countdown runs while [remaining] is above zero ([isCounting]). A
/// message still sending ([pending]) holds the send too, but starts no
/// countdown: its wait has no known length.
@immutable
final class ComposerSlowModeState {
  /// Slow mode of [interval] with [remaining] to wait for [nextSendAt].
  const ComposerSlowModeState({
    this.interval = Duration.zero,
    this.nextSendAt,
    this.remaining = Duration.zero,
    this.pending = false,
  });

  /// [slowMode] read at [now].
  factory ComposerSlowModeState.of(SlowMode slowMode, DateTime now) =>
      ComposerSlowModeState(
        interval: slowMode.interval,
        nextSendAt: slowMode.nextSendAt,
        remaining: slowMode.remainingAt(now),
        pending: slowMode.isActive && slowMode.pending,
      );

  /// No slow mode, or one that holds nothing now.
  static const free = ComposerSlowModeState();

  /// The tag of the [denial] of a send held only by a message still
  /// sending.
  static const pendingTag = 'slowModePending';

  /// The slow mode interval; zero without slow mode.
  final Duration interval;

  /// When the user may send next; null when there is no wait.
  final DateTime? nextSendAt;

  /// The wait left before the next send.
  final Duration remaining;

  /// Whether a message of the user's is still sending in slow mode.
  final bool pending;

  /// Whether the countdown runs.
  bool get isCounting => remaining > Duration.zero;

  /// Whether a send now is refused: during the countdown, or while a
  /// message is still sending.
  bool get holdsSend => isCounting || pending;

  /// Why a send now is refused, as the host's `onDenied(sendNow, …)` gets
  /// it, or null when it is not.
  ///
  /// During the countdown it is a restriction until the next send time, so
  /// the host can say how long is left; a message still sending alone is
  /// `other(`[pendingTag]`)`.
  DenialReason? get denial => switch (nextSendAt) {
    final until? when isCounting => DenialReason.restricted(until: until),
    _ when pending => const DenialReason.other(pendingTag),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is ComposerSlowModeState &&
      other.interval == interval &&
      other.nextSendAt == nextSendAt &&
      other.remaining == remaining &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(interval, nextSendAt, remaining, pending);

  @override
  String toString() =>
      'ComposerSlowModeState(interval: $interval, remaining: $remaining, '
      'pending: $pending)';
}

import 'package:chrome_foundation/chrome_foundation.dart'
    show ChromeCountdownTiming;
import 'package:flutter/foundation.dart';

/// Where the composer shows slow mode's countdown.
enum ComposerCountdownPlacement {
  /// In place of the primary action's glyph: the send button reads `m:ss`.
  primaryAction,

  /// As the placeholder of the empty field.
  placeholder,
}

/// How the primary action is drawn while a message of the user's is still
/// sending in slow mode (`SlowMode.pending`), which holds the next send.
enum ComposerPendingSend {
  /// Dimmed, still tappable: a tap reports the held send to the host.
  dimmed,

  /// Disabled: it takes no tap and the submit key does nothing.
  disabled,
}

/// How the composer draws slow mode: where the countdown shows, how often it
/// redraws, the primary action while a message is still sending, and
/// whether actions that start a send (`ActionDescriptor.heldBySlowMode`) are
/// held during the wait. Part of `ComposerDeniedForms`; the per-platform
/// defaults are [android], [ios] and [desktop].
///
/// The forms only draw. Which sends are held, the countdown itself and the
/// report of an early send are the controller's
/// (`ComposerController.slowMode`, `refuseEarlySend`).
@immutable
final class ComposerSlowModeForms {
  /// Slow mode forms with the given chrome.
  const ComposerSlowModeForms({
    required this.countdown,
    required this.refresh,
    required this.pendingSend,
    required this.holdsSendActions,
  });

  /// Android: the send button becomes the `m:ss` countdown, redrawn every
  /// 100 ms; while a message is still sending it is dimmed.
  static const android = ComposerSlowModeForms(
    countdown: ComposerCountdownPlacement.primaryAction,
    refresh: ChromeCountdownTiming.control,
    pendingSend: ComposerPendingSend.dimmed,
    holdsSendActions: false,
  );

  /// iOS: the countdown is the empty field's placeholder, redrawn every
  /// 0.5 s; the actions that start a send (attach) are dimmed and disabled
  /// during the wait. A send while a message is still sending is dimmed,
  /// as on Android.
  static const ios = ComposerSlowModeForms(
    countdown: ComposerCountdownPlacement.placeholder,
    refresh: ChromeCountdownTiming.placeholder,
    pendingSend: ComposerPendingSend.dimmed,
    holdsSendActions: true,
  );

  /// Desktop and the web: the send button shows `m:ss`, polled every
  /// 200 ms; while a message is still sending it is disabled.
  static const desktop = ComposerSlowModeForms(
    countdown: ComposerCountdownPlacement.primaryAction,
    refresh: ChromeCountdownTiming.polledControl,
    pendingSend: ComposerPendingSend.disabled,
    holdsSendActions: false,
  );

  /// Where the countdown shows.
  final ComposerCountdownPlacement countdown;

  /// How often the countdown redraws while it runs.
  final Duration refresh;

  /// How the primary action is drawn while a message is still sending.
  final ComposerPendingSend pendingSend;

  /// Whether actions marked `ActionDescriptor.heldBySlowMode` are dimmed
  /// and disabled while slow mode holds the next send.
  final bool holdsSendActions;

  @override
  bool operator ==(Object other) =>
      other is ComposerSlowModeForms &&
      other.countdown == countdown &&
      other.refresh == refresh &&
      other.pendingSend == pendingSend &&
      other.holdsSendActions == holdsSendActions;

  @override
  int get hashCode =>
      Object.hash(countdown, refresh, pendingSend, holdsSendActions);
}

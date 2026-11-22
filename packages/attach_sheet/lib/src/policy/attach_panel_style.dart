import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';

/// The haptic a platform plays for a refusal.
enum AttachHaptic {
  /// None.
  none,

  /// A light key tap.
  keyboardTap,

  /// The error pattern.
  error,
}

/// An entry of the send menu (a long-press on Send).
enum AttachSendMenuItem {
  /// Send without sound.
  silent,

  /// Schedule, with the host's picker.
  schedule,

  /// Send when the recipient is next online.
  whenOnline,

  /// Move the caption above or below the media.
  captionAbove,

  /// Send in high quality (a compressed photo over the standard side).
  highQuality,

  /// Hide every item under a spoiler, or show them all.
  spoiler,
}

/// An entry of the overflow menu in the sheet's header.
enum AttachOverflowItem {
  /// Open the system's own picker (nothing selected).
  openExternal,

  /// Send the selection as files, now.
  sendAsFiles,

  /// Send each item on its own, now.
  withoutGrouping,

  /// Hide every selected item under a spoiler, or show them all.
  spoiler,

  /// Switch between high and standard quality (the default is remembered).
  quality,

  /// Send in high quality, now.
  highQuality,

  /// Move the caption above or below the media.
  captionAbove,
}

/// How the send button's count bounces when it changes: it jumps to [up]
/// (count grew) or [down] (count fell), over [out] when given, then returns
/// to 1 over [back].
@immutable
final class AttachCountBounce {
  /// A bounce.
  const AttachCountBounce({
    required this.up,
    required this.down,
    required this.back,
    this.out,
  });

  /// The scale a growing count reaches.
  final double up;

  /// The scale a falling count reaches.
  final double down;

  /// How it gets there; null to jump.
  final MotionSpec? out;

  /// How it returns to 1.
  final MotionSpec back;
}

/// How the attach panel (caption field and send button) looks and behaves on
/// one platform family: plain values the sheet policy carries.
@immutable
final class AttachPanelStyle {
  /// A panel style.
  const AttachPanelStyle({
    required this.counterRemaining,
    required this.overLimitHaptic,
    required this.reveal,
    required this.revealRise,
    required this.sendButtonFromScale,
    required this.countBounce,
    required this.sendMenu,
    required this.overflow,
    required this.sendButtonSize,
    this.viewerSendShowsCount = true,
  });

  /// The counter shows once this many code points or fewer remain; null for
  /// no counter.
  final int? counterRemaining;

  /// The haptic of a send refused for a long caption.
  final AttachHaptic overLimitHaptic;

  /// How the panel comes in when something is selected and leaves when the
  /// selection empties.
  final MotionSpec reveal;

  /// How far below its place the panel starts as it comes in.
  final double revealRise;

  /// The scale the send button grows from as the panel comes in.
  final double sendButtonFromScale;

  /// Whether the send button in the picker viewer's caption bar carries the
  /// selection's count, as the sheet's does.
  final bool viewerSendShowsCount;

  /// How the count on the send button bounces.
  final AttachCountBounce countBounce;

  /// The send menu's entries, in order; each shows where its rule allows.
  final List<AttachSendMenuItem> sendMenu;

  /// The overflow menu's entries, in order; each shows where its rule
  /// allows.
  final List<AttachOverflowItem> overflow;

  /// The send button's diameter.
  final double sendButtonSize;
}

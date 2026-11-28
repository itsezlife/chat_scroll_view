import 'dart:ui' show Color, PointerDeviceKind;

import 'package:chrome_foundation/chrome_foundation.dart'
    show ChromeInputClass, ChromeTapTiming;
import 'package:flutter/foundation.dart';
import 'package:message_media/src/message_media_hit_part.dart';
import 'package:mpx_core/mpx_core.dart' show AssetLoadState, MediaStatusIcon;

/// Where a tap cancels an item that is loading, in normal mode.
enum MediaLoadingTap {
  /// Only on the status control; a tap on the picture opens the viewer.
  statusOnly,

  /// Anywhere on the picture, as on the status control.
  anywhere,
}

/// What a tap on a media part does in normal mode: what message media
/// performs for a `ChatBodyPartActivated` naming one of its items.
enum MediaPartAction {
  /// The host's viewer opens on the item (`MessageMediaView.onOpenViewer`).
  openViewer,

  /// The item's content downloads (the retry of a failed one too).
  download,

  /// The item's download stops, keeping the stages it reached.
  cancel,

  /// The item's hidden spoiler is revealed, and nothing else.
  reveal,

  /// Nothing: the part is the viewport's (the options affordance opens the
  /// message menu).
  none,
}

/// The cell-local hover highlight over an item under the mouse: a [color]
/// laid over the item, fading in and out over [duration].
@immutable
final class MediaHoverLook {
  /// A highlight of [color] fading over [duration].
  const MediaHoverLook({
    this.color = const Color(0x14000000),
    this.duration = const Duration(milliseconds: 200),
  });

  /// The colour laid over the hovered item.
  final Color color;

  /// How long the highlight takes to come in or go.
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is MediaHoverLook &&
      other.color == color &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(MediaHoverLook, color, duration);
}

/// How message media answers taps, the mouse and repeated activations in
/// normal mode, per platform family; message selection is the viewport's,
/// where every part toggles the message.
///
/// | | Android | iOS | Desktop | Web |
/// | --- | --- | --- | --- | --- |
/// | Tap on a loading item ([loadingTap]) | cancels through the status control only | cancels anywhere on the picture | cancels anywhere on the picture | cancels anywhere on the picture |
/// | Click cursor over a part ([clickCursor]) | no | no | yes, plain in selection | with a mouse ([hoverNeedsMouse]) |
/// | Hover ([hover]) | none | none | cell-local highlight, 200 ms | the same, with a mouse |
/// | Repeated activation ([activationGuard]) | dropped for 400 ms | the same | the same | the same |
///
/// A double tap acts as over any bubble on the platform and a long press,
/// a secondary click or the options affordance open the message menu: both
/// are the viewport's, not this policy's.
@immutable
final class MediaGesturePolicy {
  /// A policy with the given values; each defaults to Android's.
  const MediaGesturePolicy({
    this.loadingTap = MediaLoadingTap.statusOnly,
    this.clickCursor = false,
    this.hover,
    this.activationGuard = ChromeTapTiming.repeatGuard,
    this.hoverNeedsMouse = false,
  });

  /// Android: a loading picture opens the viewer, the status control
  /// cancels; no cursor, no hover.
  const MediaGesturePolicy.android() : this();

  /// iOS: a tap anywhere on a loading picture cancels it.
  const MediaGesturePolicy.ios() : this(loadingTap: MediaLoadingTap.anywhere);

  /// Desktop: a click anywhere on a loading picture cancels it, the click
  /// cursor over every part, and the hover highlight.
  const MediaGesturePolicy.desktop()
    : this(
        loadingTap: MediaLoadingTap.anywhere,
        clickCursor: true,
        hover: const MediaHoverLook(),
      );

  /// The web: the desktop's cursor and highlight, but only for a pointer of
  /// the mouse's input class; a tap is the same with any pointer.
  ///
  /// A browser runs on touch screens and with a mouse alike, and one device
  /// may have both, so the class comes from each hover event's pointer kind
  /// (`ChromeInputClass.fromPointerKind`), not from the platform: a hovering
  /// stylus or a touch screen shows no highlight and no click cursor.
  const MediaGesturePolicy.web()
    : this(
        loadingTap: MediaLoadingTap.anywhere,
        clickCursor: true,
        hover: const MediaHoverLook(),
        hoverNeedsMouse: true,
      );

  /// Where a tap cancels a loading item.
  final MediaLoadingTap loadingTap;

  /// Whether the mouse cursor turns into the click cursor over a part
  /// outside message selection.
  final bool clickCursor;

  /// The highlight over the item under the mouse, or null for none.
  final MediaHoverLook? hover;

  /// How long after an accepted activation of a message's media a further
  /// one is dropped (reported as `media` / `activationDropped`): a burst of
  /// taps opens the viewer once, and a double tap on the status control
  /// does not download and cancel at once.
  final Duration activationGuard;

  /// Whether [hover] and [clickCursor] answer only a pointer of the mouse's
  /// input class ([hoversWith]); otherwise any hovering pointer does.
  final bool hoverNeedsMouse;

  /// Whether a hovering pointer of [kind] gets [hover] and [clickCursor].
  ///
  /// A kind of no input class (`PointerDeviceKind.unknown`) counts as a
  /// mouse: hover events come from hovering devices.
  bool hoversWith(PointerDeviceKind kind) =>
      !hoverNeedsMouse ||
      (ChromeInputClass.fromPointerKind(kind) ?? ChromeInputClass.mouse) ==
          ChromeInputClass.mouse;

  /// What a normal-mode tap on [part] of an item in [state] does.
  ///
  /// The status control downloads content that waits for the user or failed
  /// and cancels one that loads; content cancels a load where [loadingTap]
  /// says so and opens the viewer otherwise.
  MediaPartAction actionOf(MediaPart part, AssetLoadState state) =>
      switch (part) {
        MediaPart.spoiler => MediaPartAction.reveal,
        MediaPart.options => MediaPartAction.none,
        MediaPart.status => switch (state.status().icon) {
          MediaStatusIcon.download => MediaPartAction.download,
          MediaStatusIcon.cancel => MediaPartAction.cancel,
          MediaStatusIcon.play ||
          MediaStatusIcon.pause ||
          MediaStatusIcon.none => MediaPartAction.openViewer,
        },
        MediaPart.content
            when loadingTap == MediaLoadingTap.anywhere &&
                state.transfer.isActive =>
          MediaPartAction.cancel,
        MediaPart.content => MediaPartAction.openViewer,
      };

  /// A copy with the given values replaced; [hover] is replaced only when
  /// [replaceHover] is set, so it can be cleared.
  MediaGesturePolicy copyWith({
    MediaLoadingTap? loadingTap,
    bool? clickCursor,
    MediaHoverLook? hover,
    bool replaceHover = false,
    Duration? activationGuard,
    bool? hoverNeedsMouse,
  }) => MediaGesturePolicy(
    loadingTap: loadingTap ?? this.loadingTap,
    clickCursor: clickCursor ?? this.clickCursor,
    hover: replaceHover || hover != null ? hover : this.hover,
    activationGuard: activationGuard ?? this.activationGuard,
    hoverNeedsMouse: hoverNeedsMouse ?? this.hoverNeedsMouse,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaGesturePolicy &&
      other.loadingTap == loadingTap &&
      other.clickCursor == clickCursor &&
      other.hover == hover &&
      other.activationGuard == activationGuard &&
      other.hoverNeedsMouse == hoverNeedsMouse;

  @override
  int get hashCode => Object.hash(
    MediaGesturePolicy,
    loadingTap,
    clickCursor,
    hover,
    activationGuard,
    hoverNeedsMouse,
  );
}

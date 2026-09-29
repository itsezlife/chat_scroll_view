import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar_theme.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// **Scrollbar preset**: the host's choice of scrollbar for the chat
/// viewport — either a scrollbar drawn by a [ChatScrollbarPainter], or none.
///
/// The scrollbar sits on the trailing edge of the scroll band (right in
/// left-to-right, left in right-to-left) and paints outside the edge-effect
/// transform. Its **track** stands for the known conversation span, its
/// **thumb** for the visible band. The viewport owns thumb position and
/// length, when the scrollbar is shown ([ChatScrollbarVisibility]), and
/// which presses it grabs ([ChatScrollbarGrab]); the painter owns only the
/// look.
///
/// No scrollbar is painted, and no press is grabbed, while the whole
/// conversation fits in the scroll band or the viewport shows its loading or
/// empty overlay.
///
/// Immutable and value-equal. Passing an equal preset to a live viewport
/// changes nothing, so a rebuild never interrupts a grab. An unequal preset
/// ends an active grab before the new preset takes over; the pointer that
/// held it scrolls nothing until it lifts.
@immutable
sealed class ChatScrollbar {
  /// A scrollbar drawn by [painter], shown per [visibility], grabbed per
  /// [grab] — see [ChatScrollbar$Painted].
  const factory ChatScrollbar({
    ChatScrollbarPainter painter,
    ChatScrollbarVisibility visibility,
    ChatScrollbarGrab grab,
  }) = ChatScrollbar$Painted;

  const ChatScrollbar._();

  /// No scrollbar — see [ChatScrollbar$None].
  const factory ChatScrollbar.none() = ChatScrollbar$None;
}

/// A scrollbar drawn by [painter], shown per [visibility], grabbed per
/// [grab].
///
/// The three parts are independent: [grab] reads the track and thumb rects
/// the viewport resolved from [painter]'s geometry, never what [painter]
/// drew, and [visibility] gates only touch grabs (a hidden scrollbar is
/// still live under a mouse — see [ChatScrollbarGrab]).
final class ChatScrollbar$Painted extends ChatScrollbar {
  /// A scrollbar drawn by [painter]; defaults to [ChatPillScrollbarPainter],
  /// always shown, with the default [ChatScrollbarGrab].
  const ChatScrollbar$Painted({
    this.painter = const ChatPillScrollbarPainter(),
    this.visibility = const ChatScrollbarVisibility.always(),
    this.grab = const ChatScrollbarGrab(),
  }) : super._();

  /// The look. Part of this preset's equality: give custom painters value
  /// equality (or reuse one instance), since an unequal painter makes the
  /// preset unequal and ends an active grab on every rebuild.
  final ChatScrollbarPainter painter;

  /// When the scrollbar is shown. The painter receives the resulting
  /// **scrollbar visibility** as [ChatScrollbarFrame.visibility].
  final ChatScrollbarVisibility visibility;

  /// Which presses and hovers the scrollbar claims, and what a press on the
  /// track does.
  final ChatScrollbarGrab grab;

  @override
  bool operator ==(Object other) =>
      other is ChatScrollbar$Painted &&
      other.painter == painter &&
      other.visibility == visibility &&
      other.grab == grab;

  @override
  int get hashCode =>
      Object.hash(ChatScrollbar$Painted, painter, visibility, grab);

  @override
  String toString() =>
      'ChatScrollbar(painter: $painter, visibility: $visibility, '
      'grab: $grab)';
}

/// No scrollbar: nothing is painted and no press is grabbed, so presses
/// along the trailing edge reach messages like any other.
final class ChatScrollbar$None extends ChatScrollbar {
  /// The absent scrollbar.
  const ChatScrollbar$None() : super._();

  @override
  bool operator ==(Object other) => other is ChatScrollbar$None;

  @override
  int get hashCode => (ChatScrollbar$None).hashCode;

  @override
  String toString() => 'ChatScrollbar.none()';
}

/// When a painted [ChatScrollbar] is shown: the source of its **scrollbar
/// visibility**, a factor in `[0, 1]` the painter receives as
/// [ChatScrollbarFrame.visibility]. At `0` the viewport does not call the
/// painter.
///
/// Scrollbar visibility is the scrollbar's own factor, separate from scroll
/// activity: the day header never reads it, and a day header that holds
/// scroll activity does not hold the scrollbar.
///
/// Immutable and value-equal, as part of the preset's equality. An unequal
/// visibility on a live viewport takes over from the value currently shown:
/// switching from [ChatScrollbarVisibility.always] to
/// [ChatScrollbarVisibility.autoHide] keeps the scrollbar shown and starts
/// the idle delay, the reverse shows it at once, and new auto-hide timings
/// apply from the next fade or hold.
@immutable
sealed class ChatScrollbarVisibility {
  const ChatScrollbarVisibility._();

  /// Shown whenever there is something to scroll — see
  /// [ChatScrollbarVisibility$Always].
  const factory ChatScrollbarVisibility.always() =
      ChatScrollbarVisibility$Always;

  /// Shown while the reader's position moves, hidden once it rests — see
  /// [ChatScrollbarVisibility$AutoHide].
  const factory ChatScrollbarVisibility.autoHide({
    Duration idleDelay,
    Duration navigationIdleDelay,
    Duration fadeIn,
    Duration fadeOut,
    Curve curve,
  }) = ChatScrollbarVisibility$AutoHide;
}

/// Visibility `1` whenever there is something to scroll.
///
/// A grab's release settle runs over 250 ms along [Curves.easeOut].
final class ChatScrollbarVisibility$Always extends ChatScrollbarVisibility {
  /// The always-shown scrollbar.
  const ChatScrollbarVisibility$Always() : super._();

  @override
  bool operator ==(Object other) => other is ChatScrollbarVisibility$Always;

  @override
  int get hashCode => (ChatScrollbarVisibility$Always).hashCode;

  @override
  String toString() => 'ChatScrollbarVisibility.always()';
}

/// Visibility that rises when the reader's position in the conversation
/// changes and falls after an idle delay.
///
/// The viewport opens with the scrollbar hidden. Then:
///
/// - **Held** (eased to `1` over [fadeIn], no hide pending) while the list
///   moves under a drag, a fling, the mouse wheel, or span auto-scroll, and
///   while a scrollbar grab holds the pointer. A finger resting mid-drag
///   keeps the hold. Once nothing moves the list and no grab is held, the
///   scrollbar stays shown for [idleDelay], then eases to `0` over
///   [fadeOut].
/// - **Pulsed** (shown, then hidden after a delay unless held) by a
///   `scrollBy` step, the keyboard's included, after [idleDelay]; and by
///   host navigation — a jump, a center-band jump, an animated scroll to a
///   message, or a self-sent message pulling the reader to the tail — after
///   [navigationIdleDelay]. An animated scroll holds while it runs, then
///   waits [navigationIdleDelay]. The jumps a grab makes while it moves the
///   list are part of the grab and do not pulse.
/// - **Silent** for changes that only reshape the thumb: following the
///   tail as messages arrive there, history loading around the band, anchor
///   renormalization, delete recovery that keeps the band in place, inset
///   and keyboard changes, and row chrome holds.
///
/// Fades advance on a viewport ticker and pause while the viewport's
/// `TickerMode` is off. A grab's release settle runs over [fadeOut] along
/// [curve].
final class ChatScrollbarVisibility$AutoHide extends ChatScrollbarVisibility {
  /// Auto-hide; the defaults show for 1000 ms after the list rests and
  /// 1500 ms after host navigation, fading in and out over 250 ms along
  /// [Curves.easeOut].
  const ChatScrollbarVisibility$AutoHide({
    this.idleDelay = const Duration(milliseconds: 1000),
    this.navigationIdleDelay = const Duration(milliseconds: 1500),
    this.fadeIn = const Duration(milliseconds: 250),
    this.fadeOut = const Duration(milliseconds: 250),
    this.curve = Curves.easeOut,
  }) : super._();

  /// How long the scrollbar stays shown once the list rests after user
  /// motion, a `scrollBy` step, or a grab's release.
  final Duration idleDelay;

  /// How long the scrollbar stays shown after host navigation lands.
  final Duration navigationIdleDelay;

  /// Ease from the current visibility to `1`.
  final Duration fadeIn;

  /// Ease from the current visibility to `0`; also the length of a grab's
  /// release settle.
  final Duration fadeOut;

  /// Easing of both fades and of a grab's release settle. Part of this
  /// preset's equality: most curves compare by identity, so pass a `const`
  /// curve (or reuse one instance) — a fresh curve on every rebuild makes
  /// the preset unequal and ends an active grab.
  final Curve curve;

  @override
  bool operator ==(Object other) =>
      other is ChatScrollbarVisibility$AutoHide &&
      other.idleDelay == idleDelay &&
      other.navigationIdleDelay == navigationIdleDelay &&
      other.fadeIn == fadeIn &&
      other.fadeOut == fadeOut &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(
    ChatScrollbarVisibility$AutoHide,
    idleDelay,
    navigationIdleDelay,
    fadeIn,
    fadeOut,
    curve,
  );

  @override
  String toString() =>
      'ChatScrollbarVisibility.autoHide(idleDelay: $idleDelay, '
      'navigationIdleDelay: $navigationIdleDelay, fadeIn: $fadeIn, '
      'fadeOut: $fadeOut, curve: $curve)';
}

/// **Scrollbar grab**: which presses and hovers a painted [ChatScrollbar]
/// takes away from message scrolling, and what a grab does.
///
/// A closed behavior with tunable parameters. The rules follow the pointer
/// kind of each event — a touchscreen laptop gets touch rules for touch and
/// mouse rules for the mouse under one preset. Every target is measured
/// from the track and thumb rects the viewport resolved for the painter
/// ([ChatScrollbarFrame]), never from what the painter drew. No press is
/// claimed and nothing is hovered while no scrollbar is resolved: the
/// conversation fits in the scroll band, or the viewport shows its loading
/// or empty overlay.
///
/// ## Touch and stylus
///
/// A touch or stylus press grabs only while the scrollbar is shown
/// (visibility above `0` at the press) and only inside the **touch
/// target**: [touchTargetWidth] in from the viewport's trailing edge, over
/// the thumb grown to at least [touchTargetMinHeight] around its centre.
/// Every other touch press — on a hidden scrollbar, on the track beside the
/// thumb, just outside the target — is declined: a swipe that starts near
/// the edge scrolls the list, and a tap or long-press there reaches the
/// message under it. [trackPress] never applies to touch.
///
/// ## Mouse and trackpad
///
/// The **strip**, [stripWidth] in from the trailing edge over the track's
/// vertical span, is live even while the scrollbar is hidden. Hovering it
/// holds the scrollbar shown (revealing a hidden one), sets
/// [ChatScrollbarFrame.hoverFactor] to `1`, and shows the basic arrow
/// cursor over whatever lies beneath; leaving it drops
/// the hover factor to `0` and starts the idle delay. The wheel over the
/// strip scrolls messages as it does anywhere else. A primary-button press
/// on the thumb grabs; a primary-button press on the track beside the thumb
/// does what [trackPress] says. Other buttons are declined.
///
/// Both the strip and the touch target reach at least to the track's far
/// edge from the trailing side, so a painter wider than [stripWidth] or
/// [touchTargetWidth] stays grabbable across its whole track, and a thinner
/// painter never shrinks either target.
///
/// ## Ownership
///
/// A grab starts only on a fresh press: one that goes down while no other
/// pointer is down on the viewport — never during a span gesture, a list
/// drag, a desktop drag selection, a press that caught a fling or edge
/// spring, or another grab. A pointer on something drawn above the
/// viewport, such as a text selection handle or a message menu session's
/// dismiss layer, never reaches the scrollbar: a press on the strip while a
/// message menu is open dismisses the menu and does not grab.
///
/// A grab cancels a fling in flight and releases a held navigation
/// placement. It then owns its pointer until release: no tap, long-press,
/// span gesture, secondary tap, or list drag fires from it. It holds the
/// scrollbar shown until the pointer lifts. Declined presses reach messages
/// exactly as if there were no scrollbar.
///
/// ## Drag
///
/// - A press on the thumb keeps the point it grabbed: nothing moves until
///   the pointer does.
/// - While grabbed, the thumb is painted exactly under the pointer, with
///   the length it had at the press. The list follows: the thumb's place on
///   the track maps linearly onto message ids across the known span, and
///   the scroll band's top edge lands at that position — inside a message
///   when the position falls inside one, so dragging through a tall message
///   moves through it continuously. Each move reports a jump to the
///   controller's jump listeners and fetches unloaded history the same way
///   a jump does.
/// - On release the thumb eases back to where the list's own position puts
///   it, over the preset visibility's fade-out and curve (250 ms,
///   [Curves.easeOut] under [ChatScrollbarVisibility.always]). The two can
///   differ, because the list's position weighs how many messages fit in
///   the band where it landed.
///
/// Immutable and value-equal, as part of the preset's equality.
@immutable
final class ChatScrollbarGrab {
  /// Grab rules; the defaults give a 12 px mouse strip, a 32 × 48 px touch
  /// target, and a track press that centres the thumb.
  const ChatScrollbarGrab({
    this.stripWidth = 12,
    this.touchTargetWidth = 32,
    this.touchTargetMinHeight = 48,
    this.trackPress = ChatScrollbarTrackPress.centerThumb,
  }) : assert(stripWidth > 0, 'stripWidth must be positive'),
       assert(touchTargetWidth > 0, 'touchTargetWidth must be positive'),
       assert(
         touchTargetMinHeight >= 0,
         'touchTargetMinHeight must not be negative',
       );

  /// Width of the mouse and trackpad strip, in from the viewport's trailing
  /// edge.
  final double stripWidth;

  /// Width of the touch target, in from the viewport's trailing edge.
  final double touchTargetWidth;

  /// Shortest the touch target gets along the track. A shorter thumb gets
  /// a target of this height centred on it, reaching past the track's ends
  /// when the thumb rests at one; a longer thumb is its own target height.
  final double touchTargetMinHeight;

  /// What a mouse or trackpad press on the track beside the thumb does.
  final ChatScrollbarTrackPress trackPress;

  @override
  bool operator ==(Object other) =>
      other is ChatScrollbarGrab &&
      other.stripWidth == stripWidth &&
      other.touchTargetWidth == touchTargetWidth &&
      other.touchTargetMinHeight == touchTargetMinHeight &&
      other.trackPress == trackPress;

  @override
  int get hashCode => Object.hash(
    stripWidth,
    touchTargetWidth,
    touchTargetMinHeight,
    trackPress,
  );

  @override
  String toString() =>
      'ChatScrollbarGrab(stripWidth: $stripWidth, '
      'touchTargetWidth: $touchTargetWidth, '
      'touchTargetMinHeight: $touchTargetMinHeight, '
      'trackPress: $trackPress)';
}

/// What a mouse or trackpad press on the track beside the thumb does; see
/// [ChatScrollbarGrab.trackPress].
enum ChatScrollbarTrackPress {
  /// Grabs: the thumb centres on the pointer at once, the list jumps to
  /// match, and the grab continues from there as if the press had landed on
  /// the thumb's centre.
  centerThumb,

  /// Declines the press, which reaches the message under it as if there
  /// were no scrollbar.
  fallThrough,
}

/// What a [ChatScrollbarPainter] draws in one frame, in viewport-local
/// pixels.
///
/// Resolved by the viewport once per paint, including paints where the
/// scrollbar is hidden and the painter is not called. Grab hit-testing reads
/// the same [trackRect] and [thumbRect], so presses land on what the
/// viewport handed the painter no matter what the painter drew.
@immutable
final class ChatScrollbarFrame {
  /// A frame with [trackRect] and [thumbRect], resting unless the factors
  /// say otherwise.
  const ChatScrollbarFrame({
    required this.trackRect,
    required this.thumbRect,
    required this.textDirection,
    this.visibility = 1.0,
    this.hoverFactor = 0.0,
    this.grabFactor = 0.0,
  });

  /// The track's full travel: [ChatScrollbarPainter.trackThickness] wide,
  /// [ChatScrollbarPainter.crossAxisMargin] in from the trailing edge, and
  /// [ChatScrollbarPainter.mainAxisMargin] in from the scroll band's top and
  /// bottom.
  final Rect trackRect;

  /// The thumb: as wide as [trackRect] and always inside it. At rest its
  /// length is the visible band's share of the known span, floored at
  /// [ChatScrollbarPainter.minThumbLength], and its offset along the track
  /// is the band's place in that span. While grabbed it sits under the
  /// pointer with the length it had at the press; after the grab it eases
  /// back to the resting rect.
  final Rect thumbRect;

  /// Reading direction; the trailing edge is on the right in
  /// [TextDirection.ltr] and on the left in [TextDirection.rtl].
  final TextDirection textDirection;

  /// **Scrollbar visibility** in `[0, 1]`: how shown the scrollbar is, per
  /// the preset's [ChatScrollbarVisibility]. A painter receives no frame
  /// while it is `0`.
  final double visibility;

  /// How far a hovering pointer has engaged the scrollbar, in `[0, 1]`: `1`
  /// while a mouse or trackpad pointer rests on the strip (see
  /// [ChatScrollbarGrab]).
  final double hoverFactor;

  /// How far a grab has engaged the scrollbar, in `[0, 1]`: `1` while a
  /// pointer holds it.
  final double grabFactor;

  @override
  bool operator ==(Object other) =>
      other is ChatScrollbarFrame &&
      other.trackRect == trackRect &&
      other.thumbRect == thumbRect &&
      other.textDirection == textDirection &&
      other.visibility == visibility &&
      other.hoverFactor == hoverFactor &&
      other.grabFactor == grabFactor;

  @override
  int get hashCode => Object.hash(
    trackRect,
    thumbRect,
    textDirection,
    visibility,
    hoverFactor,
    grabFactor,
  );

  @override
  String toString() =>
      'ChatScrollbarFrame(trackRect: $trackRect, thumbRect: $thumbRect, '
      'textDirection: $textDirection, visibility: $visibility, '
      'hoverFactor: $hoverFactor, grabFactor: $grabFactor)';
}

/// **Scrollbar painter**: the host-replaceable look of the scrollbar.
///
/// The viewport reads the geometry getters to resolve a [ChatScrollbarFrame],
/// then calls [paint] with it on every viewport paint while the scrollbar's
/// visibility is above `0`. Hit-testing reads that frame's rects, never what
/// [paint] drew, so a custom look cannot move where presses land.
///
/// The geometry getters are read once per paint and must stay constant for a
/// given painter value. [paint] must be pure and cheap: it runs inside the
/// viewport's own paint, on every scroll frame.
abstract class ChatScrollbarPainter {
  /// Const constructor for subclasses.
  const ChatScrollbarPainter();

  /// Width of [ChatScrollbarFrame.trackRect] and
  /// [ChatScrollbarFrame.thumbRect]: the widest this painter ever draws.
  double get trackThickness;

  /// Gap between the viewport's trailing edge and the track.
  double get crossAxisMargin;

  /// Gap between each end of the scroll band and the track. Shortens the
  /// track, and so the thumb's travel, by twice this value.
  double get mainAxisMargin;

  /// Shortest thumb the viewport resolves. A thumb that would be at least as
  /// long as the track leaves nothing to travel, and no scrollbar is shown.
  double get minThumbLength;

  /// Draws [frame] onto [canvas] in viewport-local coordinates, coloured
  /// from [theme].
  void paint(
    Canvas canvas,
    ChatScrollbarFrame frame,
    ChatScrollbarThemeData theme,
  );

  /// Whether replacing [oldPainter] with this painter changes what [paint]
  /// draws or what the geometry getters return. Defaults to `true`.
  ///
  /// Consulted only when the viewport's preset changes to an unequal value
  /// that still uses a painter of the same type; a different painter type
  /// always repaints. Returning `false` keeps the previous frame — pixels
  /// and grab rects alike — until the viewport next paints.
  bool shouldRepaint(covariant ChatScrollbarPainter oldPainter) => true;
}

/// The default [ChatScrollbarPainter]: a fully rounded pill track with a
/// pill thumb on top.
///
/// Both pills hug the trailing side of their rects and share one thickness,
/// lerped from [thickness] to [grabbedThickness] by the grab factor. The
/// thumb colour lerps from [ChatScrollbarThemeData.thumbColor] to
/// [ChatScrollbarThemeData.thumbDraggingColor] by the same factor; the track
/// uses [ChatScrollbarThemeData.trackColor]. Visibility scales both fills'
/// alpha.
@immutable
final class ChatPillScrollbarPainter extends ChatScrollbarPainter {
  /// Pill painter; the defaults draw a 4 px bar, 6 px while grabbed, 4 px in
  /// from the trailing edge and the scroll band ends.
  const ChatPillScrollbarPainter({
    this.paintsTrack = true,
    this.thickness = 4,
    this.grabbedThickness = 6,
    this.minThumbLength = 16,
    this.crossAxisMargin = 4,
    this.mainAxisMargin = 4,
  }) : assert(thickness > 0, 'thickness must be positive'),
       assert(grabbedThickness > 0, 'grabbedThickness must be positive'),
       assert(minThumbLength > 0, 'minThumbLength must be positive'),
       assert(crossAxisMargin >= 0, 'crossAxisMargin must not be negative'),
       assert(mainAxisMargin >= 0, 'mainAxisMargin must not be negative');

  /// Whether the track pill is drawn under the thumb.
  final bool paintsTrack;

  /// Pill thickness at rest.
  final double thickness;

  /// Pill thickness while grabbed.
  final double grabbedThickness;

  @override
  final double minThumbLength;

  @override
  final double crossAxisMargin;

  @override
  final double mainAxisMargin;

  @override
  double get trackThickness => math.max(thickness, grabbedThickness);

  @override
  void paint(
    Canvas canvas,
    ChatScrollbarFrame frame,
    ChatScrollbarThemeData theme,
  ) {
    final width = lerpDouble(thickness, grabbedThickness, frame.grabFactor)!;
    final radius = Radius.circular(width / 2);
    RRect pill(Rect rect) =>
        RRect.fromRectAndRadius(switch (frame.textDirection) {
          TextDirection.ltr => Rect.fromLTRB(
            rect.right - width,
            rect.top,
            rect.right,
            rect.bottom,
          ),
          TextDirection.rtl => Rect.fromLTRB(
            rect.left,
            rect.top,
            rect.left + width,
            rect.bottom,
          ),
        }, radius);
    Paint fill(Color color) =>
        _fill..color = color.withValues(alpha: color.a * frame.visibility);

    if (paintsTrack) {
      canvas.drawRRect(pill(frame.trackRect), fill(theme.trackColor));
    }
    canvas.drawRRect(
      pill(frame.thumbRect),
      fill(
        Color.lerp(
          theme.thumbColor,
          theme.thumbDraggingColor,
          frame.grabFactor,
        )!,
      ),
    );
  }

  /// One fill reused across paints: a const painter holds no state, and
  /// this runs on every scroll frame.
  static final Paint _fill = Paint();

  @override
  bool shouldRepaint(ChatPillScrollbarPainter oldPainter) => oldPainter != this;

  @override
  bool operator ==(Object other) =>
      other is ChatPillScrollbarPainter &&
      other.paintsTrack == paintsTrack &&
      other.thickness == thickness &&
      other.grabbedThickness == grabbedThickness &&
      other.minThumbLength == minThumbLength &&
      other.crossAxisMargin == crossAxisMargin &&
      other.mainAxisMargin == mainAxisMargin;

  @override
  int get hashCode => Object.hash(
    paintsTrack,
    thickness,
    grabbedThickness,
    minThumbLength,
    crossAxisMargin,
    mainAxisMargin,
  );

  @override
  String toString() =>
      'ChatPillScrollbarPainter(paintsTrack: $paintsTrack, '
      'thickness: $thickness, grabbedThickness: $grabbedThickness, '
      'minThumbLength: $minThumbLength, crossAxisMargin: $crossAxisMargin, '
      'mainAxisMargin: $mainAxisMargin)';
}

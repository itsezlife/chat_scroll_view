import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// **Scrollbar preset**: the host's choice of scrollbar for the chat
/// viewport — either a scrollbar drawn by a [ChatScrollbarPainter], or none.
///
/// The scrollbar sits on the trailing edge of the scroll band (right in
/// left-to-right, left in right-to-left) and paints outside the edge-effect
/// transform. Its **track** stands for the known conversation span, its
/// **thumb** for the visible band. The viewport owns thumb position and
/// length, when the scrollbar is shown, and which presses it grabs; the
/// painter owns only the look.
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
  /// A scrollbar drawn by [painter] — see [ChatScrollbar$Painted].
  const factory ChatScrollbar({ChatScrollbarPainter painter}) =
      ChatScrollbar$Painted;

  const ChatScrollbar._();

  /// No scrollbar — see [ChatScrollbar$None].
  const factory ChatScrollbar.none() = ChatScrollbar$None;
}

/// A scrollbar drawn by [painter].
///
/// Always shown while there is something to scroll. A pointer that goes down
/// within 20 px of the viewport's trailing edge, over the track's vertical
/// span, grabs the scrollbar until it lifts:
///
/// - A press on the thumb keeps the point it grabbed: nothing moves until
///   the pointer does. A press on the track beside the thumb centres the
///   thumb on the pointer at once and continues the same way.
/// - While grabbed, the thumb is painted exactly under the pointer, with
///   the length it had at the press. The list follows: the thumb's place on
///   the track maps linearly onto message ids across the known span, and
///   the scroll band's top edge lands at that position — inside a message
///   when the position falls inside one, so dragging through a tall message
///   moves through it continuously.
/// - On release the thumb eases back over 250 ms to where the list's own
///   position puts it. The two can differ, because the list's position
///   weighs how many messages fit in the band where it landed.
///
/// A grab starts only on a fresh press, cancels a fling in flight, releases
/// a held navigation placement, and never reaches message selection, taps,
/// secondary taps, or the list drag. Each move the list follows reports a
/// jump to the controller's jump listeners, and fetches unloaded history
/// the same way a jump does.
final class ChatScrollbar$Painted extends ChatScrollbar {
  /// A scrollbar drawn by [painter]; defaults to [ChatPillScrollbarPainter].
  const ChatScrollbar$Painted({
    this.painter = const ChatPillScrollbarPainter(),
  }) : super._();

  /// The look. Part of this preset's equality: give custom painters value
  /// equality (or reuse one instance), since an unequal painter makes the
  /// preset unequal and ends an active grab on every rebuild.
  final ChatScrollbarPainter painter;

  @override
  bool operator ==(Object other) =>
      other is ChatScrollbar$Painted && other.painter == painter;

  @override
  int get hashCode => Object.hash(ChatScrollbar$Painted, painter);

  @override
  String toString() => 'ChatScrollbar(painter: $painter)';
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

/// What a [ChatScrollbarPainter] draws in one frame, in viewport-local
/// pixels.
///
/// Resolved by the viewport once per paint. Grab hit-testing reads the same
/// [trackRect] and [thumbRect], so presses land on what the viewport handed
/// the painter no matter what the painter drew.
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

  /// **Scrollbar visibility** in `[0, 1]`: how shown the scrollbar is.
  final double visibility;

  /// How far a hovering pointer has engaged the scrollbar, in `[0, 1]`.
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
/// then calls [paint] with it on every viewport paint while a scrollbar is
/// shown. Hit-testing reads that frame's rects, never what [paint] drew, so a
/// custom look cannot move where presses land.
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
    RRect pill(Rect rect) => RRect.fromRectAndRadius(
      switch (frame.textDirection) {
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
      },
      radius,
    );
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
  bool shouldRepaint(ChatPillScrollbarPainter oldPainter) =>
      oldPainter != this;

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

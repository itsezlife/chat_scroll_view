import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// The text side of a media bubble at one moment of a transition: the
/// caption's size, how present it is and how far above the media it sits.
///
/// Everything else the bubble's geometry depends on is the media's
/// interpolated size, so a transition lerps this between legs
/// ([MediaBubbleText.lerp]) and computes the geometry from it and the
/// frame's media ([MediaBubbleGeometry.compute]): the bubble then always
/// fits the media painted in it.
@immutable
final class MediaBubbleText {
  /// A caption of [caption] size, [presence] shown, [above] the media.
  const MediaBubbleText({
    this.caption = Size.zero,
    this.presence = 0,
    this.above = 0,
  }) : assert(presence >= 0 && presence <= 1, 'presence is in [0, 1].'),
       assert(above >= 0 && above <= 1, 'above is in [0, 1].');

  /// The text [t] of the way from [a] to [b].
  factory MediaBubbleText.lerp(
    MediaBubbleText a,
    MediaBubbleText b,
    double t,
  ) => MediaBubbleText(
    caption: Size.lerp(a.caption, b.caption, t)!,
    presence: lerpDouble(a.presence, b.presence, t)!.clamp(0.0, 1.0),
    above: lerpDouble(a.above, b.above, t)!.clamp(0.0, 1.0),
  );

  /// No caption.
  static const none = MediaBubbleText();

  /// The caption's laid-out size (of the caption leaving, while it fades).
  final Size caption;

  /// 1 with a caption, 0 without; between while one comes or goes.
  final double presence;

  /// 1 with the caption above the media, 0 below; between while
  /// `invertMedia` flips.
  final double above;

  @override
  bool operator ==(Object other) =>
      other is MediaBubbleText &&
      other.caption == caption &&
      other.presence == presence &&
      other.above == above;

  @override
  int get hashCode => Object.hash(caption, presence, above);

  @override
  String toString() => 'MediaBubbleText($caption, $presence, $above)';
}

/// Where a media bubble's parts sit, in the bubble's coordinates.
///
/// ## Stacking
///
/// Top to bottom: the header, the caption when above, the media, the
/// caption when below. The media keeps [compute]'s `mediaInset` from the
/// bubble's sides and from a bubble edge it touches; a text row keeps
/// `textPadding` (its top before it, its bottom after it unless more text
/// follows). The bubble is as wide as the media with its inset, or the
/// caption with its padding, whichever is wider; the header never widens
/// it (the host lays it out to the media's width and it truncates there).
@immutable
final class MediaBubbleGeometry {
  /// A geometry of the given rects.
  const MediaBubbleGeometry({
    required this.size,
    required this.media,
    required this.caption,
    this.header,
  });

  /// The parts of a bubble around media of [media] size, with [header]
  /// (null without one) and [text].
  ///
  /// A caption between present and absent, or between above and below,
  /// blends the geometries of its ends, so its rows grow, shrink and move
  /// continuously.
  factory MediaBubbleGeometry.compute({
    required Size media,
    required double mediaInset,
    required EdgeInsets textPadding,
    required MediaBubbleText text,
    Size? header,
  }) {
    MediaBubbleGeometry arrange({required bool present, required bool above}) =>
        MediaBubbleGeometry._arrange(
          media: media,
          inset: mediaInset,
          padding: textPadding,
          header: header,
          caption: text.caption,
          present: present,
          above: above,
        );
    final below = MediaBubbleGeometry.lerp(
      arrange(present: false, above: false),
      arrange(present: true, above: false),
      text.presence,
    );
    if (text.above == 0) return below;
    final over = MediaBubbleGeometry.lerp(
      arrange(present: false, above: true),
      arrange(present: true, above: true),
      text.presence,
    );
    return MediaBubbleGeometry.lerp(below, over, text.above);
  }

  /// The geometry [t] of the way from [a] to [b].
  factory MediaBubbleGeometry.lerp(
    MediaBubbleGeometry a,
    MediaBubbleGeometry b,
    double t,
  ) {
    if (t == 0) return a;
    if (t == 1) return b;
    return MediaBubbleGeometry(
      size: Size.lerp(a.size, b.size, t)!,
      media: Rect.lerp(a.media, b.media, t)!,
      caption: Rect.lerp(a.caption, b.caption, t)!,
      header: switch ((a.header, b.header)) {
        (final from?, final to?) => Rect.lerp(from, to, t),
        (_, final to) => to,
      },
    );
  }

  factory MediaBubbleGeometry._arrange({
    required Size media,
    required double inset,
    required EdgeInsets padding,
    required Size? header,
    required Size caption,
    required bool present,
    required bool above,
  }) {
    final hasMedia = !media.isEmpty;
    var y = 0.0;
    // What the previous row was: null at the bubble's top edge.
    bool? previousIsText;
    Rect? headerRect;
    late Rect captionRect;
    final Rect mediaRect;

    void text(Size size, void Function(Rect rect) place) {
      y += padding.top;
      place(Offset(padding.left, y) & size);
      y += size.height;
      previousIsText = true;
    }

    void captionRow() {
      if (!present) {
        // A caption on its way: no height, no padding, at its place.
        captionRect = Rect.fromLTWH(padding.left, y, caption.width, 0);
        return;
      }
      text(caption, (rect) => captionRect = rect);
    }

    if (header case final size?) text(size, (rect) => headerRect = rect);
    if (above) captionRow();
    if (hasMedia) {
      y += switch (previousIsText) {
        null => inset,
        true => padding.bottom,
        false => 0,
      };
      mediaRect = Offset(inset, y) & media;
      y += media.height;
      previousIsText = false;
    } else {
      mediaRect = Rect.fromLTWH(inset, y, 0, 0);
    }
    if (!above) captionRow();
    y += switch (previousIsText) {
      null => 0,
      true => padding.bottom,
      false => inset,
    };
    final width = math.max(
      hasMedia ? media.width + 2 * inset : 0.0,
      present ? caption.width + padding.horizontal : 0.0,
    );
    return MediaBubbleGeometry(
      size: Size(width, y),
      media: mediaRect,
      caption: captionRect,
      header: headerRect,
    );
  }

  /// The bubble's size.
  final Size size;

  /// The media's rect (its layout's origin at [Rect.topLeft]).
  final Rect media;

  /// The caption's rect; zero high without a caption.
  final Rect caption;

  /// The header's rect, or null without a header.
  final Rect? header;

  @override
  bool operator ==(Object other) =>
      other is MediaBubbleGeometry &&
      other.size == size &&
      other.media == media &&
      other.caption == caption &&
      other.header == header;

  @override
  int get hashCode => Object.hash(size, media, caption, header);

  @override
  String toString() =>
      'MediaBubbleGeometry($size, media: $media, caption: $caption, '
      'header: $header)';
}

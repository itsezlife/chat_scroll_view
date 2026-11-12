import 'dart:math' as math;

import 'package:content_model/content_model.dart' show ContentSize;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';
import 'package:panel_pages/src/preview/content_preview_item.dart';

/// Where a content preview draws its content, the emoji above it and its
/// menu, in the window's coordinates.
///
/// The preview's geometry, with
/// `M = min(width, height - insets)` where the insets are the window's top
/// and bottom padding:
///
/// - **Size.** A sticker or custom emoji is a square of `M / 1.8`; a GIF one
///   of `M - 40` ([gifInset]), fitted to its proportions inside it, with
///   corners of [gifRadius].
/// - **Centre.** Across the middle of the window; down at
///   `max(size / 2 + top + (emoji ? 40 : 0), (height - insets - keyboard) / 2)`,
///   where `keyboard` is the height assumed for a keyboard
///   ([defaultKeyboardHeight] until it knows better) and 40 is room for the
///   emoji above ([emojiRoom]); a GIF moves up from there by its swipe.
/// - **Emoji.** Its line begins [emojiGap] above the square, [emojiWidth]
///   wide, centred.
/// - **Menu.** Centred across, its top [menuGap] below the square.
///
/// Under a pointer (a desktop) the preview has its own sizes, whatever the
/// window: a sticker or custom emoji is a square of [pointerSide], a GIF is
/// fitted to its proportions inside a square of twice that, up or down, and
/// the square is in the middle of the window. A window smaller than the box
/// takes it down to `M`.
@immutable
final class ContentPreviewLayout {
  /// The layout in a window of [window] size with [padding] (its top and
  /// bottom count), for content of [kind] and pixel [contentSize], with an
  /// [emoji] line or not, and moved up by [swipe] (a GIF's, 0 or less).
  factory ContentPreviewLayout({
    required Size window,
    required EdgeInsets padding,
    required ContentPreviewKind kind,
    ContentSize? contentSize,
    bool emoji = false,
    double swipe = 0,
    double keyboardHeight = defaultKeyboardHeight,
    bool pointer = false,
  }) {
    final insets = padding.top + padding.bottom;
    final m = math.min(window.width, window.height - insets);
    if (pointer) {
      return ContentPreviewLayout._pointer(
        window: window,
        kind: kind,
        contentSize: contentSize,
        m: m,
      );
    }
    final side = switch (kind) {
      ContentPreviewKind.gif => m - gifInset,
      ContentPreviewKind.sticker || ContentPreviewKind.customEmoji => m / 1.8,
    };
    final centreY =
        math.max(
          side / 2 + padding.top + (emoji ? emojiRoom : 0),
          (window.height - insets - keyboardHeight) / 2,
        ) +
        swipe;
    final center = Offset(window.width / 2, centreY);
    final square = Rect.fromCenter(center: center, width: side, height: side);
    final extent = switch ((kind, contentSize)) {
      (ContentPreviewKind.gif, ContentSize(:final width, :final height))
          when width > 0 && height > 0 =>
        _fit(side, width / height),
      _ => Size.square(side),
    };
    return ContentPreviewLayout._(
      square: square,
      content: Rect.fromCenter(
        center: center,
        width: extent.width,
        height: extent.height,
      ),
      extent: extent,
      emoji: Rect.fromLTWH(
        window.width / 2 - emojiWidth / 2,
        square.top - emojiGap,
        emojiWidth,
        emojiGap,
      ),
      menuTop: square.bottom + menuGap,
    );
  }

  factory ContentPreviewLayout._pointer({
    required Size window,
    required ContentPreviewKind kind,
    required ContentSize? contentSize,
    required double m,
  }) {
    final side = math.min(m, switch (kind) {
      ContentPreviewKind.gif => 2 * pointerSide,
      ContentPreviewKind.sticker ||
      ContentPreviewKind.customEmoji => pointerSide,
    });
    final center = window.center(Offset.zero);
    final square = Rect.fromCenter(center: center, width: side, height: side);
    final extent = switch ((kind, contentSize)) {
      (ContentPreviewKind.gif, ContentSize(:final width, :final height))
          when width > 0 && height > 0 =>
        _fit(side, width / height),
      _ => Size.square(side),
    };
    return ContentPreviewLayout._(
      square: square,
      content: Rect.fromCenter(
        center: center,
        width: extent.width,
        height: extent.height,
      ),
      extent: extent,
      emoji: Rect.fromLTWH(
        window.width / 2 - emojiWidth / 2,
        square.top - emojiGap,
        emojiWidth,
        emojiGap,
      ),
      menuTop: square.bottom + menuGap,
    );
  }

  const ContentPreviewLayout._({
    required this.square,
    required this.content,
    required this.extent,
    required this.emoji,
    required this.menuTop,
  });

  /// The side of a sticker's or custom emoji's square under a pointer: 224.
  static const double pointerSide = 224;

  /// `M - 40`: how much narrower than `M` a GIF is.
  static const double gifInset = 40;

  /// The corner radius of a GIF: 6.
  static const double gifRadius = 6;

  /// 40 added to the topmost centre when an emoji line is drawn.
  static const double emojiRoom = 40;

  /// 30: how far above the square the emoji line begins.
  static const double emojiGap = 30;

  /// 200: the width the emoji line is ellipsized to.
  static const double emojiWidth = 200;

  /// 24: the emoji line's size.
  static const double emojiFontSize = 24;

  /// 24: the menu's top below the square.
  static const double menuGap = 24;

  /// 200 until a keyboard was measured.
  static const double defaultKeyboardHeight = 200;

  /// The square the content is drawn in.
  final Rect square;

  /// The content's own box: the square, or for a GIF its proportions fitted
  /// inside it.
  final Rect content;

  /// The size of [content], worked out from the window and the content alone:
  /// the same at every swipe, where [content]'s own size (its edges'
  /// difference) can drift in the last bits as the box moves. What the
  /// content is drawn at, so a drag never resizes it.
  final Size extent;

  /// The emoji line's box: [emojiWidth] wide, from [emojiGap] above the
  /// square to its top.
  final Rect emoji;

  /// The top of the menu.
  final double menuTop;

  static Size _fit(double side, double aspect) =>
      aspect >= 1 ? Size(side, side / aspect) : Size(side * aspect, side);
}

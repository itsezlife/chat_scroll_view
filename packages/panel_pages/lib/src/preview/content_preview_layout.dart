import 'dart:math' as math;

import 'package:content_model/content_model.dart' show ContentSize;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';
import 'package:panel_pages/src/preview/content_preview_item.dart';

/// Where a content preview draws its content, the emoji above it and its
/// menu, in the window's coordinates.
///
/// The reference client's geometry (`ContentPreviewViewer.onDraw`), with
/// `M = min(width, height - insets)` where the insets are the window's top
/// and bottom padding:
///
/// - **Size.** A sticker or custom emoji is a square of `M / 1.8`; a GIF one
///   of `M - 40` ([gifInset]), fitted to its proportions inside it, with
///   corners of [gifRadius].
/// - **Centre.** Across the middle of the window; down at
///   `max(size / 2 + top + (emoji ? 40 : 0), (height - insets - keyboard) / 2)`,
///   where `keyboard` is the height the reference assumes a keyboard has
///   ([defaultKeyboardHeight] until it knows better) and 40 is room for the
///   emoji above ([emojiRoom]); a GIF moves up from there by its swipe.
/// - **Emoji.** Its line begins [emojiGap] above the square, [emojiWidth]
///   wide, centred.
/// - **Menu.** Centred across, its top [menuGap] below the square.
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
  }) {
    final insets = padding.top + padding.bottom;
    final m = math.min(window.width, window.height - insets);
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
    final square = Rect.fromCenter(
      center: Offset(window.width / 2, centreY),
      width: side,
      height: side,
    );
    return ContentPreviewLayout._(
      square: square,
      content: switch ((kind, contentSize)) {
        (ContentPreviewKind.gif, ContentSize(:final width, :final height))
            when width > 0 && height > 0 =>
          _fit(square, width / height),
        _ => square,
      },
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
    required this.emoji,
    required this.menuTop,
  });

  /// `M - dp(40)`: how much narrower than `M` a GIF is.
  static const double gifInset = 40;

  /// `centerImage.setRoundRadius(dp(6))` for a GIF.
  static const double gifRadius = 6;

  /// `dp(40)` added to the topmost centre when an emoji line is drawn.
  static const double emojiRoom = 40;

  /// `dp(30)`: how far above the square the emoji line begins.
  static const double emojiGap = 30;

  /// `dp(200)`: the width the emoji line is ellipsized to.
  static const double emojiWidth = 200;

  /// `textPaint.setTextSize(dp(24))`: the emoji line's size.
  static const double emojiFontSize = 24;

  /// `y += dp(24)`: the menu's top below the square.
  static const double menuGap = 24;

  /// `keyboardHeight = dp(200)` until a keyboard was measured.
  static const double defaultKeyboardHeight = 200;

  /// The square the content is drawn in.
  final Rect square;

  /// The content's own box: the square, or for a GIF its proportions fitted
  /// inside it (`setAspectFit(true)`).
  final Rect content;

  /// The emoji line's box: [emojiWidth] wide, from [emojiGap] above the
  /// square to its top.
  final Rect emoji;

  /// The top of the menu.
  final double menuTop;

  static Rect _fit(Rect square, double aspect) {
    final width = aspect >= 1 ? square.width : square.width * aspect;
    final height = aspect >= 1 ? square.height / aspect : square.height;
    return Rect.fromCenter(center: square.center, width: width, height: height);
  }
}

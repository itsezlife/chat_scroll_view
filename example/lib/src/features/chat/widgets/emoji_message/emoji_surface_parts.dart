import 'dart:ui' show Rect;

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatMessageSurfacePart, ChatMessageSurfaceParts;
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_chrome.dart';
import 'package:flutter/painting.dart'
    show BorderRadius, RoundedRectangleBorder;

/// The painted parts of an emoji-only message, as the outline the message
/// menu's scrim leaves undimmed.
///
/// An emoji-only message has no bubble. The reference client opens its menu by
/// drawing the message again above a flat dim, so the glyphs or the sticker's
/// art, the time pill, the reply panel and each reaction chip stay bright and
/// what lies between them (the gap under a reply, the strip beside a short
/// pill, the corners of the row) stays dimmed (`Telegram`
/// `ChatActivity.java` 17630-17700; iOS lifts the same node, in
/// `ChatMessageAnimatedStickerItemNode`). One rounded rectangle around the lot
/// would read as a bubble.
///
/// Every rect is in the coordinates of the box the message reports as its
/// surface, which is also the stack the chrome is placed in. [art] is the
/// viewport body's `ChatEmojiGeometry.content`, the items' area or the
/// sticker's art, without the strip the chrome reserves under it: the pill is
/// a part of its own. A pill the platform does not show now (Desktop hides an
/// incoming one until the pointer is over it) is passed as null.
ChatMessageSurfaceParts emojiSurfaceParts({
  required EmojiChrome chrome,
  required Rect art,
  Rect? pill,
  Rect? header,
  List<Rect> reactions = const <Rect>[],
}) {
  ChatMessageSurfacePart rounded(Rect rect, double radius) =>
      ChatMessageSurfacePart(
        rect: rect,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      );

  return ChatMessageSurfaceParts(<ChatMessageSurfacePart>[
    // A sticker's art or a glyph run has no outline: its box is square.
    ChatMessageSurfacePart(rect: art),
    if (header != null) rounded(header, chrome.headerRadius),
    if (pill != null) rounded(pill, chrome.pillRadius(pill.height)),
    for (final chip in reactions) rounded(chip, chip.height / 2),
  ]);
}

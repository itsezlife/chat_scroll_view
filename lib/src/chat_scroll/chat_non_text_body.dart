import 'dart:ui' show Offset, Rect;

import 'package:chat_scroll_view/src/chat_scroll/chat_inline_hit.dart';

/// A message body that paints no selectable text: what a body registers with
/// `ChatSelectionController.putNonTextBody` instead of a markdown model.
///
/// The registration kind is the whole difference between the two bodies the
/// viewport ships. A text body (`ChatMarkdownBody`) puts a model on the
/// facade, and the facade then owns a character range over it. A non-text
/// body has nothing to select, so a long press on it is message selection
/// and Copy is the message's own; all it gives the facade is where its
/// activatable parts are, so that a tap on one is arbitrated with the rest of
/// the viewport's gestures. A body that shows media registers the same way.
abstract interface class ChatNonTextBody {
  /// The activatable part of the body under [globalOffset], or null for the
  /// rest of it. Evaluated at the time of the call: a body scrolls without
  /// rebuilding.
  ChatInlineHit? inlineHitAt(Offset globalOffset);

  /// The painted rectangle of the body in global coordinates, or null while
  /// it has none (not laid out, detached). Where a long press or a secondary
  /// click counts as being on the message when the host reported no surface.
  Rect? get globalBounds;
}

/// A [ChatNonTextBody] whose part is a sticker the host can command and place
/// an effect over: what `ChatEmojiBody` registers in its sticker layout.
///
/// The facade finds it by message id (`ChatSelectionController.replaySticker`,
/// `stickerRectOf`, `playRemoteInteraction`), so a host that draws over the
/// list or applies a peer's interaction needs no handle on the widget, and a
/// row that is recycled and mounted again is found again.
abstract interface class ChatStickerBody implements ChatNonTextBody {
  /// The rectangle the sticker is drawn in, in global coordinates, or null
  /// while it is not shown: not laid out, detached, or the host says the row
  /// is inactive. The host reads it again when it needs it; a row scrolls
  /// without rebuilding.
  Rect? get stickerGlobalRect;

  /// Plays the sticker's animation again and says whether it started.
  ///
  /// False while a pass is running (a pass is never rewound), when the sticker
  /// does not play on its own end, or while it is not shown.
  bool replay();
}

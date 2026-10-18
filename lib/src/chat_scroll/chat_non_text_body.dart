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

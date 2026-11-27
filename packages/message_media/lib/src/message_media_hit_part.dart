import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatBodyPartRole, ChatDiagnosablePart;
import 'package:content_model/content_model.dart' show MediaItemId;
import 'package:meta/meta.dart';

/// The part of a message's media a body part hit is on: what message media
/// puts in `ChatInlineHit.bodyPart`'s opaque `partId`, and what the host
/// reads back from `ChatBodyPartActivated.partId` and
/// `ChatMessageMenuRequest.partId`.
///
/// Sealed so the host's switch over it is exhaustive: a media item's part
/// ([MediaHitPart], also an item inside a link preview card) or the card's
/// own area ([LinkPreviewHitPart]).
@immutable
sealed class MessageMediaHitPart implements ChatDiagnosablePart {
  const MessageMediaHitPart();

  /// A hit on [part] of the media item [itemId].
  const factory MessageMediaHitPart.media(
    MediaItemId itemId, {
    required MediaPart part,
  }) = MediaHitPart;

  /// A hit on [zone] of the link preview card of message [messageId].
  const factory MessageMediaHitPart.linkPreview(
    int messageId, {
    required LinkPreviewZone zone,
  }) = LinkPreviewHitPart;

  /// How the viewport arbitrates a tap on this part: the options affordance
  /// opens the message menu, every other part is the body's to act on.
  ChatBodyPartRole get role;
}

/// Which part of a media item a [MediaHitPart] is on.
enum MediaPart {
  /// The picture or the file row: opens the viewer, or cancels a load where
  /// the cell policy says so.
  content,

  /// The status control: download, cancel or retry.
  status,

  /// A hidden spoiler over the item: a tap only reveals it.
  spoiler,

  /// The options affordance: opens the message menu for the item.
  options,
}

/// Which area of a link preview card a [LinkPreviewHitPart] is on.
enum LinkPreviewZone {
  /// The card's text area, the site name included: the host opens the URL.
  body,

  /// The card's action button: the host runs the button's action.
  button,
}

/// A body part hit on [part] of the media item [itemId].
final class MediaHitPart extends MessageMediaHitPart {
  /// A hit on [part] of [itemId].
  const MediaHitPart(this.itemId, {required this.part});

  /// The item hit.
  final MediaItemId itemId;

  /// Which part of the item.
  final MediaPart part;

  @override
  ChatBodyPartRole get role => switch (part) {
    MediaPart.options => ChatBodyPartRole.menu,
    MediaPart.content ||
    MediaPart.status ||
    MediaPart.spoiler => ChatBodyPartRole.activate,
  };

  @override
  String get diagnosticName => part.name;

  @override
  String? get diagnosticItemId => itemId.toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaHitPart && other.itemId == itemId && other.part == part;

  @override
  int get hashCode => Object.hash(MediaHitPart, itemId, part);

  @override
  String toString() => 'MediaHitPart($itemId, part: ${part.name})';
}

/// A body part hit on [zone] of the link preview card of message
/// [messageId]: the card's area outside its media. The card's media is a
/// [MediaHitPart]; links in its description are text hits.
final class LinkPreviewHitPart extends MessageMediaHitPart {
  /// A hit on [zone] of [messageId]'s card.
  const LinkPreviewHitPart(this.messageId, {required this.zone});

  /// The message whose card was hit.
  final int messageId;

  /// Which area of the card.
  final LinkPreviewZone zone;

  @override
  ChatBodyPartRole get role => ChatBodyPartRole.activate;

  @override
  String get diagnosticName => zone.name;

  @override
  String? get diagnosticItemId => null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkPreviewHitPart &&
          other.messageId == messageId &&
          other.zone == zone;

  @override
  int get hashCode => Object.hash(LinkPreviewHitPart, messageId, zone);

  @override
  String toString() => 'LinkPreviewHitPart($messageId, zone: ${zone.name})';
}

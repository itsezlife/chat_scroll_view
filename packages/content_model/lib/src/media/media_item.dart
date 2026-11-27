import 'package:content_model/src/identity/content_descriptor.dart';
import 'package:content_model/src/media/media_item_id.dart';
import 'package:content_model/src/media/media_item_kind.dart';
import 'package:meta/meta.dart';

/// One piece of media a message shows: an attachment, or a link preview's
/// photo or embedded media.
///
/// The unit every media surface takes (layout, cells, state, the outbox, the
/// picker). It names no message, so a row can show items from several.
/// Equal by value.
@immutable
final class MediaItem {
  /// An item [id] showing [descriptor]'s content.
  ///
  /// [kind] defaults to [MediaItemKind.fromDescriptor]; a host that knows
  /// how the item was sent passes it, and it wins (a photo sent as a file is
  /// [MediaItemKind.file]).
  MediaItem({
    required this.id,
    required this.descriptor,
    MediaItemKind? kind,
    this.spoiler = false,
  }) : kind = kind ?? MediaItemKind.fromDescriptor(descriptor);

  /// The item's identity in the chat.
  final MediaItemId id;

  /// What is known about the content the item shows.
  final ContentDescriptor descriptor;

  /// What the item is shown as.
  final MediaItemKind kind;

  /// Whether the item is hidden behind a spoiler until revealed. Per item: an
  /// album may hide some of its media and not others.
  final bool spoiler;

  @override
  bool operator ==(Object other) =>
      other is MediaItem &&
      other.id == id &&
      other.descriptor == descriptor &&
      other.kind == kind &&
      other.spoiler == spoiler;

  @override
  int get hashCode => Object.hash(id, descriptor, kind, spoiler);

  @override
  String toString() => 'MediaItem($id, $kind${spoiler ? ', spoiler' : ''})';
}

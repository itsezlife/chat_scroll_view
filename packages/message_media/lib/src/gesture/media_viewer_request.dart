import 'dart:ui' show Rect;

import 'package:content_model/content_model.dart' show MediaItemId;
import 'package:flutter/foundation.dart';

/// Where a media item is drawn now, in global coordinates, or null when it
/// is not on screen (scrolled away, never shown).
typedef MediaOriginLookup = Rect? Function(MediaItemId id);

/// What message media hands the host's viewer when an item's content is
/// activated: the items to page through, the one to open, and where it
/// opens from.
///
/// [originRect] is the item's rectangle when the tap landed: the frame the
/// viewer opens from. [rectOf] gives any item's rectangle now, by id, for the
/// frame the viewer closes on after the list scrolled or the viewer paged to
/// a neighbour; a host adapts it to its viewer's origin contract.
@immutable
final class MediaViewerRequest {
  /// A request to open [items] at [index].
  const MediaViewerRequest({
    required this.messageId,
    required this.items,
    required this.index,
    required this.originRect,
    required this.rectOf,
  });

  /// The engine's id of the message whose media opened.
  final int messageId;

  /// The items the viewer pages through, in the message's order: a
  /// message's photos, videos and animations together, or a file alone.
  final List<MediaItemId> items;

  /// The index in [items] of the item activated.
  final int index;

  /// The item's global rectangle when the tap landed, or null when it had
  /// none (the viewer opens without a morph).
  final Rect? originRect;

  /// Any item's global rectangle now.
  final MediaOriginLookup rectOf;

  /// The item activated.
  MediaItemId get item => items[index];

  @override
  bool operator ==(Object other) =>
      other is MediaViewerRequest &&
      other.messageId == messageId &&
      listEquals(other.items, items) &&
      other.index == index &&
      other.originRect == originRect;

  @override
  int get hashCode =>
      Object.hash(messageId, Object.hashAll(items), index, originRect);

  @override
  String toString() =>
      'MediaViewerRequest(messageId: $messageId, items: $items, '
      'index: $index, originRect: $originRect)';
}

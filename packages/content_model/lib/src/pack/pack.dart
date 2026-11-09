import 'package:content_model/src/collection/collection.dart';
import 'package:content_model/src/collection/collection_contents.dart';
import 'package:content_model/src/collection/collection_id.dart';
import 'package:content_model/src/identity/content_descriptor.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/value_equality.dart';
import 'package:meta/meta.dart';

/// The opaque id of a [Pack], issued by the host.
///
/// The same in every source: a content's descriptor names its pack with it
/// ([ContentDescriptor.pack]), and the pack's listing is the collection
/// [CollectionId.set] of the same text ([Pack.collectionId]). Fetch
/// credentials of a pack stay on the host, keyed by this id.
extension type const PackId(String value) {}

/// What a [Pack] holds.
///
/// Packs of different kinds are installed, ordered and shown apart: a strip
/// of sticker packs never lists an emoji pack.
enum PackKind {
  /// Stickers sent as messages of their own.
  stickers('stickers'),

  /// Stickers placed over a face or another image.
  masks('masks'),

  /// Custom emoji, used inside text.
  emoji('emoji');

  const PackKind(this.value);

  /// The kind written as [value].
  ///
  /// A closed set: an unknown non-null value throws an [ArgumentError], and
  /// null throws unless a [fallback] is given.
  factory PackKind.fromValue(String? value, {PackKind? fallback}) {
    for (final kind in values) {
      if (kind.value == value) return kind;
    }
    if (value == null && fallback != null) return fallback;
    throw ArgumentError.value(value, 'value', 'Unknown PackKind');
  }

  /// The stable string for storage and host interchange.
  final String value;

  /// The semantic kind of the content this kind of pack holds.
  SemanticKind get itemKind => switch (this) {
    stickers => SemanticKind.sticker,
    masks => SemanticKind.mask,
    emoji => SemanticKind.customEmoji,
  };
}

/// A published set of stickers, masks or custom emoji: the unit a user
/// installs, archives, removes and opens in a pack sheet.
///
/// A value, as a pack source found it. Whether the user installed it is not
/// here: that is the content library's to answer, so a pack fetched before an
/// install never contradicts it.
@immutable
final class Pack {
  /// Creates the pack [id]; [items] is copied into an unmodifiable list.
  Pack({
    required this.id,
    required this.kind,
    required this.title,
    required List<ContentDescriptor> items,
    this.cover,
    this.official = false,
  }) : items = List<ContentDescriptor>.unmodifiable(items);

  /// Which pack this is.
  final PackId id;

  /// What the pack holds.
  final PackKind kind;

  /// The title as published, in the publisher's language.
  final String title;

  /// The content, in the pack's order. Unmodifiable.
  final List<ContentDescriptor> items;

  /// The content that stands for the pack (on a strip tab), or null when the
  /// publisher named none and the first item serves.
  final ContentKey? cover;

  /// Whether the platform itself publishes the pack. The reference offers to
  /// archive an official pack where it offers to remove any other.
  final bool official;

  /// How many items the pack holds.
  int get count => items.length;

  /// The id of the pack's listing as a [Collection].
  CollectionId get collectionId => CollectionId.set(id.value);

  /// The pack as a loaded [Collection], every item described.
  Collection get collection => Collection(
    id: collectionId,
    metadata: CollectionMetadata(
      title: title,
      cover: cover,
      flags: official ? CollectionFlags.official : CollectionFlags.none,
    ),
    contents: CollectionContents.loaded([
      for (final item in items) CollectionItem.described(item),
    ]),
  );

  @override
  bool operator ==(Object other) =>
      other is Pack &&
      other.id == id &&
      other.kind == kind &&
      other.title == title &&
      other.cover == cover &&
      other.official == official &&
      ValueEquality.lists(other.items, items);

  @override
  int get hashCode =>
      Object.hash(id, kind, title, cover, official, Object.hashAll(items));

  @override
  String toString() => 'Pack(${id.value}, ${kind.value}, $count items)';
}

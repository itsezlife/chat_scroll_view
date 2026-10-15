import 'package:content_model/src/collection/collection_contents.dart';
import 'package:content_model/src/collection/collection_id.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:meta/meta.dart';

/// A combination of facts a source can state about a [Collection].
///
/// Combinable, so a bitmask: build one with `|`, test one with [contains].
/// Equality is bit equality, so the order a combination was built in does not
/// matter. The set of flags grows by addition.
extension type const CollectionFlags._(int _bits) {
  /// No facts stated.
  static const CollectionFlags none = CollectionFlags._(0);

  /// The collection is in the user's own library rather than offered for
  /// preview.
  static const CollectionFlags installed = CollectionFlags._(1);

  /// The collection is currently promoted by the source.
  static const CollectionFlags featured = CollectionFlags._(2);

  /// The collection is published by the platform itself.
  static const CollectionFlags official = CollectionFlags._(4);

  /// Both this combination and [other].
  CollectionFlags operator |(CollectionFlags other) =>
      CollectionFlags._(_bits | other._bits);

  /// Whether every flag of [other] is part of this combination.
  bool contains(CollectionFlags other) => _bits & other._bits == other._bits;
}

/// What a source states about a [Collection], apart from its contents.
///
/// Presentation-free by design: [title] is data the source provides, not a
/// localized label, and no icon is carried. Icons and localized titles of
/// built-in collections belong to the page that shows them, keyed on the
/// collection's [CollectionId].
///
/// Metadata and contents load independently, so every field is optional and a
/// collection can show its title before any item arrives.
@immutable
final class CollectionMetadata {
  /// Creates metadata; every fact defaults to absent.
  const CollectionMetadata({
    this.title,
    this.cover,
    this.flags = CollectionFlags.none,
  });

  /// Metadata that states nothing.
  static const CollectionMetadata empty = CollectionMetadata();

  /// The title as the data provides it, in the source's own language, or null
  /// when the data has none.
  final String? title;

  /// The content that represents the collection, for example on a tab. Any
  /// kind of content may serve; null when the data names none.
  final ContentKey? cover;

  /// Further facts the source states.
  final CollectionFlags flags;

  @override
  bool operator ==(Object other) =>
      other is CollectionMetadata &&
      other.title == title &&
      other.cover == cover &&
      other.flags == flags;

  @override
  int get hashCode => Object.hash(title, cover, flags);

  @override
  String toString() => 'CollectionMetadata(${title ?? 'untitled'})';
}

/// The one shape of every list of content: a set, a personal list, search
/// results, a trending feed.
///
/// A collection is an [id], its [metadata] and its [contents], where
/// [contents] says how far loading has come. A panel section is a projection
/// of a collection, never the collection itself.
///
/// A plain value: the source publishes a new one for every change, and equal
/// collections are interchangeable.
@immutable
final class Collection {
  /// Creates the collection [id]. Before anything loads it states no metadata
  /// and its [contents] are [CollectionContents.idle].
  const Collection({
    required this.id,
    this.metadata = CollectionMetadata.empty,
    this.contents = CollectionContents.idle,
  });

  /// Which collection this is, within its source.
  final CollectionId id;

  /// What the source states about the collection.
  final CollectionMetadata metadata;

  /// The items and the state of loading them.
  final CollectionContents contents;

  @override
  bool operator ==(Object other) =>
      other is Collection &&
      other.id == id &&
      other.metadata == metadata &&
      other.contents == contents;

  @override
  int get hashCode => Object.hash(id, metadata, contents);

  @override
  String toString() => 'Collection($id, $contents)';
}

import 'package:meta/meta.dart';

/// The personal lists every catalog has a fixed place for.
enum WellKnownList {
  /// What the user picked most recently or most often.
  recent,

  /// What the user marked as a favourite.
  faved,

  /// What the user saved.
  saved,
}

/// Identifies a [Collection] within the source that produces it.
///
/// This is also the collection's semantic id: a page keys the icon and
/// localized title of a built-in collection on it, so data sources never carry
/// presentation. An id is scoped to its source; two sources may each have a
/// [recent] list without their ids colliding in any shared store.
///
/// The set of variants is closed:
///
/// - [CollectionId.set]: a set (a pack of stickers or emoji) by its id.
/// - [recent], [faved], [saved]: the well-known personal lists.
/// - [CollectionId.query]: the results of a query, for example a search.
/// - [CollectionId.category]: a named grouping, for example a built-in group
///   of an emoji catalog.
///
/// Equality is exact value equality on the variant and its payload.
@immutable
sealed class CollectionId {
  /// The set with the opaque [id], which must not be empty.
  const factory CollectionId.set(String id) = CollectionId$Set;

  /// The results of the query [text], kept exactly as the source received it:
  /// no trimming, no case folding, so two spellings are two ids. The empty
  /// text is a valid query (for example "trending").
  const factory CollectionId.query(String text) = CollectionId$Query;

  /// The category with the semantic [id], which must not be empty.
  const factory CollectionId.category(String id) = CollectionId$Category;

  const CollectionId._();

  /// The recent list.
  static const CollectionId recent = CollectionId$WellKnown(
    WellKnownList.recent,
  );

  /// The favourites list.
  static const CollectionId faved = CollectionId$WellKnown(WellKnownList.faved);

  /// The saved list.
  static const CollectionId saved = CollectionId$WellKnown(WellKnownList.saved);
}

/// A [CollectionId] of a set; see [CollectionId.set].
final class CollectionId$Set extends CollectionId {
  /// Creates the id of the set [id], which must not be empty.
  const CollectionId$Set(this.id)
    : assert(id != '', 'A set CollectionId needs an id.'),
      super._();

  /// The opaque set id.
  final String id;

  @override
  bool operator ==(Object other) => other is CollectionId$Set && other.id == id;

  @override
  int get hashCode => Object.hash(CollectionId$Set, id);

  @override
  String toString() => 'CollectionId.set($id)';
}

/// A [CollectionId] of a well-known personal list; see
/// [CollectionId.recent].
final class CollectionId$WellKnown extends CollectionId {
  /// Creates the id of [list].
  const CollectionId$WellKnown(this.list) : super._();

  /// Which personal list this is.
  final WellKnownList list;

  @override
  bool operator ==(Object other) =>
      other is CollectionId$WellKnown && other.list == list;

  @override
  int get hashCode => Object.hash(CollectionId$WellKnown, list);

  @override
  String toString() => 'CollectionId.${list.name}';
}

/// A [CollectionId] of a query's results; see [CollectionId.query].
final class CollectionId$Query extends CollectionId {
  /// Creates the id of the results of [text].
  const CollectionId$Query(this.text) : super._();

  /// The query text, exactly as received.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is CollectionId$Query && other.text == text;

  @override
  int get hashCode => Object.hash(CollectionId$Query, text);

  @override
  String toString() => 'CollectionId.query($text)';
}

/// A [CollectionId] of a category; see [CollectionId.category].
final class CollectionId$Category extends CollectionId {
  /// Creates the id of the category [id], which must not be empty.
  const CollectionId$Category(this.id)
    : assert(id != '', 'A category CollectionId needs an id.'),
      super._();

  /// The semantic category id.
  final String id;

  @override
  bool operator ==(Object other) =>
      other is CollectionId$Category && other.id == id;

  @override
  int get hashCode => Object.hash(CollectionId$Category, id);

  @override
  String toString() => 'CollectionId.category($id)';
}

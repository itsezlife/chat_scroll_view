import 'package:content_model/src/identity/content_descriptor.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/value_equality.dart';
import 'package:meta/meta.dart';

/// An opaque host-issued cursor to the next page of a [Collection].
///
/// Only the source that issued it can interpret it, and only that source gets
/// it back.
extension type const PageToken(String value) {}

/// One entry of a loaded [Collection]: a content key and, when the source
/// already holds it, the descriptor of that content.
///
/// A bare entry stands for content the source knows only by key; whoever needs
/// its facts resolves the key. The key of a described entry is always its
/// descriptor's key, so the two cannot disagree.
@immutable
final class CollectionItem {
  /// An entry known only by [key].
  const CollectionItem.bare(this.key) : descriptor = null;

  /// An entry with its [descriptor] already known.
  CollectionItem.described(ContentDescriptor this.descriptor)
    : key = descriptor.key;

  /// The content this entry refers to.
  final ContentKey key;

  /// What the source knows about [key], or null for a bare entry.
  final ContentDescriptor? descriptor;

  @override
  bool operator ==(Object other) =>
      other is CollectionItem &&
      other.key == key &&
      other.descriptor == descriptor;

  @override
  int get hashCode => Object.hash(key, descriptor);

  @override
  String toString() =>
      'CollectionItem($key${switch (descriptor) {
        null => '',
        _ => ', described',
      }})';
}

/// The contents of a [Collection] and where loading them stands.
///
/// Exactly one of four mutually exclusive states, so a list cannot be both
/// loading and failed, or hold items while idle:
///
/// - [idle]: nothing has been asked for yet.
/// - [loading]: the first load is in flight.
/// - [CollectionContents.loaded]: items are available.
/// - [CollectionContents.failed]: the first load failed.
///
/// Pagination never leaves [CollectionContents.loaded]. A source keeps
/// publishing the loaded items while it fetches the next page, and keeps them
/// when that fetch fails; [CollectionContents$Loaded.nextPageToken] is the
/// signal that more exist. So a grid never loses what it already shows.
///
/// Whether the descriptor of an item has loaded is not a state here: it is a
/// property of the [CollectionItem], derived from the descriptor being present.
@immutable
sealed class CollectionContents {
  /// The items of one loaded page run, in display order.
  ///
  /// The list is copied and then unmodifiable. [nextPageToken] is the token to
  /// request the next page with, or null when no further page exists.
  factory CollectionContents.loaded(
    List<CollectionItem> items, {
    PageToken? nextPageToken,
  }) = CollectionContents$Loaded;

  /// A failed first load. [error] and [stackTrace] are diagnostics for the
  /// host to log; they carry no meaning a consumer should branch on, and
  /// [stackTrace] is ignored by equality.
  const factory CollectionContents.failed(
    Object error, [
    StackTrace? stackTrace,
  ]) = CollectionContents$Failed;

  const CollectionContents._();

  /// Nothing has been asked for yet.
  static const CollectionContents idle = CollectionContents$Idle();

  /// The first load is in flight.
  static const CollectionContents loading = CollectionContents$Loading();
}

/// The [CollectionContents.idle] state.
final class CollectionContents$Idle extends CollectionContents {
  /// Creates the idle state.
  const CollectionContents$Idle() : super._();

  @override
  bool operator ==(Object other) => other is CollectionContents$Idle;

  @override
  int get hashCode => (CollectionContents$Idle).hashCode;

  @override
  String toString() => 'idle';
}

/// The [CollectionContents.loading] state.
final class CollectionContents$Loading extends CollectionContents {
  /// Creates the loading state.
  const CollectionContents$Loading() : super._();

  @override
  bool operator ==(Object other) => other is CollectionContents$Loading;

  @override
  int get hashCode => (CollectionContents$Loading).hashCode;

  @override
  String toString() => 'loading';
}

/// The [CollectionContents.loaded] state.
final class CollectionContents$Loaded extends CollectionContents {
  /// Creates the loaded state, copying [items] into an unmodifiable list.
  CollectionContents$Loaded(List<CollectionItem> items, {this.nextPageToken})
    : items = List<CollectionItem>.unmodifiable(items),
      super._();

  /// The loaded items in display order. Unmodifiable.
  final List<CollectionItem> items;

  /// The cursor of the next page, or null when this is the last one.
  final PageToken? nextPageToken;

  @override
  bool operator ==(Object other) =>
      other is CollectionContents$Loaded &&
      other.nextPageToken == nextPageToken &&
      ValueEquality.lists(other.items, items);

  @override
  int get hashCode => Object.hash(
    CollectionContents$Loaded,
    nextPageToken,
    Object.hashAll(items),
  );

  @override
  String toString() =>
      'loaded(${items.length} items${switch (nextPageToken) {
        null => '',
        _ => ', more',
      }})';
}

/// The [CollectionContents.failed] state.
final class CollectionContents$Failed extends CollectionContents {
  /// Creates the failed state for [error].
  const CollectionContents$Failed(this.error, [this.stackTrace]) : super._();

  /// What the first load failed with.
  final Object error;

  /// Where [error] was thrown, when the source caught it with a trace.
  final StackTrace? stackTrace;

  @override
  bool operator ==(Object other) =>
      other is CollectionContents$Failed && other.error == error;

  @override
  int get hashCode => Object.hash(CollectionContents$Failed, error);

  @override
  String toString() => 'failed($error)';
}

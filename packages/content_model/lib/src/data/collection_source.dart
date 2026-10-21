import 'package:content_model/src/collection/collection.dart';
import 'package:content_model/src/collection/collection_id.dart';
import 'package:listen/listen.dart';

/// Where a page gets its [Collection]s: an ordered set of collections, each
/// with its own contents, loading state and paging.
///
/// One source serves one kind of content (the emoji catalogue, an installed
/// sticker library, trending GIFs). Pages compose only the sources they need;
/// there is no facade over all of them.
///
/// ## Publication
///
/// [collections] is the snapshot pattern: an immutable, unmodifiable list the
/// source replaces whole, never edits in place. It is in display order, holds
/// at most one [Collection] per [CollectionId], and the order is the source's
/// to decide and stable between publications unless the data itself changes.
/// Every change (a title arrives, a collection starts loading, a page lands)
/// produces one new list and one signal, however many collections it
/// touched.
///
/// Metadata and contents load independently, so a collection may be listed
/// with its title long before its [CollectionContents] leave `idle`.
///
/// ## Loading
///
/// Both commands report their outcome only through [collections]. Their
/// returned futures complete when that outcome has been published and
/// **never complete with an error**: a failure is a state, not an exception.
///
/// - [load] asks for the first contents of a collection. Idle moves to
///   loading, then loaded, or failed when the first load fails. Calling it on
///   a collection that is loading or already loaded changes nothing; on a
///   failed one it tries again.
/// - [loadMore] fetches the page named by the loaded contents'
///   `nextPageToken`. The collection stays loaded throughout, items appended
///   in order; if the fetch fails it stays loaded with the same token, so a
///   later call retries. With no token, or while a page is in flight, it
///   changes nothing.
///
/// A command naming a [CollectionId] the source does not list changes
/// nothing.
///
/// ## Disposal
///
/// [dispose] releases the source. Afterwards [collections] publishes nothing,
/// commands do nothing and their futures complete at once. Work still in
/// flight is dropped, not published.
abstract interface class CollectionSource {
  /// The collections on offer, in display order.
  ValueListenable<List<Collection>> get collections;

  /// Starts the first load of the collection [id].
  Future<void> load(CollectionId id);

  /// Fetches the next page of the loaded collection [id].
  Future<void> loadMore(CollectionId id);

  /// Releases the source and its listeners.
  void dispose();
}

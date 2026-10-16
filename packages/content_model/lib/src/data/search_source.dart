import 'package:content_model/src/collection/collection.dart';
import 'package:content_model/src/observable/observable.dart';

/// Turns a query into one paged results [Collection].
///
/// A source holds one search at a time, like the field that drives it. The
/// results are the snapshot pattern of [CollectionSource.collections]:
/// replaced whole, one signal per change.
///
/// ## Results
///
/// [results] always describes the latest query: its id is
/// `CollectionId.query(text)` for the text passed to the last [search], and
/// `CollectionId.query('')` before the first one. Contents follow the
/// [Collection] states: loading while the first page is in flight, loaded with
/// the items and a `nextPageToken`, failed when the first page fails. Order
/// is relevance, best first, with no key repeated.
///
/// ## Commands
///
/// - [search] starts a new query and supersedes the one before it: anything
///   still in flight for an older query is dropped, never published, so
///   results cannot arrive out of order. An empty query, or one of only
///   whitespace, clears the results to `idle` instead of searching. The same
///   query again changes nothing.
/// - [loadMore] fetches the next page of the current results, with the
///   guarantees of [CollectionSource.loadMore].
///
/// Both futures complete once the outcome is published and never complete
/// with an error. A page that fails to load stays out of the results; they
/// remain loaded.
///
/// Searching does not count as use: a pick made from search results is
/// reported to a [RecentsStore] as [PickSource.search], which it ignores.
///
/// ## Disposal
///
/// After [dispose] nothing is published and commands do nothing.
abstract interface class SearchSource {
  /// The results of the latest query.
  ValueObservable<Collection> get results;

  /// Replaces the current query with [query].
  Future<void> search(String query);

  /// Fetches the next page of the current results.
  Future<void> loadMore();

  /// Releases the source and its listeners.
  void dispose();
}

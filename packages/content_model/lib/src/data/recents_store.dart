import 'package:content_model/src/identity/content_descriptor.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/observable/observable.dart';

/// Where in the interface a pick was made; decides whether it counts as use.
enum PickSource {
  /// A browsable collection: a category grid, a set, a trending feed.
  collection,

  /// The recents list itself.
  recents,

  /// Search results. Never counts as use.
  search,
}

/// What the user picked lately, per [SemanticKind], most useful first.
///
/// The host decides when a pick counts (insert or send) and calls [record];
/// pages never record on their own. Any [ContentKey] can be recorded, unicode
/// and document-backed alike. The store keeps keys, not descriptors: resolve
/// the bare keys with a `ContentResolver` for display.
///
/// ## Ordering
///
/// [recents] orders by how often a key was picked, most often first, and
/// breaks ties by how recently, latest first. Each [SemanticKind] has its own
/// list; a key recorded under one kind never appears in another. A list holds
/// no key twice and never more than the store's capacity: recording past it
/// drops the key that sorts last.
///
/// ## Loaded stores only
///
/// A store is created already holding what was persisted, so [recents] is
/// synchronous and never shows a half-loaded state. A picked key is reflected
/// by [recents] and [changes] **before** the future returned by [record]
/// completes; the future completes when the pick is persisted and fails if
/// persisting did, leaving the in-memory state as it is.
///
/// ## Disposal
///
/// After [dispose] [changes] is silent, [recents] keeps answering with the
/// last state and the commands do nothing.
abstract interface class RecentsStore {
  /// Signals once per [record] or [clear] that changed some list.
  Observable get changes;

  /// The keys of [kind], best first. Unmodifiable; empty when none were
  /// recorded.
  List<ContentKey> recents(SemanticKind kind);

  /// Counts one pick of [key] under [kind].
  ///
  /// A pick with [source] [PickSource.search] is ignored: nothing changes and
  /// nothing is signalled.
  Future<void> record(
    ContentKey key, {
    required SemanticKind kind,
    PickSource source = PickSource.collection,
  });

  /// Forgets everything recorded under [kind], or under every kind when it is
  /// null. Does nothing, and signals nothing, when there was nothing to
  /// forget.
  Future<void> clear({SemanticKind? kind});

  /// Releases the store and its listeners.
  void dispose();
}

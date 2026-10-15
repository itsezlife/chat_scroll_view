import 'package:catalog_assets/src/atlas/cache/glyph_cache_key.dart';
import 'package:catalog_assets/src/atlas/glyph_page_store.dart';

/// A persisted set of baked pages and what it was baked for.
final class GlyphCacheGeneration {
  /// Creates a generation described by [record] whose pages are in [pages].
  const GlyphCacheGeneration({required this.record, required this.pages});

  /// The key and glyph list the pages were baked for.
  final GlyphCacheRecord record;

  /// The pages, as a [GlyphPageStore]. Writable: a generation that lost a
  /// page is repaired by baking that page again into the same store.
  final GlyphPageStore pages;
}

/// Seam behind which baked pages outlive the process: one **committed**
/// generation that is what the next launch finds, and at most one **staged**
/// generation being baked beside it.
///
/// Staging exists for one case: art changed, so the committed pages are still
/// drawn while the new set bakes. The staged pages are invisible to
/// [openCommitted] until [commit] makes them the committed ones in one step
/// and removes the old, so a process killed mid-bake leaves the old set intact.
/// A first run or a discard stages and commits straight away (an empty
/// generation), so each page is durable as soon as it is written and a later
/// launch restores the pages that made it.
///
/// Contract (run [runGlyphCacheStoreContract] against an implementation):
///
/// - [openCommitted] returns null when nothing valid is committed, and also
///   for a record that cannot be read: damage is a miss, never a throw;
/// - pages written to [stage]'s store are not committed before [commit];
///   staging again forgets the earlier uncommitted generation;
/// - [commit] replaces the committed generation, record and pages together;
///   without a staged generation it throws [StateError];
/// - a page written to the store of [openCommitted] is read back from a later
///   [openCommitted];
/// - [clear] removes everything, committed and staged.
///
/// One atlas at a time uses a store (single writer).
///
/// [runGlyphCacheStoreContract]: package:catalog_assets/testing.dart
abstract interface class GlyphCacheStore {
  /// The committed generation, or null.
  Future<GlyphCacheGeneration?> openCommitted();

  /// Starts an uncommitted generation described by [record] and returns the
  /// store its pages go to.
  Future<GlyphPageStore> stage(GlyphCacheRecord record);

  /// Makes the staged generation the committed one.
  Future<void> commit();

  /// Removes every persisted page and record.
  Future<void> clear();
}

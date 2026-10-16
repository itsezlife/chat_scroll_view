import 'dart:ui';

/// Seam behind which baked atlas pages are kept: in memory for the pages being
/// drawn, later also on disk so a bake is a first-run cost.
///
/// Pages are GPU images, so a store speaks in [Image] handles. Ownership is by
/// handle: the store keeps its own clone of what it is given and hands out a
/// fresh clone on every read, so a caller disposing its handle never
/// invalidates the stored page and a stored page is never mutated in place
/// (static pages are immutable once composed).
///
/// Contract (run [runGlyphPageStoreContract] against an implementation):
///
/// - [read] after [write] returns a page with the same pixels, [read] of a page
///   never written (or after [clear]) returns null;
/// - writing an index again replaces the page;
/// - disposing a handle passed to [write] or returned by [read] leaves the
///   stored page readable.
///
/// [runGlyphPageStoreContract]: package:catalog_assets/testing.dart
abstract interface class GlyphPageStore {
  /// Stores [page] as page [pageIndex]. The caller keeps ownership of [page].
  Future<void> write(int pageIndex, Image page);

  /// A new handle to page [pageIndex], or null when it is not stored. The
  /// caller disposes it.
  Future<Image?> read(int pageIndex);

  /// Drops every stored page.
  Future<void> clear();
}

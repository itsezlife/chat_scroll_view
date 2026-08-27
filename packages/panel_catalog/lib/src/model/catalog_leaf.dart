import 'package:catalog_assets/catalog_assets.dart';

/// One cell in the catalog projection.
///
/// Carries **identity only** (unicode glyph or document id). Presentation
/// (ready content vs kind-specific placeholder) is projected by the viewport
/// from asset-cache readiness — MUST NOT be stored on the leaf itself.
/// Storing paint mode on the model would duplicate the cache as a second
/// write model and go stale when readiness flips.
///
/// Bind to [CatalogAssetCache] via [assetKey]. Equality is **not** overridden
/// on the leaf types; use [assetKey] (and its equality) for maps, sets, and
/// presentation lookup. Two [UnicodeCatalogLeaf] instances with the same
/// glyph are not `==` unless you compare [assetKey].
sealed class CatalogLeaf {
  /// Cache / hit-test identity for this leaf ([CatalogAssetKey]).
  CatalogAssetKey get assetKey;

  /// Creates a unicode emoji leaf for [glyph].
  ///
  /// [glyph] is one or more codepoints (ZWJ sequences allowed). Empty string
  /// is undefined for paint.
  const factory CatalogLeaf.unicode(String glyph) = UnicodeCatalogLeaf;

  /// Creates a document-backed leaf for [documentId].
  ///
  /// [documentId] MUST be unique within the process-wide asset-cache key
  /// space (stable across notifies for the same media).
  const factory CatalogLeaf.document(String documentId) = DocumentCatalogLeaf;
}

/// Standard unicode emoji leaf.
///
/// Paints via paragraph cache (no async asset decode). Presentation is
/// [CatalogLeafPresentation.content] unless the cache reports failed.
final class UnicodeCatalogLeaf implements CatalogLeaf {
  /// Creates a unicode leaf for [glyph].
  const UnicodeCatalogLeaf(this.glyph);

  /// The emoji glyph string (one or more codepoints, including ZWJ sequences).
  final String glyph;

  @override
  CatalogAssetKey get assetKey => CatalogAssetKey.unicode(glyph);
}

/// Document-backed leaf (animated/custom emoji, sticker, GIF).
///
/// Identity is available even when media decode is stubbed — the viewport can
/// still project, bind, and paint a stand-in. Loading projects to
/// [CatalogLeafPresentation.thumbFirstPlaceholder]. Ready paint may still be
/// a stand-in until the host media pipeline supplies bytes to the cache.
final class DocumentCatalogLeaf implements CatalogLeaf {
  /// Creates a document-backed leaf for [documentId].
  const DocumentCatalogLeaf(this.documentId);

  /// Stable document identifier for the host media pipeline.
  ///
  /// MUST be unique within the process-wide asset-cache key space. Changing
  /// the id is a different leaf — the old binding detaches when it leaves the
  /// visible band.
  final String documentId;

  @override
  CatalogAssetKey get assetKey => CatalogAssetKey.document(documentId);
}

/// Identity for an entry in the global catalog asset cache.
///
/// Unicode glyphs and document-backed assets share one key type so multiple
/// host surfaces can bind the same process-wide store.
sealed class CatalogAssetKey {
  /// Creates a key for a standard unicode emoji glyph.
  const factory CatalogAssetKey.unicode(String glyph) = UnicodeCatalogAssetKey;

  /// Creates a key for a document-backed leaf (animated emoji, sticker, GIF).
  const factory CatalogAssetKey.document(String documentId) =
      DocumentCatalogAssetKey;
}

/// Unicode glyph identity.
final class UnicodeCatalogAssetKey implements CatalogAssetKey {
  /// Creates a unicode catalog asset key.
  const UnicodeCatalogAssetKey(this.glyph);

  /// The emoji glyph string.
  final String glyph;

  @override
  bool operator ==(Object other) =>
      other is UnicodeCatalogAssetKey && other.glyph == glyph;

  @override
  int get hashCode => glyph.hashCode;

  @override
  String toString() => 'CatalogAssetKey.unicode($glyph)';
}

/// Document-backed identity (animated/custom emoji, sticker, GIF).
final class DocumentCatalogAssetKey implements CatalogAssetKey {
  /// Creates a document catalog asset key.
  const DocumentCatalogAssetKey(this.documentId);

  /// Stable document identifier used by the host media pipeline.
  final String documentId;

  @override
  bool operator ==(Object other) =>
      other is DocumentCatalogAssetKey && other.documentId == documentId;

  @override
  int get hashCode => documentId.hashCode;

  @override
  String toString() => 'CatalogAssetKey.document($documentId)';
}

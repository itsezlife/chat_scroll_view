/// Leaf presentation readiness for a bound catalog asset.
enum CatalogAssetReadiness {
  /// Asset is not yet available; viewport paints a kind-specific placeholder.
  loading,

  /// Asset bytes / drawable are available to paint.
  ready,

  /// Load failed; viewport may paint a failed stand-in.
  failed,
}

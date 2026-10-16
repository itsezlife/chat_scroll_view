/// Size class for a catalog asset decode.
///
/// Distinguishes keyboard-panel cells from message-sized leaves so the same
/// key can be retained at more than one resolution.
enum CatalogAssetCacheType {
  /// Keyboard-panel catalog cells.
  keyboard,

  /// Inline / message-sized leaves in a conversation surface.
  messages,
}

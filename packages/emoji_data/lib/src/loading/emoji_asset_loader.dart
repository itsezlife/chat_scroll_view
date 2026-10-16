/// Reads the text of one bundled asset by its key.
///
/// The seam to the host's asset bundle: in Flutter,
/// `rootBundle.loadString` is one. The keys come from
/// `EmojiCatalogPackAssets`. A missing or unreadable asset fails the returned
/// future; the loader never returns partial text.
typedef EmojiAssetLoader = Future<String> Function(String key);

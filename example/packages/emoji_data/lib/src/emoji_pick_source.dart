/// Where the user picked an emoji — drives recents policy.
enum EmojiPickSource {
  /// Category / default grid.
  grid,

  /// Frequently-used row.
  recent,

  /// In-panel search — does not update frequently-used recents.
  search,
}

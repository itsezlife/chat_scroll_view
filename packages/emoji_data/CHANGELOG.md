# Changelog

All notable changes to `emoji_data` are documented in this file. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Changed

- Change notification is `package:listen` (`listen: ^1.0.1`) instead of
  `content_model`'s removed `Observable` family: `changes` is a `Listenable`,
  `collections` and `results` are `ValueListenable`s, and the keyword sources
  and `MissingGlyphProbe` are `ChangeNotifier`s whose `dispose` stays
  idempotent. `addListener` on a disposed source asserts in debug builds.

### Added

- Emoji logic over the `content_model` seams, in pure Dart: no Flutter, no
  platform channel, no native code. `EmojiAssetLoader`, `EmojiCatalogLoader`
  and `EmojiCatalog` read the shipped structure and keyword packs of
  `emoji_catalog_pack`.
- `EmojiCollectionSource` (recents, then one collection per category, the
  chosen variant of each emoji, emoji the device cannot draw hidden, optional
  paging) and `EmojiSearchSource` (ordered language set, exact, prefix and
  later-token ranking, re-run when a pack arrives).
- `BundledKeywordSource` and `LayeredKeywordSource` (host records over the
  bundled ones).
- The glyph probe: `MissingGlyphProbe` (the `GlyphSupport`, persisted through a
  `KeyValueStore` under the art version it was taken for),
  `computeGlyphArtFingerprint`, `PacedGlyphProbePass` for a host with no bake to
  share, `GlyphProbeSnapshot` and `hashGlyphPixels`.
- `package:emoji_data/testing.dart` with `FakeEmojiAssetLoader`.

### Changed

- The items of `EmojiCollectionSource` and `EmojiSearchSource` carry the spoken
  name of their emoji (the first word of its keyword record, from the first
  language that names it; a tone variant is named as its entry), so a screen
  reader says the name and not the glyph. `EmojiCollectionSource` takes
  optional `keywords` and `languages` for it, and waits for the packs before
  publishing a collection as loaded.

### Removed

- The native emoji platform filter and its plugin code: which glyphs the
  device cannot draw is decided by the probe from rendered cells.

### Fixed

- A search whose pack cannot be read when it arrives reports the failure to the
  zone and keeps the results on screen, instead of swallowing it.
- A probe disposed while its art version is being produced fails
  `artVersionReady` with a `StateError` (not a null check) and completes
  `completed` (`isComplete` stays false).

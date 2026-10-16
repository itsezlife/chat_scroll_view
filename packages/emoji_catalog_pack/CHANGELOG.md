# Changelog

All notable changes to `emoji_catalog_pack` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Changed

- Source-breaking for `generator.dart`: `generateAssets(...)` is
  `AssetGenerator.generate(...)`, `buildEmojiKeywordPack(...)` is
  `EmojiKeywordPackBuilder.build(...)` and `buildStructure(file)` is
  `StructureBuilder.build(file)`.

### Added

- The emoji catalog as shipped data: `assets/structure.tsv` (groups,
  subgroups, 1759 entries and their variants with skin-tone and gender tags)
  and one keyword pack per locale under `assets/keywords/` (de, en, es, fr, hi,
  it, ja, nl, pt, ru, zh), with `assets/LICENSE-UNICODE.txt` for provenance.
- Pure-Dart readers: `EmojiCatalogStructure` and `EmojiKeywordPack`, both
  strict (a `FormatException` on anything unreadable), and
  `EmojiCatalogPackAssets` (the asset keys and the shipped locales).
- The pinned generator (`package:emoji_catalog_pack/generator.dart`, `tool/`)
  that builds both assets from Unicode and CLDR, with its inputs locked in
  `tool/inputs.lock`.

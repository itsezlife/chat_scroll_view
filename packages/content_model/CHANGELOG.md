# Changelog

All notable changes to `content_model` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- Pure-Dart value types for catalog content: `ContentKey` (`unicode`,
  `document`, `external`, with a stable string encoding), `ContentDescriptor`,
  `SemanticKind`, `MediaForm`, `Collection`, `CollectionId`,
  `CollectionContents`, `CollectionItem`, `PageToken`, `EmojiEntry` with
  `EmojiModifiers` and `InlineContentRef`.
- `RichText` and `Entity`: plain text plus UTF-16 spans (styles, link, mention,
  inline content), always canonical, with `insert`, `delete`, `replaceRange`
  and `slice`, and JSON in and out. `package:content_model/markdown.dart` adds
  `RichTextMarkdown` to read and write the markdown the viewport's markdown
  library understands.
- The synchronous change-notification primitives `Observable`,
  `ValueObservable`, `EventObservable` and their owners `ObservableNotifier`,
  `ObservableValue`, `EventNotifier`.
- The seams packages reach data through: `CollectionSource`, `SearchSource`,
  `RecentsStore`, `PreferenceStore`, `KeywordSource` with `KeywordPack`,
  `GlyphSupport`, `KeyValueStore` with `StoredValue`, and `ContentResolver`.
- `KeyValueRecentsStore` and `KeyValuePreferenceStore`, the reference stores
  over a `KeyValueStore`, created only by their async `load`.
- `package:content_model/testing.dart`: a fake and a contract suite for every
  seam (`runObservableContract`, `runKeyValueStoreContract`, ...). It depends on
  `package:test`; production code never imports it.

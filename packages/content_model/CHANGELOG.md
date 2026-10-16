# Changelog

All notable changes to `content_model` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- `DeferredRecentsStore`: a `RecentsStore` view that shows the recents of
  another as of its last `commit()`, so a panel that lists them does not
  reorder under the finger picking from it. Picks go to the real store at once;
  a clear commits at once.

### Changed

- Change notification is `package:listen` (`listen: ^1.0.1`), not a type of
  this package. The seams expose `Listenable` (`changes`) and
  `ValueListenable` (`collections`, `results`); the reference stores and the
  fakes are `ChangeNotifier`s, and `FakeCollectionSource` / `FakeSearchSource`
  hold a `ValueNotifier`. `Observable`, `ValueObservable`, `EventObservable`,
  `ObservableNotifier`, `ObservableValue`, `EventNotifier`, `FakeObservable`
  and `runObservableContract` are removed; the owners' `dispose` stays
  idempotent. What changes for hosts: a listener added twice runs twice, an
  owner no longer ignores `addListener` or a signal after `dispose` (they assert
  in debug builds), a throwing listener goes to the static `Listenable.onError`,
  whose default rethrows, and `batch` is gone (assign the final value once).
  Typed events are a broadcast `Stream` in the packages that publish them.

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
- The seams packages reach data through: `CollectionSource`, `SearchSource`,
  `RecentsStore`, `PreferenceStore`, `KeywordSource` with `KeywordPack`,
  `GlyphSupport`, `KeyValueStore` with `StoredValue`, and `ContentResolver`.
- `KeyValueRecentsStore` and `KeyValuePreferenceStore`, the reference stores
  over a `KeyValueStore`, created only by their async `load`.
- `package:content_model/testing.dart`: a fake and a contract suite for every
  seam (`runKeyValueStoreContract`, ...). It depends on
  `package:test`; production code never imports it.

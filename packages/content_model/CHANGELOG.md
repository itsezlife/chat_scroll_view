# Changelog

All notable changes to `content_model` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- Source-breaking for implementers: `PreferenceStore.defaultVariant` and
  `setDefaultVariant(EmojiModifiers)`, a tone for every emoji that forgets the
  choices made per emoji; `KeyValuePreferenceStore` persists it as tone names,
  `FakePreferenceStore` and the contract cover it.
- `DeferredRecentsStore`: a `RecentsStore` view that shows the recents of
  another as of its last `commit()`, so a panel that lists them does not
  reorder under the finger picking from it. Picks go to the real store at once;
  a clear commits at once.

### Changed

- `PreferenceStore.preferredVariant` documents that choosing the base is stored
  as the base itself; no new member and no record change (the reference store
  already round-trips it), so existing data reads as before: a user who chose
  the base earlier is simply a user who has not chosen.
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

- `RecentsStore.remove(key, {kind})`: forgets one key under one kind, its count
  with it, and signals once (nothing when it was not listed). In the contract
  suite, the reference store, the ledger and the fake. Source-breaking for an
  implementer of `RecentsStore`.
  `DeferredRecentsStore.remove` forgets in the real store and takes the key out
  of what the view shows at once, leaving every other waiting pick for the next
  `commit` (a pick of the same key not yet shown is forgotten with it).
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

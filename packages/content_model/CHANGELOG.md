# Changelog

All notable changes to `content_model` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- `RichTextMarkdown.codec`: `encode` and `decode` as a `dart:convert` `Codec`,
  so a host can `fuse(utf8)` a body into bytes or `inverted` it. The static
  functions stay.
- `TypedMarkdown.apply`: the markers a user typed become entities at send,
  with Telegram Android's rules: `` `code` ``, a triple-backtick code block
  (with a language first line), `**bold**`, `__italic__`, `~~strike~~` and
  `||spoiler||`. A pair that touches code, a code block, a link or an atom
  stays text. Call it before `EntityDetection.apply`.

### Fixed

- `TypedMarkdown`: a run of four or more backticks is not a code fence (it
  used to convert into a block with a stray backtick); `RichTextMarkdown`
  round trips what it made, pinned by a test.
- `RichTextMarkdown.decode` threw on `[`a`](u)`, a link whose label holds code:
  a `RichText` never lets the two overlap, and the decode contract is that it
  never throws. The link is kept and the label's code reads as text; one such
  message failed a whole fetched range.

### Changed

- Source-breaking: the contract suites in `testing.dart` are statics on a type
  per seam: `runKeyValueStoreContract(...)` is now
  `KeyValueStoreContract.run(...)`, and likewise `RecentsStoreContract`,
  `PreferenceStoreContract`, `CollectionSourceContract`,
  `SearchSourceContract`, `KeywordSourceContract`, `GlyphSupportContract` and
  `ContentResolverContract`.

### Added

- `EntityKind.isTextStyle`: whether a kind is a style that wraps text and
  holds other entities beside it (every `EntityStyle` but code and quote).
- `EntityDetection.apply(RichText, DetectionPolicy)` and
  `EntityDetection.strip`: bare URLs (`https://a.b/c`, `a.com`, `www.a.com`),
  emails (a `mailto:` link), `@name` (`EntityKind.username`) and `#tag`
  (`EntityKind.hashtag`) become entities with Telegram Android's rules, never
  inside code, a code block, a link, a mention, a username, a hashtag or inline
  content. At most `EntityDetection.maxMatches` (100) per text; a text over
  `EntityDetection.maxLength` (20 480) is returned unchanged. A scheme-less
  host must end in a TLD from the shipped IANA list
  (`tool/generate_tlds.dart` regenerates it) or in punycode. `strip` is the
  edit-load inverse. `DetectionPolicy({urls, usernames, hashtags, schemes})`
  replaces the root package's `ChatLinkifyPolicy`; `DetectionPolicy.urlsOnly`
  is the web-URL-only policy.

- `EmojiOnlyText.of(RichText)` returns the `EmojiOnly` items (`EmojiOnlyItem`:
  a unicode or document `ContentKey` and the line breaks before it) of a text
  that is nothing but emoji, spaces, tabs and line breaks, with inline content
  of a document key as the only entity; null for any other text. It follows
  Telegram Android's `Emoji.parseEmojis` with no count cap.

- `RichClipboard.attach(RichClipboardField)`: takes over the clipboard
  commands a platform performs itself for a focused text field (a browser's
  copy, cut and paste keys and menu), so they keep the rich form.
  `FakeRichClipboard.performCopy({cut})` and `performPaste()` stand in for
  them. Source-breaking for `RichClipboard` implementers.

- `PastedMedia` (`.bytes` with a MIME type and name, `.file` with a path)
  and `RichClipboard.readWithMedia()`: the clipboard's text and the images
  and files it holds as `ClipboardContents`, in one read, so a platform that
  asks before a paste asks once. Files a file manager copied come without
  text. `FakeRichClipboard.putMedia(media, text:)` and the contract's
  `putImage` harness hook; the contract takes an image as data or as a saved
  file. Source-breaking for `RichClipboard` implementers.
- Building a `RichText` takes time linear in its size: a text style's split
  at line breaks looked through the rest of the text, and its trim through
  every code and atomic entity, per entity.
- `EntityKind.codeBlock({language})` (ADR 033): whole lines of code with an
  optional language (letters, digits and `+ # . _ -`). It holds no other
  entity and overlaps no quote. Markdown writes it as a backtick fence with
  the language as the info string and reads fences back; JSON uses
  `kind: codeBlock` with `language`. Source-breaking for exhaustive switches
  over `EntityKind`.
- `RichClipboard`, the seam to the system clipboard for text that keeps its
  entities: `write(RichText)` puts its plain text and a rich form on the
  clipboard, `read()` answers a `ClipboardText` (the plain text, plus the
  `RichText` when the clipboard held a rich form). `FakeRichClipboard` and
  `RichClipboardContract.run` are in `testing.dart`. See ADR 032.
- `MediaForm.animatedImage` (`animated_image`): frames in an image format
  (animated WebP, GIF, APNG), decoded by image codecs. `MediaForm.video` is
  now video-coded media only: decoders are registered per form, and with one
  form for both, an animated-image decoder and a video decoder could not be
  registered side by side.
- `RichText.splitsSurrogatePair(text, index)`: whether an offset falls inside
  a surrogate pair, where no entity and no edit range may start or end, so an
  editor can move an edge off it before calling `replaceRange`.
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

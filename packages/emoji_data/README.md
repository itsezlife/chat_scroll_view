# emoji_data

Emoji logic over the `content_model` seams, and nothing else: it reads the
shipped catalog assets, serves them as a `CollectionSource` and a
`SearchSource`, and decides which glyphs the device cannot draw. Pure Dart: no
Flutter, no platform channel, no native code on any platform, no assets of its
own. It depends on `content_model` and on `emoji_catalog_pack` (the data and
its readers); persistence and the asset bundle are the host's.

Decisions: [ADR 021](../../docs/adr/021-content-identity-and-collections.md)
(variants, collections), [ADR 023](../../docs/adr/023-data-layering-and-persistence.md)
(shipping, search, glyph support).

## Types

| Type | Role |
| --- | --- |
| `EmojiAssetLoader` | The asset-bundle seam: `Future<String> Function(String key)`. In Flutter, `rootBundle.loadString`. |
| `EmojiCatalogLoader` | Reads and decodes the structure and one keyword pack per locale, lazily and once; a failed read is retried on the next ask. |
| `EmojiCatalog` | Index over the structure: from any key, base or variant, to its `EmojiEntry` and palette position. The one answer to "does this emoji have variants", shared by grid, picker and search. |
| `BundledKeywordSource` | The shipped packs as a `KeywordSource`: the offline baseline. Spoken name first, then keywords; version 0. |
| `LayeredKeywordSource` | A host `KeywordSource` over the bundled one: the host's records replace the bundled ones per key and add keys the bundle lacks. |
| `EmojiCollectionSource` | `CollectionSource`: recents (from a `RecentsStore`, `SemanticKind.unicodeEmoji`) then one category per catalogue group. Shows the variant the user chose per base (`PreferenceStore`), hides what a `GlyphSupport` says is missing, optional paging. `chooseVariant`, `entryOf` and `shownKeyOf` are the picker path. |
| `EmojiSearchSource` | `SearchSource` over an ordered language set: merged packs, rank exact > prefix > later-token prefix > recents frequency, de-duplicated by key, same variant and glyph rules as the grid. Re-runs when a pack arrives. |
| `MissingGlyphProbe`, `GlyphProbeSnapshot`, `computeGlyphArtFingerprint`, `hashGlyphPixels` | The pure-Dart glyph probe: pixels in, verdicts and an art-version fingerprint out. Rasterising is the host's. |

`package:emoji_data/testing.dart` holds `FakeEmojiAssetLoader`. The fakes and
contract suites of the seams themselves are `content_model/testing.dart`; the
tests of this package run `runCollectionSourceContract`,
`runSearchSourceContract` and `runKeywordSourceContract` against the
implementations.

## Wiring

```dart
final loader = EmojiCatalogLoader(rootBundle.loadString);
final catalog = EmojiCatalog(await loader.structure());
final keywords = LayeredKeywordSource(
  base: BundledKeywordSource(loader),
  overlay: hostKeywordSource, // server packs, if any
);
final emoji = EmojiCollectionSource(
  catalog: catalog,
  recents: recents, // KeyValueRecentsStore.load(...)
  preferences: preferences, // KeyValuePreferenceStore.load(...)
  glyphSupport: glyphSupport, // optional
);
final search = EmojiSearchSource(
  catalog: catalog,
  keywords: keywords,
  languages: const ['de', 'en'], // app locale first
  recents: recents,
  preferences: preferences,
  glyphSupport: glyphSupport,
);
```

## Host contract

| The host provides | The host must not |
| --- | --- |
| An `EmojiAssetLoader` over its bundle, and `emoji_catalog_pack` as an app dependency so the assets are bundled. | Parse the asset files itself, or expect a bundled pack for a language outside `EmojiCatalogPackAssets.locales`. |
| Loaded `RecentsStore` and `PreferenceStore` (the reference ones over a `KeyValueStore` live in `content_model`). | Hand over a store that is still loading: the sources read them synchronously. |
| The ordered language set for search (app locale first, English after). | Rely on the sources to follow a locale change: build a new `EmojiSearchSource`. |
| The decision when a pick counts: it calls `RecentsStore.record`. | Expect picks from search results to be recorded; the store ignores `PickSource.search`. |
| Optionally a `GlyphSupport` and a host `KeywordSource`. | Expect hidden emoji to change the atlas plan: filtering happens at display. |
| Titles, icons and the page order of the categories, keyed by group id (`CollectionId.category(id)`). | Look for titles or covers on the collections: there are none. |

## Notes

- Group ids are Unicode's, as `emoji_catalog_pack` writes them (`smileys-emotion`,
  `people-body`, ...). An emoji is in exactly one category.
- Loading a collection is in memory but asynchronous: `loading` is published
  at once and `loaded` after a microtask. Nothing here reaches `failed`;
  `EmojiSearchSource` reaches it when a keyword pack exists and cannot be read,
  and retries when the same text is searched again.
- The glyph probe does not yet implement `GlyphSupport`; that adaptation, its
  persistence and its pacing are the glyph probe issue.

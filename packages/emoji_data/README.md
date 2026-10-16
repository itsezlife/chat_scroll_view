# emoji_data

Emoji logic over the `content_model` seams, and nothing else: it reads the
shipped catalog assets, serves them as a `CollectionSource` and a
`SearchSource`, and decides which glyphs the device cannot draw. Pure Dart: no
Flutter, no platform channel, no native code on any platform, no assets of its
own. It depends on `content_model` and on `emoji_catalog_pack` (the data and
its readers); persistence and the asset bundle are the host's.

Decisions: [ADR 021](../../docs/adr/021-content-identity-and-collections.md)
(variants, collections), [ADR 023](../../docs/adr/023-data-layering-and-persistence.md)
(shipping, search, glyph support), [ADR 006](../../docs/adr/006-panel-catalog-viewport.md)
(the probe shares the bake pass). Glossary: [Content and Assets](../../docs/content/CONTEXT.md).

## Types

| Type | Role |
| --- | --- |
| `EmojiAssetLoader` | The asset-bundle seam: `Future<String> Function(String key)`. In Flutter, `rootBundle.loadString`. |
| `EmojiCatalogLoader` | Reads and decodes the structure and one keyword pack per locale, lazily and once; a failed read is retried on the next ask. |
| `EmojiCatalog` | Index over the structure: from any key, base or variant, to its `EmojiEntry` and palette position. The one answer to "does this emoji have variants", shared by grid, picker and search. |
| `BundledKeywordSource` | The shipped packs as a `KeywordSource`: the offline baseline. Spoken name first, then keywords; version 0. |
| `LayeredKeywordSource` | A host `KeywordSource` over the bundled one: the host's records replace the bundled ones per key and add keys the bundle lacks. |
| `EmojiCollectionSource` | `CollectionSource`: recents (from a `RecentsStore`, `SemanticKind.unicodeEmoji`) then one category per catalogue group. With a `KeywordSource` and `languages` every item carries its spoken name (the first word of its record, from the first language that names it). Shows the variant the user chose per base (`PreferenceStore`), hides what a `GlyphSupport` says is missing, optional paging. `chooseVariant`, `entryOf` and `shownKeyOf` are the picker path. |
| `EmojiSearchSource` | `SearchSource` over an ordered language set: merged packs, rank exact > prefix > later-token prefix > recents frequency, de-duplicated by key, same variant and glyph rules as the grid. Re-runs when a pack arrives. |
| `MissingGlyphProbe` | The `GlyphSupport`: cells in (`observe`), `supports` and `artVersion` out, one signal per step on `changes`. Flags a cell identical to a missing-glyph reference or empty. Keeps its verdicts through a `KeyValueStore`, under the art version they were taken for. Rasterising is the host's. |
| `computeGlyphArtFingerprint`, `defaultArtSentinelGlyphs` | The system emoji art version signal: a pixel fingerprint of a few sentinel glyphs, one rendered per frame, plus an optional host `supplement` (such as the OS version). No native call. |
| `PacedGlyphProbePass` | The probe's own pass for a host with no bake to share (web): a few cells per frame under a governor, paused while the panel opens or scrolls. |
| `GlyphProbeSnapshot`, `hashGlyphPixels` | The persisted record (hashes, never pixels) and the cell comparison key. |

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
  keywords: keywords, // spoken names for screen readers
  languages: const ['de', 'en'], // app locale first
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
| Optionally a `GlyphSupport` (the `MissingGlyphProbe`, wired to the bake as above) and a host `KeywordSource`. | Expect hidden emoji to change the atlas plan: filtering happens at display. |
| The pixels: a system rasteriser for the sentinels (and, without an atlas, for every cell), a `KeyValueStore`, the frame clock, and optionally a supplementary art-version text. | Expect `emoji_data` to draw anything or read the OS version itself. |
| The bridge between the bake and the probe (three functions), and which art version the atlas cache key uses (`probe.artVersionReady`). | Give the atlas a second, separately computed art version, or let the probe's verdicts filter the atlas plan. |
| Titles, icons and the page order of the categories, keyed by group id (`CollectionId.category(id)`). | Look for titles or covers on the collections: there are none. |

## Glyph support

`MissingGlyphProbe` answers which emoji the system cannot draw, with no native
code on any platform. It does not rasterise: it is shown the cells somebody
rasterised and compares each with the cell of a missing-glyph reference
(U+10FFFF) or finds it empty.

```dart
final probe = MissingGlyphProbe(
  glyphs: catalogGlyphs,
  store: keyValueStore,
  // Rendered once; one sentinel per frame. `supplement` is optional.
  artVersion: () => computeGlyphArtFingerprint(
    sentinels: defaultArtSentinelGlyphs,
    pixelsOf: systemRasteriserPixelsOf,
    nextFrame: nextFrame,
    supplement: operatingSystemVersion,
  ),
);
// One art version for the probe and the atlas cache key:
final atlasArtVersion = ComputedGlyphArtVersion(probe.artVersionReady);
// The bake pass feeds the probe, so no glyph is drawn twice:
final observer = CallbackGlyphBakeObserver(
  pendingReferences: () => probe.pendingReferences,
  wants: probe.wants,
  observe: probe.observe,
);
```

- **Cells in.** With a glyph atlas the bake already rasterises every glyph; it
  shows the probe each cell (`GlyphBakeObserver`), so the probe adds no
  rasterising pass and inherits the bake's pacing (a few glyphs per frame under
  a frame-time governor, paused while the panel opens and while scrolling).
  Hashing a cell is the probe's only work on the drawing thread. Without an
  atlas (web), `PacedGlyphProbePass` draws the cells itself under the same
  rules.
- **Answers out.** `supports` is `true` until a cell is found missing, so a
  probe that is late or never finishes shows everything, as with no probe.
  Answers are published on `changes` once the art version is known, together
  with it, then once per burst of cells that hid something new.
- **Art version.** The sentinel fingerprint changes when the system redraws
  them. The sentinels sample a few glyphs, so an update confined to others goes
  unseen by the pixels; a host that knows its OS version means new art passes it
  as `supplement` and accepts a re-probe and a re-bake on every OS update. The
  probe produces the version once and `artVersionReady` hands the same value on
  as the atlas cache key component.
- **Persistence.** The cell hashes are kept in one record (namespace
  `emoji_data`, key `glyph_probe`) with the art version they belong to. On a
  launch that restores baked pages from disk the bake draws nothing, so the
  restored record is what supplies the verdicts; a record of another art
  version is ignored and replaced when the probe completes. A failing store is
  reported to the zone and costs only the record.
- **The atlas plans the unfiltered list.** Verdicts hide emoji at display
  (`EmojiCollectionSource`, `EmojiSearchSource`); they never change the
  catalogue hash, so a verdict never re-bakes a page.

### Validation by platform

Result of the rasterise-and-compare rule (cell identical to the reference cell
of U+10FFFF, on a transparent background) over all 1,923 base emoji of Emoji
18.0, run with a prototype of this probe in debug builds. The shipped code
(shared bake pass, persistence, pacing) is covered by tests against a fake
system only; the rows below say nothing about it on a device.

| Platform | Emoji version rendered | Result |
| --- | --- | --- |
| macOS 26.6.1 | up to Emoji 17.0 | Flagged exactly Emoji 18.0 (9), 0 false positives. |
| iOS 26.4 simulator | up to Emoji 17.0 | Same as macOS. |
| iOS 18.1 simulator | up to Emoji 15.1 | Flagged Emoji 18.0 (9) and 7 of 8 of Emoji 17.0 by reference (the eighth only by a width rule this probe does not use); the Emoji 16.0 glyphs draw an identical placeholder that is not the reference cell, so the reference rule misses all of them. |
| Chrome 155 (web) | Noto Color Emoji slices of the Flutter version | Correct once the fallback font had loaded (Emoji 17.0 and 18.0 flagged). Before it loads every cell equals the reference; there is no completion signal, hence the guard below. |
| Android | not measured | **Open: needs a device.** Fallback if the probe fails: an Android-only native adapter package (`emoji_glyph_android`) behind `GlyphSupport`, supplying glyph support only, never the art version. |
| Windows | not measured | **Open: needs a device.** |
| Linux | not measured | **Open: needs a device.** |

Known limits of the rule, kept as behaviour:

- **A system that draws nothing is not believed.** When sixteen or more cells
  have been seen and every one is flagged, the verdicts are treated as no
  information: nothing is hidden or persisted. That is a browser whose emoji
  font has not loaded, not a system that lacks all its emoji. A host on the web
  starts `PacedGlyphProbePass` once its fonts are ready.
- **Distinct placeholders are not caught.** A system that draws a different
  placeholder per missing glyph (iOS 18.1 for Emoji 16.0) is invisible to the
  reference comparison; those glyphs stay shown, which is the behaviour with no
  probe.

### Cost

Measured on the development Mac (AOT build, `hashGlyphPixels`): 1759 cells of
76 x 76 RGBA hash in about 60 ms in total, about 0.5 ms for a 16-glyph strip; the
persisted record is about 53 KB. These are host-side costs of the probe on top
of the bake and do not stand in for a mid-range Android measurement, which is
open together with the zero-dropped-frames check on the reference device.

## Notes

- The sources set no `spokenName` on the descriptors they publish. A screen
  reader reads the glyph of a unicode emoji; the CLDR spoken names stay in the
  keyword packs (`BundledKeywordSource` searches them).
- Group ids are Unicode's, as `emoji_catalog_pack` writes them (`smileys-emotion`,
  `people-body`, ...). An emoji is in exactly one category.
- Loading a collection is in memory but asynchronous: `loading` is published
  at once and `loaded` after a microtask. Nothing here reaches `failed`;
  `EmojiSearchSource` reaches it when a keyword pack exists and cannot be read,
  and retries when the same text is searched again.

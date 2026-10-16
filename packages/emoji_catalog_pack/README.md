# emoji_catalog_pack

The emoji catalog as shipped data: one locale-independent **structure** asset,
one **keyword pack** per locale, and the pinned generator that builds them from
Unicode and CLDR. Pure Dart: the assets are bundled by Flutter hosts, the
readers decode plain text and depend only on `content_model`.

Nothing here knows about panels, pages or search ranking. Loading an asset,
merging packs and ranking results belong to the packages that consume them.

## Assets

| Asset | Content | Raw | Gzip (level 9) |
| --- | --- | --- | --- |
| `assets/structure.tsv` | Groups, subgroups and 1759 entries in palette order; each entry is a base key plus its variants (2204) with skin-tone and gender tags | 78.2 KB | 13.5 KB |
| `assets/keywords/<locale>.tsv` | Per locale: the CLDR spoken name and search keywords of every entry and of every gender variant (1923 records) | 96-250 KB | 31-49 KB |
| `assets/LICENSE-UNICODE.txt` | Provenance (Emoji and CLDR versions) and the Unicode licence text | 3.4 KB | |

The structure accounts for every fully-qualified sequence of the pinned
`emoji-test.txt` exactly once: 3963 sequences, 1923 without a skin tone and
2040 with one. A sequence is a variant of another entry when removing its
tones and normalising its gender gives that entry (`1F469 200D 1F4BB`, woman
technologist, is the woman variant of `1F9D1 200D 1F4BB`; a mixed-tone
handshake belongs to the handshake). Formats are documented on
`EmojiCatalogStructure` and `EmojiKeywordPack`; both readers are strict and
throw a `FormatException` on anything they cannot read.

`EmojiKeywordPack` is the reader of this asset and also carries the spoken
names. It is not `content_model`'s `KeywordPack`, the language-keyed value a
`KeywordSource` supplies to search: the package that wires the assets to
search converts one into the other.

### Size report

Gzip level 9, measured on the committed assets (a test holds each pack under
52 KB and the structure under 16 KB).

| Locale | Raw KB | Gzip KB |
| --- | --- | --- |
| en | 109.8 | 36.2 |
| de | 121.0 | 40.0 |
| es | 96.5 | 30.8 |
| fr | 131.2 | 40.5 |
| hi | 249.9 | 48.1 |
| it | 150.6 | 46.3 |
| ja | 115.9 | 37.6 |
| nl | 115.9 | 38.7 |
| pt | 124.0 | 39.5 |
| ru | 205.5 | 48.8 |
| zh | 101.0 | 40.7 |

Latin-script packs land at 31-46 KB and Hindi and Russian at 48-49 KB.
Keywords that repeat the spoken name are dropped (2 to 9 percent of a pack).
Loading one locale costs one pack plus the 13.5 KB structure.

## Host contract

| The host provides | The host must not |
| --- | --- |
| The asset bundle: loads the text behind the asset keys `EmojiCatalogPackAssets.structure` and `keywordPack(locale)` and passes it to `EmojiCatalogStructure.decode` / `EmojiKeywordPack.decode`. Depending on this package is what bundles the assets. | Parse the files itself; the formats are internal to the decoders. |
| The ordered language set it wants packs for. A locale without a shipped pack (`EmojiCatalogPackAssets.locales` lists the shipped ones) is a host decision (fall back, or fetch a pack of its own). | Expect a pack for every CLDR locale: the shipped set is the locales of `tool/inputs.lock`. |
| A spoken name for a tone variant: the entry's own name, extended by the host if it wants the tone read out. | Look a tone variant up in a pack: only entries and gender variants have records. |
| Any server-supplied or newer keyword pack through a `KeywordSource`, keyed by the same `ContentKey`s. | Assume the keys of a newer Emoji version are in the shipped structure. |

Dependency direction: `panel_shell`, `panel_pages` and `panel_presentation`
never depend on this package (`scripts/check` enforces it). A composition root
reads the assets and hands data to the pages.

## Regenerating

Everything under `assets/` is generated; do not edit it.

```shell
# write assets/ from tool/inputs.lock (downloads and verifies inputs on first use)
dart run tool/generate.dart

# the gate scripts/check runs (tool/check): fails unless assets/ is reproducible
tool/check

# move to other versions or locales, then regenerate and commit both
dart run tool/generate.dart lock <emoji-version> <cldr-tag> [locale ...]
dart run tool/generate.dart
```

Inputs are cached in `tool/.cache` (untracked; `EMOJI_CATALOG_PACK_CACHE`
overrides it) and are only read as text. Every run verifies them against the
SHA-256 in `tool/inputs.lock`; a URL that starts serving other bytes fails the
run instead of changing the catalog. Changing a pinned version without
regenerating fails `tool/check`, because the lock refuses a URL that does not
belong to its versions and the assets carry the versions they were built from.

### Pins

| Input | Pin |
| --- | --- |
| Unicode Emoji | 18.0, `emoji-test.txt` from `https://unicode.org/Public/18.0.0/emoji/`, sha256 `8f3735cd...ab21a` |
| CLDR | `release-49-beta4` annotations and annotationsDerived per locale, `LICENSE` |
| Locales | en, de, es, fr, hi, it, ja, nl, pt, ru, zh |

The complete list with full checksums is `tool/inputs.lock`. CLDR 48.2, the
latest stable release, has no names for Emoji 17 and 18 additions, which is
why the pin is a CLDR 49 beta; move to the final tag with the `lock` command
when it is published.

## Decisions

- [ADR 023: Data layering and persistence](../../docs/adr/023-data-layering-and-persistence.md)
  (structure and keywords ship as separate text assets, loaded lazily per
  locale), [ADR 020](../../docs/adr/020-package-topology.md) (dependency
  direction), [ADR 030](../../docs/adr/030-testing-policy.md) (the generator
  gate).
- Glossary: [Content and Assets](../../docs/content/CONTEXT.md).
- Unicode groups are kept as shipped (nine, `People & Body` separate from
  `Smileys & Emotion`; components excluded). Mapping them to panel categories
  is a page decision.
- Direction variants (`facing right`) are entries of their own: the modifier
  model has tones and genders only.
- Keyword packs carry no per-tone records. Tone variants are spoken and found
  as their entry; per-tone CLDR names would add about 14-17 KB gzip to every
  pack.
- The CLDR parser reads the one-element-per-line annotation files with a
  regular expression, so the generator has no XML dependency; an element it
  cannot read stops the run.

## Licence

Generated assets derive from Unicode and CLDR data under the Unicode License
v3 (`assets/LICENSE-UNICODE.txt`).

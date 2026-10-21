# ADR 023: Data layering, catalog shipping and persistence

Catalog data comes from small seams in `content_model` that pages compose.
The emoji catalog is generated from pinned Unicode and CLDR inputs and ships as
one structure asset plus one keyword pack per locale. Persistence goes through
one `KeyValueStore` seam. Change notification is the pure-Dart `package:listen`
(`Listenable`, `ValueListenable`, `ChangeNotifier`, `ValueNotifier`), not a type
of this repository.

**Status**: Accepted  
**Date**: 2026-10-16  
**Amended**: 2026-10-16 — change notification is [`package:listen`](https://pub.dev/packages/listen), see [Amendment](#amendment-change-notification-is-packagelisten)  
**Amended**: 2026-10-17 — a recents list belongs to the page that files into it, see [Amendment](#amendment-one-recents-list-per-page)  
**Relates to**: [ADR 020](020-package-topology.md), [ADR 021](021-content-identity-and-collections.md), [ADR 022](022-asset-cache-and-media-pipeline.md)

## Decided

| Area | Decision |
| ---- | -------- |
| Sourcing | A pinned, reproducible generator in the repo: Unicode `emoji-test.txt` (structure, order, groups, variants) plus CLDR annotations (keywords and spoken names per locale). Inputs are pinned by version and the Unicode-3.0 licence notices are kept. The copied picker tables and the Dart `const` locale files are deleted. |
| Shipping | One locale-independent **catalog structure** asset and one **keyword pack** asset per locale (JSON or TSV), loaded lazily, about 26 to 41 KB gzip per locale. Assets and generator live in `emoji_catalog_pack`. |
| Keyword seam | `KeywordSource`: bundled packs are the offline baseline; a host may supply server packs (per language, versioned). |
| Seams | In `content_model`: `CollectionSource` (ordered collections, per-collection contents with state and paging), `SearchSource` (query to a paged results collection), `RecentsStore`, `PreferenceStore`, `KeywordSource`, `GlyphSupport`, `KeyValueStore`, `ContentResolver`, and `RichClipboard` ([ADR 032](032-rich-clipboard.md)). No facade interface. Pages compose only what they need (emoji page: all; GIF page: collection, search and recents). |
| Reactivity | `package:listen`'s `Listenable` and `ValueListenable` on the read side, `ChangeNotifier` and `ValueNotifier` on the owner side; synchronous, snapshot dispatch, one notification per assigned value. The repository owns no notification type (see the [Amendment](#amendment-change-notification-is-packagelisten) for the contract differences). Flutter's widgets read it through one small builder per package that needs one. |
| Glyph support | `GlyphSupport` seam with one cross-platform pure-Dart rasterise-and-compare probe in `emoji_data`. No native directory and no method channel anywhere. The system emoji art version signal that invalidates the probe result and the baked atlas cache key is a pixel fingerprint of a few sentinel glyphs rendered once per launch and compared with the stored value. An operating-system version string is at most a supplementary signal. The signal is produced once and shared by every consumer. The probe is paced like the bake: a few glyphs per frame under a frame-time governor, paused during the panel open animation and scrolling, and sharing the bake's rasterisation pass where one exists. Validation on Android, Windows and Linux is an acceptance criterion; the fallback is a thin Android-only native adapter behind the same seam, supplying glyph support and never the version signal. Without an adapter, everything shows. |
| Persistence | Logic packages depend only on `KeyValueStore`: async get, set and remove, namespaced keys, versioned values. The `shared_preferences` adapter lives in `kv_shared_preferences`; the in-memory fake lives in `content_model`. Async factories return loaded stores, so there is no unloaded state and no silent drop before load. One namespace per package, structured versioned records, no legacy dual-read. |
| Recents | `record(key, {source})` is called by the host when it decides a pick counts (insert or send). Search picks do not record. Any content key can be recorded; entries keep count and last-used time; order is frequency, then recency; default cap 48, configurable; recents are separate per semantic kind. Bare keys resolve through `ContentResolver` for display. |
| Search | The host supplies an ordered language set (default: app locale plus English). One pack per language, merged. Rank: exact, then prefix, then later-token prefix, then recents frequency; de-duplicate by key. Flags and CLDR names are plain keywords. Results are a paged collection. |
| Placement | `content_model`: interfaces, reference implementations over the seams (KV-backed recents and preference stores) and fakes. `emoji_data`: emoji-specific logic only. Server-backed sticker and GIF sources, and any `KeywordSource` fed from a server, are host-implemented. |

## Why

- The old catalog was stale and unstamped: 313 emoji missing, 12 duplicates, about 26% keyword drift. Eleven locales cost 1.8 MB in the binary, and the native plugin worked only on Android. Telegram bundles structure and ships keyword packs per language from the server on all three clients.
- The old code had five hand-rolled listener mechanisms and persistence across three stores and four key families, with silent drops before load.
- Telegram clients record recents at send time and keep both unicode and custom-emoji ids; keyword search is multi-language.
- A pixel fingerprint needs no native call and tracks what matters, the art, which an OS version string does not (it changes without the art changing).

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| All locales as `const` in the binary; published data packages | No server-pack seam; published packages lag the Emoji release and lack multilingual CLDR keywords |
| Per-kind facades; one generic content data source | A monolith again |
| Asynchronous streams for state; Flutter `Listenable` in the leaf | Async lag and subscription lifetimes; the leaf stays pure Dart (typed events use a *synchronous* broadcast `Stream`, see the Amendment) |
| A homemade `Observable` family in `content_model` | A second implementation of what `package:listen` (the framework's own `Listenable`, standalone) already is, with its own contract to maintain and teach |
| Keeping the Android-only native plugin; a native font-version call; an unpaced probe; dropping filtering; bundling emoji art | Native code in `emoji_data`; a long raster-thread burst; unsupported glyphs would show as boxes; the system look would be lost |
| `shared_preferences` directly in logic packages; per-package files or databases | Couples logic to one plugin and fragments persistence |
| Pure MRU recents; recording inside the page on tap; app-locale-only search | Telegram parity and host control over what counts as a pick |

## Amendment: change notification is `package:listen`

The primitive this ADR first called `Observable` was a homemade family in
`content_model` (`Observable`, `ValueObservable`, `EventObservable`, their
notifiers, `batch`, a fake and a contract suite). It is replaced by the
pure-Dart `package:listen` (`^1.0.1`): the same `Listenable`,
`ValueListenable`, `ChangeNotifier` and `ValueNotifier` as
`package:flutter/foundation`, standalone. Packages that name one of its types
declare `listen` themselves; no package re-exports it.

| Was | Is |
| --- | --- |
| `Observable`, `ObservableListener` | `Listenable`, `VoidCallback` |
| `ValueObservable<T>`, `ObservableValue<T>` | `ValueListenable<T>`, `ValueNotifier<T>` |
| `ObservableNotifier` | `ChangeNotifier`, mixed into or extended by the owner (`notifyListeners` is protected) |
| `EventObservable<T>`, `EventNotifier<T>` | A synchronous broadcast `Stream<T>` the owner publishes to (see below) |
| `batch` | Gone: assign the final value once |
| `ValueObservableBuilder` | `ListenValueBuilder`, one copy per package that needs one (`chrome_foundation` must not depend on `content_model`) |
| `FakeObservable`, `runObservableContract` | Gone: they tested the deleted implementation |

**Contract differences owners and hosts must know.** None is hidden by an
adapter; each is handled where the state is owned.

- **No dedup on add.** A listener added twice is called twice and removed
  twice. Owners and widgets add and remove symmetrically.
- **Disposal asserts.** `addListener`, `notifyListeners` and a second
  `dispose` on a disposed `ChangeNotifier` fail an assertion in debug builds
  (`removeListener` stays allowed). An owner that can be signalled late (an
  async callback, a frame callback) keeps its own `disposed` flag, and its
  `dispose` stays idempotent, as the seams' contract suites require.
  `dispose` from inside one of the owner's own listeners also asserts.
- **A throwing listener goes to the static `Listenable.onError`.** Its default
  rethrows, which aborts the notification at that listener and leaves the
  notifier's dispatch state behind. **The host sets it, once, at startup**
  (the example's `reportListenerErrors`, installed by `bootApp`, reports to
  `FlutterError.reportError` and does not rethrow). Library code never
  assigns it; it may call it (`CancellationToken` does for a callback added
  after cancellation).
- **No payload, no batching.** A signal carries nothing; a value owner
  assigns the value it wants heard. A mutation that changes several things
  assigns the final value once.
- **Name collisions.** `package:flutter/foundation` exports types of the same
  names. A file that imports Flutter imports `package:listen/listen.dart as
  listen` and writes `listen.ValueListenable<T>`; a pure-Dart file imports it
  unprefixed. A `package:listen` type is not accepted where Flutter's is
  expected (`ListenableBuilder`, `Listenable.merge` of Flutter): the host
  adapts at the boundary (the example's `ListenableBridge`).

**Typed events** (scroll events, panel events, scroll activity, result
counts) are synchronous broadcast `Stream`s, not listenables: `listen`
returns a subscription the consumer cancels where it used to
`removeListener`. A synchronous broadcast controller throws a `StateError` when
an event is added from inside a listener, and that is routine here (the bake
activity reports "moving" from inside the motion event that caused it, a host
selects a page from inside a panel event). Each publisher (`panel_catalog`'s
controller, `panel_shell`'s controller) therefore publishes through a small
internal queue: an event published during delivery is delivered after the
event in flight has reached every listener, still before the outermost
publish returns, so the events stay synchronous and every listener sees one
order. Delivery order of a nested event changed from "inside" to "after"; no
listener depended on the former. A throwing stream listener is reported to the
zone and the others still run (the stream's own behaviour). After disposal
the stream is closed: a later `listen` gets a done subscription.

## Related

- Glossary: [Content and assets](../content/CONTEXT.md)
- Atlas side of the shared bake pass: [ADR 022](022-asset-cache-and-media-pipeline.md), [ADR 006](006-panel-catalog-viewport.md)

## Amendment: more than one missing-glyph reference

`MissingGlyphProbe.defaultReferences` holds U+10FFFF and U+F0000 (plane 15
private use). Some systems draw the noncharacter as nothing while an emoji their font
lacks still gets the missing-glyph box; no system font covers the private use
character, which is drawn as that box. The probe keeps a cell per reference,
judges nothing until every reference is seen, and asks the bake for every
reference not seen yet. Its record (version 2) keeps the cell of each
reference by name and is trusted only for the same references, so verdicts
taken against one reference are taken again.

## Amendment: a default variant

`PreferenceStore.defaultVariant` / `setDefaultVariant(EmojiModifiers)`: the
reference desktop client's "tone for all". Setting it forgets every choice
made per emoji; choices made afterwards are kept beside it and win. The
emoji sources show, for an emoji with no choice of its own, its variant whose
people all have the default's tone, else its base; recents are untouched. The
key-value store persists it as `"defaultVariant": [tone names]` (empty for
the emoji as it is).

## Amendment: one recents list per page

The kind a pick is recorded under names a **recents list**, and the list
belongs to the page that files into it, not to the semantic kind of each key
in it. The store is unchanged: still one list per `SemanticKind` value, ranked
by frequency, then recency.

| Area | Decision |
| ---- | -------- |
| Emoji page | Files every pick under `SemanticKind.unicodeEmoji` (`EmojiPagePolicy.recentsKind`): unicode emoji and custom emoji (document keys) in one list, as both reference clients keep one list for the emoji tab. Remove, clear and the recents menu act on that list whatever the key. |
| Content kind | Stays in the descriptor. A consumer that needs to know what a recent is reads its key or descriptor, never the list's kind; the host inserts and copies by key. |
| Describing | `EmojiCollectionSource` describes the keys outside its catalogue through an optional host `ContentResolver`, batched, once per key. A key is bare until answered, described once resolved, and leaves the list when the resolver does not know it; a failed batch keeps the keys bare and is asked again at the next change. |

### Why

- Telegram Android keeps one `recentEmoji` list of unicode and custom emoji
  ids; Telegram-iOS one ordered list for the emoji tab. A list per content
  kind would split what the user sees as one row, and merging two lists has
  no shared order: each ranks only against itself.

### Rejected

| Alternative | Why not |
| ----------- | ------- |
| A store query that ranks several kinds together | A seam change across every store and fake for the same result; the kind would still have to say which lists a page merges |
| Custom emoji recents under `customEmoji`, shown after the unicode ones | Two blocks in one row, in no order the user made |


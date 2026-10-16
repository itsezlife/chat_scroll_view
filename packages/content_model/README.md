# content_model

Pure-Dart value types that identify and group catalog content (stickers,
GIFs, custom and unicode emoji), formatted text (`RichText`), the one
synchronous change-notification primitive, and the seams through which packages
reach data. No Flutter, no I/O, one dependency (`meta`), plus `package:test` for
the opt-in `testing.dart`. Every other package in the workspace speaks these
types, so it depends on no workspace package (`scripts/check` enforces both).

## Types

| Type | Role |
| --- | --- |
| `ContentKey` | The one closed identity: `unicode` (the exact sequence shown or sent), `document` (opaque id), `external` (web or inline-result id). Value equality; a stable string encoding (`encoded`, `parse`, `tryParse`) for storage. |
| `ContentDescriptor` | A key plus `SemanticKind` (what it is to the user) and `MediaForm` (how it renders), and facts known before loading: animated, tintable, locked, size, thumbnail, spoken name. |
| `Collection` | `CollectionId` + `CollectionMetadata` + `CollectionContents` (`idle`, `loading`, `loaded` with `CollectionItem`s and a `PageToken`, `failed`). Sets, personal lists, search results and trending are all collections. |
| `EmojiEntry` | A base unicode key and its variants. Each variant is its own key, tagged with `EmojiModifiers` (ordered tones, gender). |
| `InlineContentRef` | A key plus the mandatory plain-text alternative, for content embedded in text. |
| `RichText` | Plain text plus `Entity` spans (UTF-16 offset and length, and an `EntityKind`: bold, italic, underline, strike, spoiler, code, quote, link, mention, inline content). Always canonical, so equal meaning is equal value; edits (`insert`, `delete`, `replaceRange`, `slice`) keep the entities consistent; JSON in and out for drafts. |
| `RichTextMarkdown` | Opt-in, in `package:content_model/markdown.dart`: `RichText` to and from the markdown the viewport's markdown library reads. The host's helper for send, draft, edit-load and body materialise. |
| `Observable`, `ValueObservable<T>`, `EventObservable<T>` | The read sides of change notification: a signal, a signal guarding a snapshot, a typed event stream. Listeners run synchronously; dedup-on-add, snapshot dispatch, silent after dispose. |
| `ObservableNotifier`, `ObservableValue<T>`, `EventNotifier<T>` | The owner sides. `batch` turns many changes into one signal; `ObservableValue` skips equal snapshots. |
| `CollectionSource`, `SearchSource` | Publish `Collection`s as immutable snapshots, with load and paging commands. Failure is a state, never an exception. |
| `RecentsStore`, `PreferenceStore` | Loaded, synchronous-read stores for picks (per `SemanticKind`, frequency then recency) and typed user choices. |
| `KeywordSource`, `KeywordPack` | Per-language search keywords, bundled or supplied by the host. |
| `GlyphSupport` | Which unicode keys the device draws, and the identity of its emoji art. Optimistic: `true` until known missing. |
| `KeyValueStore`, `StoredValue` | Namespaced, versioned string persistence; the only way logic packages reach durable storage. |
| `ContentResolver` | Batched async resolution of bare keys to descriptors. |
| `KeyValueRecentsStore`, `KeyValuePreferenceStore` | The reference `RecentsStore` and `PreferenceStore` over a `KeyValueStore`. Created only by their async `load`, which reads persisted state first, so no store exists unloaded. Structured, versioned JSON records, one namespace per package. |

## Testing

`package:content_model/testing.dart` is opt-in: production code never imports
it and `content_model.dart` never exports it (`scripts/check` enforces both).

| Seam | Fake | Contract suite |
| --- | --- | --- |
| `Observable` | `FakeObservable` (hand-signalled, counts listeners) | `runObservableContract` |
| `KeyValueStore` | `FakeKeyValueStore` (in memory, `failure` switch) | `runKeyValueStoreContract` |
| `RecentsStore` | `FakeRecentsStore` | `runRecentsStoreContract` |
| `PreferenceStore` | `FakePreferenceStore` | `runPreferenceStoreContract` |
| `CollectionSource` | `FakeCollectionSource` (scripted `FakePages`, pausable, failure switches) | `runCollectionSourceContract` |
| `SearchSource` | `FakeSearchSource` | `runSearchSourceContract` |
| `KeywordSource` | `FakeKeywordSource` | `runKeywordSourceContract` |
| `GlyphSupport` | `FakeGlyphSupport` | `runGlyphSupportContract` |
| `ContentResolver` | `FakeContentResolver` (records batches) | `runContentResolverContract` |

A contract suite takes a factory for the implementation under test. The
suites for sources and resolvers also take a small harness that names facts
about the content only the implementation knows (an id with two pages, a key
it cannot resolve) and, where a backend can be made to fail, a switch for it.
Run the suite from the implementation's own test file:

```dart
void main() {
  runKeyValueStoreContract(MyPlatformKeyValueStore.new);
}
```

## Host contract

| The host provides | The host must not |
| --- | --- |
| Keys for its content. A `document` or `external` id is an opaque string, unique per piece of content. | Put a kind in a key, or build a second key for the same content. Kind lives in the descriptor. |
| Descriptors where it already knows the facts. Unrecognised kinds and forms decode through `SemanticKind.fromValue` / `MediaForm.fromValue` to `unknown`. | Store "descriptor loaded" state on a list. A bare `CollectionItem` is the unresolved case. |
| Fetch credentials and provenance, kept on its side and keyed by `ContentKey`. | Expect this package to carry credentials, file references or other fetch data. |
| Titles as data (`CollectionMetadata.title`), in the source's own language. | Rely on a collection carrying an icon or a localized label. A page maps the `CollectionId` to those. |
| One `Collection` per change. A first-load failure is `failed`; later page trouble stays `loaded` with its `nextPageToken`. | Mutate items or variants: the lists are unmodifiable copies. |
| Entries whose variant keys are the exact sequences it sends, and tags for each. | Compute a variant by appending a modifier to the base, or fold FE0F spellings into one key. Keys compare exactly. |
| Implementations of the seams it needs: sources, a `ContentResolver`, a `KeyValueStore` adapter for its platform storage. Each seam's dartdoc states the contract to meet. | Reach a seam's implementation through a downcast, or let a seam throw for an expected condition. Missing data is null or an absent entry; a failed load is a `failed` state. |
| Its stores from `KeyValueRecentsStore.load` and `KeyValuePreferenceStore.load` over its `KeyValueStore`, awaited once at startup. | Try to use a store before `load` completes (there is no such store), or wrap `load` in a second layer of caching. |
| A test for every implementation of a seam: the matching `run...Contract` suite from `testing.dart`. | Ship a fake, or import `testing.dart`, from production code. |
| The decision that a pick counts: it calls `RecentsStore.record` on insert or send, with the `PickSource` it came from. | Record from inside a page, or record a pick made from search results. |
| One `KeyValueStore` namespace per package, and a version on every value it writes. | Share a namespace between packages, or expect the store to migrate or interpret a value. |
| Disposal: whoever creates a notifier, source or store disposes it. | Signal from a consumer's side (only the owner type can), or rely on a listener running after dispose. |
| Listeners that tolerate being called synchronously, inside the call that changed the state, and that read the owner for the new state. | Throw from a listener to stop the others (a throwing listener is reported to the zone and the rest still run), or assume a signal carries a payload (`Observable` has none; use `EventObservable`). |
| Links and mentions as entities, made where the user or the host decides what is a link (a pasted URL, a picked mention). | Expect `RichText` or the markdown helper to detect a bare URL or `@name`. Body linkify is host-invoked (ADR 017); the helper writes and reads only what is already an entity or a markdown link. |
| Imports of `RichText` that avoid the Flutter widget of the same name: `hide RichText` on the widgets import, or `as model` here. | Import both unqualified in one file. |
| The `mention:` scheme read as a mention when it decodes a body, and its own targets for links. | Make a link whose target starts with `mention:`; the model rejects it. |
| Edits as `RichText` operations, passing the styled run to continue a style (equal kinds that touch merge). | Expect typing at the edge of a styled run to extend it, or edits inside a mention or inline content to keep it: the entity is removed. |

## Rich text and markdown

`RichText` is the neutral value a composer produces and a host stores, sends
and loads back for editing. It shares its name with Flutter's `RichText`
widget; the glossary term is _rich text_ and the name stays, so a host file
that needs both writes `import 'package:flutter/widgets.dart' hide RichText;`.

`package:content_model/markdown.dart` is the host helper between `RichText` and
a markdown body. It is a separate library, has no markdown dependency, and
follows the dialect of the viewport's markdown library (styles are toggles,
which lets styles overlap). `RichTextMarkdown` documents the mapping, the
escape rules and where that dialect falls short. Bodies stay markdown; nothing
here is called from a scroll or paint path.

## Decisions

- [Content identity and collection model](../../docs/adr/021-content-identity-and-collections.md)
- [Data layering](../../docs/adr/023-data-layering-and-persistence.md)
- [Testing policy](../../docs/adr/030-testing-policy.md)
- [Body linkify is host-invoked](../../docs/adr/017-body-linkify-host-invoked.md)

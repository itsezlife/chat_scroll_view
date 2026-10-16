# content_model

Pure-Dart value types that identify and group catalog content (stickers,
GIFs, custom and unicode emoji), the one synchronous change-notification
primitive, and the seams through which packages reach data. No Flutter, no I/O,
one dependency (`meta`).
Every other package in the workspace speaks these types, so it depends on no
workspace package (`scripts/check` enforces both).

## Types

| Type | Role |
| --- | --- |
| `ContentKey` | The one closed identity: `unicode` (the exact sequence shown or sent), `document` (opaque id), `external` (web or inline-result id). Value equality; a stable string encoding (`encoded`, `parse`, `tryParse`) for storage. |
| `ContentDescriptor` | A key plus `SemanticKind` (what it is to the user) and `MediaForm` (how it renders), and facts known before loading: animated, tintable, locked, size, thumbnail, spoken name. |
| `Collection` | `CollectionId` + `CollectionMetadata` + `CollectionContents` (`idle`, `loading`, `loaded` with `CollectionItem`s and a `PageToken`, `failed`). Sets, personal lists, search results and trending are all collections. |
| `EmojiEntry` | A base unicode key and its variants. Each variant is its own key, tagged with `EmojiModifiers` (ordered tones, gender). |
| `InlineContentRef` | A key plus the mandatory plain-text alternative, for content embedded in text. |
| `Observable`, `ValueObservable<T>`, `EventObservable<T>` | The read sides of change notification: a signal, a signal guarding a snapshot, a typed event stream. Listeners run synchronously; dedup-on-add, snapshot dispatch, silent after dispose. |
| `ObservableNotifier`, `ObservableValue<T>`, `EventNotifier<T>` | The owner sides. `batch` turns many changes into one signal; `ObservableValue` skips equal snapshots. |
| `CollectionSource`, `SearchSource` | Publish `Collection`s as immutable snapshots, with load and paging commands. Failure is a state, never an exception. |
| `RecentsStore`, `PreferenceStore` | Loaded, synchronous-read stores for picks (per `SemanticKind`, frequency then recency) and typed user choices. |
| `KeywordSource`, `KeywordPack` | Per-language search keywords, bundled or supplied by the host. |
| `GlyphSupport` | Which unicode keys the device draws, and the identity of its emoji art. Optimistic: `true` until known missing. |
| `KeyValueStore`, `StoredValue` | Namespaced, versioned string persistence; the only way logic packages reach durable storage. |
| `ContentResolver` | Batched async resolution of bare keys to descriptors. |

## Host contract

| The host provides | The host must not |
| --- | --- |
| Keys for its content. A `document` or `external` id is an opaque string, unique per piece of content. | Put a kind in a key, or build a second key for the same content. Kind lives in the descriptor. |
| Descriptors where it already knows the facts. Unrecognised kinds and forms decode through `SemanticKind.fromValue` / `MediaForm.fromValue` to `unknown`. | Store "descriptor loaded" state on a list. A bare `CollectionItem` is the unresolved case. |
| Fetch credentials and provenance, kept on its side and keyed by `ContentKey`. | Expect this package to carry credentials, file references or other fetch data. |
| Titles as data (`CollectionMetadata.title`), in the source's own language. | Rely on a collection carrying an icon or a localized label. A page maps the `CollectionId` to those. |
| One `Collection` per change. A first-load failure is `failed`; later page trouble stays `loaded` with its `nextPageToken`. | Mutate items or variants: the lists are unmodifiable copies. |
| Entries whose variant keys are the exact sequences it sends, and tags for each. | Compute a variant by appending a modifier to the base, or fold FE0F spellings into one key. Keys compare exactly. |
| Implementations of the seams it needs: sources, stores, a `ContentResolver`, a `KeyValueStore` adapter for its platform storage. Each seam's dartdoc states the contract to meet. | Reach a seam's implementation through a downcast, or let a seam throw for an expected condition. Missing data is null or an absent entry; a failed load is a `failed` state. |
| The decision that a pick counts: it calls `RecentsStore.record` on insert or send, with the `PickSource` it came from. | Record from inside a page, or record a pick made from search results. |
| One `KeyValueStore` namespace per package, and a version on every value it writes. | Share a namespace between packages, or expect the store to migrate or interpret a value. |
| Disposal: whoever creates a notifier, source or store disposes it. | Signal from a consumer's side (only the owner type can), or rely on a listener running after dispose. |
| Listeners that tolerate being called synchronously, inside the call that changed the state, and that read the owner for the new state. | Throw from a listener to stop the others (a throwing listener is reported to the zone and the rest still run), or assume a signal carries a payload (`Observable` has none; use `EventObservable`). |

## Decisions

- [Content identity and collection model](../../.scratch/package-architecture/adr-candidates/content-identity.md)
- [Data layering](../../.scratch/package-architecture/adr-candidates/data-layering.md)

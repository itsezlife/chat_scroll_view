# content_model

Pure-Dart value types that identify and group catalog content: stickers,
GIFs, custom and unicode emoji. No Flutter, no I/O, one dependency (`meta`).
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

## Host contract

| The host provides | The host must not |
| --- | --- |
| Keys for its content. A `document` or `external` id is an opaque string, unique per piece of content. | Put a kind in a key, or build a second key for the same content. Kind lives in the descriptor. |
| Descriptors where it already knows the facts. Unrecognised kinds and forms decode through `SemanticKind.fromValue` / `MediaForm.fromValue` to `unknown`. | Store "descriptor loaded" state on a list. A bare `CollectionItem` is the unresolved case. |
| Fetch credentials and provenance, kept on its side and keyed by `ContentKey`. | Expect this package to carry credentials, file references or other fetch data. |
| Titles as data (`CollectionMetadata.title`), in the source's own language. | Rely on a collection carrying an icon or a localized label. A page maps the `CollectionId` to those. |
| One `Collection` per change. A first-load failure is `failed`; later page trouble stays `loaded` with its `nextPageToken`. | Mutate items or variants: the lists are unmodifiable copies. |
| Entries whose variant keys are the exact sequences it sends, and tags for each. | Compute a variant by appending a modifier to the base, or fold FE0F spellings into one key. Keys compare exactly. |

## Decisions

- [Content identity and collection model](../../.scratch/package-architecture/adr-candidates/content-identity.md)
- [Data layering](../../.scratch/package-architecture/adr-candidates/data-layering.md)

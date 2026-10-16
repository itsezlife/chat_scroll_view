# content_model

Pure-Dart value types that identify and group catalog content (stickers,
GIFs, custom and unicode emoji) and that carry formatted text (`RichText`). No
Flutter, no I/O, one dependency (`meta`). Every other package in the workspace
speaks these types, so it depends on no workspace package (`scripts/check`
enforces both).

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

## Host contract

| The host provides | The host must not |
| --- | --- |
| Keys for its content. A `document` or `external` id is an opaque string, unique per piece of content. | Put a kind in a key, or build a second key for the same content. Kind lives in the descriptor. |
| Descriptors where it already knows the facts. Unrecognised kinds and forms decode through `SemanticKind.fromValue` / `MediaForm.fromValue` to `unknown`. | Store "descriptor loaded" state on a list. A bare `CollectionItem` is the unresolved case. |
| Fetch credentials and provenance, kept on its side and keyed by `ContentKey`. | Expect this package to carry credentials, file references or other fetch data. |
| Titles as data (`CollectionMetadata.title`), in the source's own language. | Rely on a collection carrying an icon or a localized label. A page maps the `CollectionId` to those. |
| One `Collection` per change. A first-load failure is `failed`; later page trouble stays `loaded` with its `nextPageToken`. | Mutate items or variants: the lists are unmodifiable copies. |
| Entries whose variant keys are the exact sequences it sends, and tags for each. | Compute a variant by appending a modifier to the base, or fold FE0F spellings into one key. Keys compare exactly. |
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

- [Body linkify is host-invoked](../../docs/adr/017-body-linkify-host-invoked.md)

- [Content identity and collection model](../../.scratch/package-architecture/adr-candidates/content-identity.md)
- [Data layering](../../.scratch/package-architecture/adr-candidates/data-layering.md)

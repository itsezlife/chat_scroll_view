# ADR 021: Content identity and collection model

One closed **content key** identifies a piece of catalog content. A
**content descriptor** adds what the content is and how it renders. One
**collection** type holds every list of content. All of it lives in the pure-Dart
`content_model` package.

**Status**: Accepted  
**Date**: 2026-10-16  
**Relates to**: [ADR 020](020-package-topology.md), [ADR 022](022-asset-cache-and-media-pipeline.md), [ADR 023](023-data-layering-and-persistence.md)

## Decided

| Area | Decision |
| ---- | -------- |
| Identity | One closed content key: `unicode` (the full sequence actually shown or sent), `document` (opaque document id: stickers, GIFs, custom emoji, anything document-backed), `external` (web or inline-result content with no document). Kind is not part of identity. Fetch credentials (access hash, file reference) and provenance stay on the host side, keyed by the key. |
| Descriptor | A value: key, **semantic kind** (unicode emoji, custom emoji, sticker, mask, GIF, ...), **media form** (glyph, still image, vector animation, video or animated image) and facts (animated, tintable, locked, size hint, thumbnail ref, spoken name). Semantic kind drives policy; media form drives the asset pipeline and the painter. Unknown host values fall back to a safe default. Data sources attach descriptors eagerly when they know them. A host-implemented, batched, async **content resolver** resolves bare keys (message text, recents, deep links). Loading state is derived and never stored on lists. |
| Collections | One uniform **collection**: id (set id, well-known list such as recent, faved or saved, or query or category), metadata, and contents with explicit state (`idle`, `loading`, `loaded`, `failed`) plus a page token. Sets, recents, faved, saved, search results and trending are all collections. Metadata and contents load independently. A panel section is a projection of a collection. |
| Variants | Every skin-tone, gender or multi-person variant is its own unicode key. A catalog entry links a base key to its variants. The tone preference is stored per base as the chosen variant key, with no integer tone index. Recents record the picked key. |
| Inline ref | An **inline content ref** is a content key plus a mandatory plain-text alternative. Span positions, formatting and the text container belong to the rich-text value ([ADR 026](026-composer-model.md)) and the host's body model. |
| Presentation split | Collections carry a semantic id, an optional data-provided title and an optional cover key. Icons and localized titles of built-in categories belong to pages and host presentation. |

## Why

- Telegram uses three identities per file: content (the document id), fetch (id, access hash, file reference, data center) and provenance. Kind is derived from mime type and attributes, loading state is derived, custom emoji in text are bare document ids, and inline GIF results may be external.
- The pre-redesign code modelled `unicode | document` five times (asset key, catalog leaf, emoji item, leaf meta, anonymous cell records). Adding a variant meant editing every exhaustive switch, and the document form was never constructed.
- One integer tone index cannot express the 415 two-tone sequences, and FE0F spellings fail to match when keys are folded.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Open namespaced id; kind-tagged identity | Kind can disagree with content, and an open id loses exhaustive switches |
| Bare keys only; eager descriptors only | Bare keys give no synchronous facts; eager descriptors cannot express bodies or recents that hold bare ids |
| One kind axis with media sub-variants; semantic kind only | Policy and rendering change independently |
| Separate set, personal-list and search-result types | Sections and pages would need three paths for one shape |
| Base key plus modifier parameter; variants only in the data layer | Keys must compare exactly and survive persistence |
| Key-only inline refs; defining the entity type in the identity layer | Copy, selection and accessibility need the alternative text; entities belong with text |
| Data carrying presentation hints; icons or titles inside data sources | Localization and icons are presentation concerns |

## Related

- Glossary: [Content and assets](../content/CONTEXT.md)

# Content and Assets

What a piece of catalog content is, where lists of it come from, and how it
becomes something paintable. Covers the pure-Dart `content_model` leaf, the
asset cache in `catalog_assets`, and the emoji data layer. Does not cover
panel chrome or the catalog viewport.

Decisions: [ADR 021](../adr/021-content-identity-and-collections.md),
[ADR 022](../adr/022-asset-cache-and-media-pipeline.md),
[ADR 023](../adr/023-data-layering-and-persistence.md),
[ADR 017](../adr/017-body-linkify-host-invoked.md) (entity detection),
[ADR 034](../adr/034-rich-text-wire-and-persistence.md),
[ADR 036](../adr/036-emoji-only-message-presentation.md),
[ADR 042](../adr/042-native-media-decoding.md) (native decoders).

## Language

### Identity

**Content key**:
The one canonical identity of a piece of content. Closed: `unicode` (the full sequence shown or sent), `document` (an opaque document id: stickers, GIFs, custom emoji), `external` (web or inline-result content with no document). Fetch credentials and provenance stay on the host side, keyed by the key.
_Avoid_: Kind-tagged id, emoji id, asset key, leaf identity, a second key for the same content

**Content descriptor**:
A value: content key, **semantic kind**, **media form** and facts (animated, tintable, locked, size hint, thumbnail ref, spoken name). Attached when a source knows it, resolved when it does not. Loading state is derived, never stored on lists.
_Avoid_: Metadata blob, "loaded" flag on a list

**Semantic kind**:
What the item is to the user (unicode emoji, custom emoji, sticker, mask, GIF). Drives panel and composer policy.
_Avoid_: Type, category (a category is a collection), media form

**Media form**:
How the item renders: glyph, still image, vector animation, video or animated image. Drives the asset pipeline and the painter.
_Avoid_: Semantic kind, file type, cache type

**Content resolver**:
Host-implemented, batched, async seam that resolves bare content keys (message text, recents, deep links) to descriptors.
_Avoid_: Eager descriptor lookup on every list, resolver inside the viewport

**Rich clipboard**:
The system clipboard holding two forms of one rich text: plain text any app pastes, and a rich form (HTML) a paste into the app reads back with every entity.
_Avoid_: Clipboard service, copy manager

**Clipboard text**:
What a paste reads: the clipboard's plain text, plus its rich text when the clipboard held a rich form.
_Avoid_: Clipboard data, paste payload

**Collection**:
The uniform container: id (set id, well-known list such as recent, faved or saved, or query or category), metadata and contents with explicit state (`idle`, `loading`, `loaded`, `failed`) and a page token. Sets, recents, faved, saved, search results and trending are all collections.
_Avoid_: Set, pack, list type per source, search-result type

**Emoji variant**:
A skin-tone, gender or multi-person form of an emoji. Each variant is its own unicode key; a catalog entry links a **base** key to its variants, and the tone preference is stored per base as the chosen variant key.
_Avoid_: Tone index, base key plus modifier parameter, folding FE0F spellings into one key

**Inline content ref**:
A content key plus a mandatory plain-text alternative, embedded in message text or the composer.
_Avoid_: Key-only ref, placeholder character

**Rich text**:
A neutral value: plain text plus entities (offset, length, kind). Entity kinds include inline content ref, formatting runs, link, **mention**, **username**, **hashtag**, quote, code block and, opt-in, list item. Flat text with ranged entities is the permanent model: line-widening kinds are entities, not nodes. Its markdown spelling is the one wire and storage form ([ADR 034](../adr/034-rich-text-wire-and-persistence.md)). Hosts map it to their body model.
_Avoid_: Parallel offsets beside a markdown body, a text model owned by the composer package, a document tree

**Mention**:
An entity naming a user the host has resolved: carries the user id, is atomic for editing, and is verified by the host before send. Spelled `[@name](mention:id)`. Detection never produces one.
_Avoid_: A typed `@name` (that is a **username**), an unverified id

**Username**:
An entity for a detected or typed `@name` with no id: plain, non-atomic text the host resolves on tap. Spelled `[@name](username:name)`. Distinct from a **mention** because atomicity and trust differ.
_Avoid_: Mention with a resolved flag, `mention:<name>`

**Hashtag**:
An entity for a `#tag` (a hash plus a non-digit plus word characters). Spelled `[#tag](hashtag:tag)`, painted like a mention, with its own inline hit.
_Avoid_: Cashtag, a tag with an id

**Entity detection**:
A pure transform over rich text that adds link, **username** and **hashtag** entities where text has the shape of one (`EntityDetection.apply`). Host-invoked at send and as a cached receive-time fallback for bodies with no link-class entity; never on paint and never in the composer while typing. One implementation serves the composer's send path, the host's receive path and any server port. Replaces the former body linkify.
_Avoid_: Autolink on paint, a markdown-string rewrite, detection inside the viewport, bot-command or phone detection as kinds

**Typed markdown**:
A pure transform over rich text that turns the markers a user typed (`` `code` ``, a triple-backtick block, `**bold**`, `__italic__`, `~~strike~~`, `||spoiler||`) into the matching entities and drops the markers (`TypedMarkdown.apply`). Host-invoked at send, before **entity detection**, never on paint or per keystroke; the reference client's rules.
_Avoid_: Live markdown conversion in the composer, a markdown-string rewrite, an underline or quote marker

**Detection policy**:
The caller-owned choice of which families **entity detection** applies (urls, usernames, hashtags) and which URL schemes count. The exclusion zones (code, code blocks, existing links and mentions, inline content, atoms) are fixed rules, not policy.
_Avoid_: A universal URL definition in the package, sealed presets when families must combine

**Emoji-only text**:
The result of classifying rich text as only emoji: the ordered items (a unicode sequence or a document key) and line breaks, or nothing. The rule: emoji graphemes, whitespace and newlines, with only inline content with a document key allowed as an entity. The host calls it and adds the facts it alone has before choosing an **emoji-only body** ([ADR 036](../adr/036-emoji-only-message-presentation.md)).
_Avoid_: A regular expression in the viewport, a count cap, classification per mount

**Presentation split**:
Collections carry a semantic id, an optional data-provided title and an optional cover key. Icons and localized titles of built-in categories belong to pages and host presentation.
_Avoid_: Icons or localized titles inside data sources

### Asset pipeline

**Asset cache**:
The host-created, app-wide cache of paintable assets, provided through a scope. Entries are identified by content key plus **asset spec**.
_Avoid_: Global catalog asset cache, static singleton, per-surface cache, panel-only drawable map

**Asset spec**:
The decode-affecting part of a request: pixel size at DPR, template or tint decode mode, first-frame-only or full.
_Avoid_: Surface class, `keyboard` / `messages` enum

**Asset profile**:
Per-attach behaviour: animate, loop, autoplay first frame, corner radius, fit, half frame rate. Does not split cache entries.
_Avoid_: Putting behaviour into the entry identity

**Half frame rate**:
A playing asset that shows only every second frame of a source above 30 fps (`AssetProfile.halfFrameRate`): a 60 fps sticker at 30. Set by the presets of small cells (`AssetPresets.keyboardCell` up to 90 logical px, which also caps the decode at 160 px), never by the chat's presets. It changes the frames a paintable asks for, so a surface that repaints every clock frame still renders and posts half of them; the playback policy's fps cap only spaces a binding's own repaints.
_Avoid_: A second clock, a per-surface timer, skipping repaints to save frames

**Asset paintable**:
What a binding yields. Draws itself into a canvas rect. May expose an optional sprite (atlas page plus source rectangle) for consumers that batch; the unicode glyph form is a baked sprite ([Panel Catalog glossary](../panel-catalog/CONTEXT.md): Glyph atlas page, Bake, Baked glyph).
_Avoid_: Drawable, `ui.Image` per tick, a downcast to find the sprite

**Staged readiness**:
`none`, `placeholder`, `firstFrame`, `full`, each with `isFinal`. No visible failed stage: a failed fetch or decode leaves the placeholder showing. Retry happens on re-attach, on the host's connectivity-restored signal, or through `retry()`.
_Avoid_: Failed state, error stand-in, three-state readiness

**Stand-in**:
What a surface draws for content that is not there yet: the scope's placeholder paintable (a circle for a glyph, the whole rectangle in one quiet colour for any other media, `RectPlaceholder`), a placeholder an embed brings (`SoftPlaceholder`, a quiet rounded square for a sticker), or the thumbnail. The rectangle has the size and proportion of the final cell from the first frame, so a thumbnail that arrives moves nothing; a binding rounds its corners with the surface's `AssetProfile.cornerRadius`. A bitmap thumbnail stays fully opaque under content that fades in and is released when the content is opaque (the binding keeps it for that: `paintStandIn` / `releaseStandIn`); a silhouette stand-in fades out as the content rises.
_Avoid_: Fading a bitmap thumbnail out while the content fades in, a failed stand-in, a circle for media

**Asset fit**:
How content of one proportion fills a rectangle of another, chosen per surface (`AssetProfile.fit`): `contain` shows the whole picture with bars, `cover` fills the rectangle and crops the overflow, centre-anchored. A GIF in a grid cell covers it (the reference client's `isAspectFit` is false there); a sticker is contained. Content and its thumbnail follow the same fit, so a thumbnail replaced by content does not change its crop.
_Avoid_: Letterboxed GIF in a grid cell, a clip or a second draw for the crop

**Mini-thumbnail**:
The small preview still of a piece of content (`ContentDescriptor.thumbnail`), decoded to at most 40 pixels on its longer side and blurred once at decode (`MiniThumbnail.decode`, the reference client's stripped photo with its radius 3 stack blur), then stretched over the box by the surface. A host that has no preview for a content gives none and the cell keeps its placeholder.
_Avoid_: A blur per frame, a blur hash, decoding the preview at full size

**Radial progress**:
The reference client's loading indicator for media (`RadialProgress`): a translucent dark disc with a turning white arc and a cross, painted by the surface over the thumbnail while the content loads. A function of the frame time of the surface's own paint pass; the cache reports stages and no fractions, so the arc sweeps a fixed quarter.
_Avoid_: A controller per cell, a progress percentage the cache does not have

**Content fetcher**:
Host seam from descriptor to bytes or file. Owns network, provenance refresh and the disk tier.
_Avoid_: Loader that also decodes

**Decoder**:
Adapter per media form: fetched data plus spec to paintable with stages.
_Avoid_: Fetching inside a decoder

**Playback clock**:
The core's single shared animation ticker, with per-binding gating and global pause layers. A pause freezes and a resume continues where the animation stopped.
_Avoid_: Per-surface ticker, self-scheduling paintable

**Playback activity**:
The one host-facing seam that turns the app's lifecycle, the host's low-power and reduced-motion signals and the overlays over the chat into pause layers of the playback clock. It owns those layers; the host owns `routeMoving` and `fastScroll`.
_Avoid_: A pause flag on a widget, feeding app lifecycle into a row's `isActive`

**Glyph sprite source**:
The one narrow seam through which the asset cache reaches a glyph atlas: the sprite of a glyph, a hold on its page, a page listener, and whether a sprite is on its way (`waitsForSprite`; a glyph nothing waits for is drawn as text). Several atlases are one source through a layered source: the background bake first, glyphs that joined later after it. The atlas implements it and the host registers it with the scope. Bindings hold the page from attach to detach.
_Avoid_: The cache creating or owning atlases, `panel_catalog` importing atlas types

**Dynamic page**:
A shared page of animation frames in the asset cache. An animated asset owns a **slot** on it; a worker renders every active slot in one batch call per tick and the pool uploads one image per page that changed. The paintable exposes a sprite on it. It is a separate pool and budget from the baked glyph pages ([ADR 022](../adr/022-asset-cache-and-media-pipeline.md) amendment, [ADR 042](../adr/042-native-media-decoding.md)).
_Avoid_: A `ui.Image` per animated asset, mixing frame slots into glyph pages

**Renderer seam**:
The engine-agnostic seam in `catalog_assets`: given slots, frame times and sizes, write premultiplied pixels into page memory. A native decoder adapter implements it; the pool, slot allocator and residency stay in the core, which holds no native code.
_Avoid_: The pool calling an engine, a decoder owning pages

**Frame cache**:
Compressed rendered frames of an animation, keyed by content, display size and engine version, replayed instead of re-rendering. An animation is two fills, its even frames and its odd frames, each complete (and written) on its own, so a playback at half rate, which asks only for the even ones, completes one. Skipped above 512 x 512 display size; disk and memory tiers on native, memory only on web.
_Avoid_: Keying by source size or by frame step, a cache that is a visible stage

**Native binding**:
The leaf package that owns the native library, its build hook, its `dart:ffi` or web-worker bindings and a guarded load probe. A decoder adapter depends on it; a failed probe means the decoder is never registered.
_Avoid_: FFI calls in an adapter or the core, retrying a library that failed to load

**Content embed**:
The `catalog_assets` adapter implementing an inline embed over an asset binding with the `messages` preset.
_Avoid_: `WidgetSpan` or `ImageProvider` embeds

### Data layer

**Catalog structure**:
Locale-independent emoji structure: order, groups, base to variants. One generated asset.
_Avoid_: Per-locale tables, const locale files

**Keyword pack**:
Per-language keyword data (with spoken names), bundled as the offline baseline or supplied by the host through the **keyword source** seam.
_Avoid_: Keywords compiled into the binary for every locale

**Collection source** / **Search source**:
Seams producing collections and paged search-result collections.
_Avoid_: A single content data source, facades per kind

**Recents store**:
Host-driven `record(key, {source})`. Keeps count and last-used time, orders by frequency then recency, default cap 48. Search picks do not record. One list per kind recorded under; the kind names the page's list, not each key's content (the emoji page files unicode and custom emoji in one list).
_Avoid_: Pure most-recently-used, recording inside the page on tap

**Preference store**:
Typed preferences, such as the variant chosen per base.
_Avoid_: Integer tone index

**Glyph support**:
Seam answering which unicode keys the device can render. The default adapter is a pure-Dart, paced probe. Its art version signal is a pixel fingerprint, not a native call.
_Avoid_: Native glyph-support plugin, OS version string as the art signal

**Key-value store**:
Async, namespaced, versioned persistence seam. Adapters are host-chosen; factories return loaded stores.
_Avoid_: `shared_preferences` in logic packages, unloaded stores

**Listenable**:
The change-notification primitive of the pure-Dart packages is [`Listenable` / `ValueListenable` from `package:listen`](https://pub.dev/documentation/listen/latest/listen/Listenable-class.html) (owners: `ChangeNotifier`, `ValueNotifier`); this repository defines none of its own. Seams expose it; typed events (things that happen, not state that is) are synchronous broadcast `Stream`s. The host sets `Listenable.onError`; the packages never do ([ADR 023](../adr/023-data-layering-and-persistence.md), amendment).
_Avoid_: A repository-owned observable type, Flutter's `Listenable` in the leaf, hand-rolled listener lists, assuming a listener is deduplicated or that a disposed notifier is silent

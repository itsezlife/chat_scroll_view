# Content and Assets

What a piece of catalog content is, where lists of it come from, and how it
becomes something paintable. Covers the pure-Dart `content_model` leaf, the
asset cache (mpx's `mpx_core`, reached through `content_assets` and `glyph_atlas`), and the emoji data layer. Does not cover
panel chrome or the catalog viewport.

Decisions: [ADR 021](../adr/021-content-identity-and-collections.md),
[ADR 022](../adr/022-asset-cache-and-media-pipeline.md),
[ADR 023](../adr/023-data-layering-and-persistence.md),
[ADR 017](../adr/017-body-linkify-host-invoked.md) (entity detection),
[ADR 034](../adr/034-rich-text-wire-and-persistence.md),
[ADR 036](../adr/036-emoji-only-message-presentation.md),
[ADR 042](../adr/042-native-media-decoding.md) (native decoders),
[ADR 044](../adr/044-content-library-packs-and-preview.md) (content library, packs, preview, pack sheets).

## Language

### Identity

**Content key**:
The one canonical identity of a piece of content. Closed: `unicode` (the full sequence shown or sent), `document` (an opaque document id: stickers, GIFs, custom emoji), `external` (web or inline-result content with no document). Fetch credentials and provenance stay on the host side, keyed by the key.
_Avoid_: Kind-tagged id, emoji id, asset key, leaf identity, a second key for the same content

**Content descriptor**:
A value: content key, **semantic kind**, **media form** and facts (animated, tintable, locked, size hint, byte size, duration, streamable, thumbnail ref, **preview**, spoken name). Attached when a source knows it, resolved when it does not. Loading state is derived, never stored on lists.
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
_Avoid_: Set, pack (a **pack** is the published unit a set collection lists), list type per source, search-result type

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
`none`, `preview`, `placeholder`, `firstFrame`, `full`, each with `isFinal`. A leaf that fails keeps the best picture stage it reached (preview, thumbnail or first frame); there is no failed picture. A surface that shows a **status control** turns it back to download, which is the retry. A leaf without a control (glyphs, panel cells, embeds in text) shows nothing more. Readiness has no failure stage: the **transfer** is the only failure a surface can see, and only through the control. Retry also happens on re-attach, on the host's connectivity-restored signal, or through `retry()`.
_Avoid_: Failed state, error stand-in, a failed picture, three-state readiness

**Stand-in**:
What a surface draws for content that is not there yet: the scope's placeholder paintable (a circle for a glyph; for any other media one that paints nothing, `ClearPlaceholder`, so the surface behind shows through), a placeholder a surface brings (`SoftPlaceholder`, a quiet rounded square for a sticker embed; a tinted `RectPlaceholder`), the **preview**, or the **thumbnail**. The cell has the size and proportion of the final content from the first frame, so a stand-in that arrives moves nothing; a binding rounds its corners with the surface's `AssetProfile.cornerRadius`. Each rise between stages is a fade or a swap set per platform (`MediaStageStyle`). A raster stand-in stays fully opaque under content that fades in and is released when the content is opaque (the binding keeps it for that: `paintStandIn` / `releaseStandIn`); an outline preview, or any stand-in under content that may be transparent, fades out as the content rises. A surface's own placeholder may outrank the stand-in stages up to a stage it names (`placeholderUntil`).
_Avoid_: A light flat box before content, fading a raster thumbnail out while the content fades in, a failed stand-in, a circle for media

**Asset fit**:
How content of one proportion fills a rectangle of another, chosen per surface (`AssetProfile.fit`): `contain` shows the whole picture with bars, `cover` fills the rectangle and crops the overflow, centre-anchored. A GIF in a grid cell covers it (the reference client's `isAspectFit` is false there); a sticker is contained. Content and its thumbnail follow the same fit, so a thumbnail replaced by content does not change its crop.
_Avoid_: Letterboxed GIF in a grid cell, a clip or a second draw for the crop

**Preview**:
A stand-in drawn from bytes known without fetching the content or its thumbnail (`ContentDescriptor.preview`, stage `preview`): a mini-thumbnail, a tiny raster of a few dozen pixels blurred once at decode with the platform's blur, or an outline, the vector shape of a sticker or emoji filled with the surface's quiet colour (and a shimmer where the platform has one). The data source expands any wire form (a header-stripped image, a compressed path) before it builds the descriptor.
_Avoid_: A blur per frame, a blur hash, decoding the preview at full size, a wire-format codec in the cache

**Derived preview**:
A preview the cache made from the content's first drawable frame (at most 40 px, stored unblurred under the bytes store's `previews` quota) for content whose descriptor carries none, so later shows of it, in this launch or the next, draw it in the attach frame.
_Avoid_: Deriving per surface, storing it blurred

**Thumbnail**:
The fetched stand-in of a piece of content (`ContentDescriptor.thumbnail`, stage `placeholder`), blurred at decode when its long edge is below the platform's threshold, then stretched over the box by the surface. A host that has no preview for a content gives none; the cache derives one from the first load and the cell is clear until then.
_Avoid_: A blur per frame, decoding the thumbnail at full size

**Transfer**:
The download state of an entry's content as a surface shows it (`AssetBinding.transfer`): `none` (cached, final, or not asked for), `waiting` (known missing, no byte yet), `receiving(received, total)` (the total falls back to the descriptor's byte size), `awaitingUser(total)` (the policy held it back, or the user cancelled it) and `failed(kind, received, total)`. `download()` fetches now; `cancelDownload()` stops the content fetch, keeps the stages, and is remembered per key for the session.
_Avoid_: A progress fraction without bytes, a failed stage in readiness

**Auto-download**:
Whether an attached entry's content is fetched without a user action: the host's policy answers `now`, `prefix` (a playable head only) or `manual` per descriptor and **download context**. The composition root's default weighs the media kind, the byte size and the device's network class (unmetered, metered, roaming) with each platform's reference limits; a sticker always downloads, a clip of unknown size waits for the user.
_Avoid_: Auto-download rules in the cache, one rule for every conversation

**Download context**:
The opaque class of the surface an attach comes from (`AutoDownloadContext`: private chats, groups, channels, or the host's own), which the auto-download policy uses only as a key. An entry downloads when any attached surface's context allows it; the context never enters the cache key.
_Avoid_: A cache entry per context, a context the cache interprets

**Status control**:
The round control over media (`MediaStatusControl`): a disc, a progress arc and an icon (download, cancel, play, pause), or an indeterminate spinner, driven by the transfer. Tapping it downloads, cancels or plays. A surface asks for it per view (`MediaStatusMode`: none, a bare arc, the control, a compact one for streamable video); its style is per platform with a scope override, and a host may replace it.
_Avoid_: A retry button, an error glyph, a control per surface kind

**Media badge**:
The small label over media (`MediaBadge`): the duration, or "GIF", and while downloading "received / total"; its text and colours come from the host's theme through the style scope.
_Avoid_: Sizes formatted by each surface

**Radial progress**:
The bare download arc over media (`MediaStatusMode.arc` of the status control, and the catalogue viewport's GIF leaves with `RadialProgress`): a translucent dark disc with a turning white arc that follows the transfer's fraction. It shows only while the transfer is active (waiting or receiving) and is gone on failure: a surface with only an arc has no retry to offer.
_Avoid_: A controller per cell, an arc kept over a failed download

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
The engine-agnostic seam in `mpx_core`: given slots, frame times and sizes, write premultiplied pixels into page memory. A native decoder adapter implements it; the pool, slot allocator and residency stay in the core, which holds no native code.
_Avoid_: The pool calling an engine, a decoder owning pages

**Frame cache**:
Compressed rendered frames of an animation, keyed by content, display size and engine version, replayed instead of re-rendering. An animation is two fills, its even frames and its odd frames, each complete (and written) on its own, so a playback at half rate, which asks only for the even ones, completes one. Skipped above 512 x 512 display size; disk and memory tiers on native, memory only on web.
_Avoid_: Keying by source size or by frame step, a cache that is a visible stage

**Native binding**:
The leaf package that owns the native library, its build hook, its `dart:ffi` or web-worker bindings and a guarded load probe. A decoder adapter depends on it; a failed probe means the decoder is never registered.
_Avoid_: FFI calls in an adapter or the core, retrying a library that failed to load

**Content embed**:
The `content_assets` adapter implementing an inline embed over an asset binding with the `messages` preset.
_Avoid_: `WidgetSpan` or `ImageProvider` embeds

### Library and packs

**Pack**:
A published set of stickers, masks or custom emoji, identified by an opaque pack id: kind, title, items in order, cover, official or not. Its listing is a set **collection**.
_Avoid_: Sticker set (in prose), collection (for the published unit), album

**Pack reference**:
The pack id a **content descriptor** names for the content it describes, or none. Not identity: credentials of the pack stay on the host.
_Avoid_: Set id inside the content key, a pack per collection source

**Pack source**:
Seam answering a pack by id: found, not found or failed, with what is known now readable without loading. Keeps every pack it found, installed or only seen, and merges concurrent requests for one pack.
_Avoid_: Pack repository, pack resolver (a resolver answers descriptors)

**Content library**:
The user's own lists: recent stickers, favourite stickers, saved GIFs, and installed and archived packs per kind in the user's order. Changed only through **library edits**, local first.
_Avoid_: Favourites store, stickers manager, a store per list

**Favourite sticker**:
A sticker the user marked to keep at hand. Most recently marked first, up to the host's limit; marking one more pushes out the oldest.
_Avoid_: Faved (in prose), starred

**Saved GIF**:
A GIF in the user's saved list, which is also the GIF recents: sending a GIF saves it to the front. Most recent first, up to the host's limit.
_Avoid_: Recent GIF as a list of its own, GIF favourite

**Install state**:
Whether a pack is installed, archived or not installed: a fact of the **content library**, never of the pack.
_Avoid_: An installed flag on the pack value

**Library edit**:
One change to the **content library** as a value: add or remove a recent sticker, favourite or unfavourite a sticker, save or unsave a GIF, install, archive or remove a pack, reorder packs.
_Avoid_: Library command per verb, mutation

**Undo window**:
The time an applied **library edit** is shown but not yet committed, so it can be taken back; edits commit in the order they were applied.
_Avoid_: Delayed request, pending flag on a list

**Content preview**:
The enlarged sticker, GIF or custom emoji shown while a cell is held, with its action menu. Never for a unicode emoji.
_Avoid_: Peek, popup, zoom

**Pack sheet**:
The surface that shows one pack (or several emoji packs) with its grid and its add or remove button; a bottom sheet on touch, a centred box under a pointer.
_Avoid_: Stickers alert, pack dialog

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
Host-driven `record(key, {source})`. Keeps count and last-used time, orders by frequency then recency, default cap 48. Search picks do not record. One list per kind recorded under; the kind names the page's list, not each key's content (the emoji page files unicode and custom emoji in one list). Holds the emoji recents; sticker and GIF recents are **content library** lists.
_Avoid_: Most-recently-used order for emoji, recording inside the page on tap

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

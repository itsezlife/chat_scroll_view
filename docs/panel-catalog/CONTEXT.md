# Panel Catalog Viewport

Scrollable catalog body inside the keyboard-replacement panel (emoji, stickers,
GIFs). Owns recycle, cell paint, and near/far section navigation including
stitch. Does not own panel chrome or message-attachment media.

## Language

### Ownership

**Panel Catalog Viewport**:
The scrollable catalog body: sections, rows/cells, recycle, and near/far jumps with stitch.
_Avoid_: Media Grid, EmojiEngine, Chat Scroll Viewport, Attachment Grid

**Catalog shell**:
Host chrome around the viewport — category strip, search, type tabs, skin-tone picker, and data-source wiring.
_Avoid_: Putting strip/search lifecycle inside the viewport

### Navigation

**Extent scroll**:
Scroll state is an absolute content offset against a known (or estimated) catalog content height.
_Avoid_: Anchor origin, message-id fan-out, Chat Scroll position model

**Near-path scroll**:
Continuous smooth scroll when the section target is already attached or within the far-path distance gate (Telegram `LinearSmoothScrollerCustom`).
_Avoid_: Always stitch, always animateTo across the full catalog

**Far-path scroll**:
When the target is not attached and farther than the distance gate (or animations are disabled at the product flag). **Action is stitch**, not a bare content-offset jump (Telegram `RecyclerAnimationScrollHelper.scrollToPosition(..., smooth=true)`).
_Avoid_: Naked `jumpTo` as the far-path UX, animateTo through the entire gap

**Far-path distance gate**:
Telegram emoji/stickers rule: target view not currently attached AND `|targetIndex - firstVisibleIndex| > spanCount * 9`. Below that (or if the target row is already attached), use near-path smooth scroll.
_Avoid_: Pixel-distance gates, treating “far” as synonymous with jumpTo

**Stitch**:
A continuity illusion for far-path catalog jumps: capture visible outgoing rows, teleport the content offset to the target, then dual-translate outgoing and incoming paint so the jump reads as one scroll.
_Avoid_: Crossfade, whole-viewport fade, sharing Chat Scroll load-gate / shimmer-stitch rules by default

**Outgoing strip** / **Incoming band**:
Same roles as in Chat Scroll: capture-time rows sliding out; destination rows sliding in under one animation factor.
_Avoid_: Bitmap snapshot of the old viewport

### Leaves and data

**Paint leaf**:
A recycled catalog cell drawn by the viewport without a per-cell widget Element/State tree.
_Avoid_: EmojiGlyphCell-per-slot, StatefulWidget cell as the default path

**Viewport-owned hit-test**:
Pointer mapping to a leaf id inside the catalog viewport: press scale in paint, tap/long-press callbacks to the catalog shell.
_Avoid_: Per-cell GestureDetector/InkWell as the default, temporary overlay widgets for every press

**Leaf presentation**:
How one catalog cell appears: ready content, a kind-specific loading placeholder, or failed.
_Avoid_: One generic “shimmer” for every leaf kind, ChatMessageStatus, Absent, navigation load-gate for ordinary pack/section jumps

**Circle placeholder**:
Loading stand-in for standard emoji bitmap leaves: a solid circle (~0.4 × glyph bounds) until the page bitmap is ready (Telegram `Emoji.SimpleEmojiDrawable`).
_Avoid_: Moving gradient wash, sticker-shaped shimmer for unicode cells

**Thumb-first placeholder**:
Loading stand-in for document-backed animated/custom emoji: static/SVG thumb via the image pipeline until media is ready (Telegram `AnimatedEmojiDrawable` + `ImageReceiver`).
_Avoid_: Circle placeholder for animated leaves when a thumb exists

**Shaped loading wash**:
Loading stand-in for sticker leaves: sticker SVG silhouette with a moving gradient (Telegram `LoadingStickerDrawable`).
_Avoid_: Using this as the default for unicode emoji cells

**Catalog data source**:
Authoritative catalog contents and per-leaf readiness for one panel surface. Notifies the viewport when either changes. Owns catalog fetch orchestration; does not own the global asset bytes alone.
_Avoid_: Streams as the integration contract, fetch inside the viewport, subclassing ChatDataSource, private per-viewport drawable maps as the long-term design

**Global catalog asset cache**:
Process-wide cache for emoji / sticker / GIF document thumbs and media, shared by the Panel Catalog Viewport and by Chat Scroll (inline animated emoji, sticker messages, etc.). Viewport and chat cells only bind and paint; they do not each keep a private decode store.
_Avoid_: Per-panel-only drawable map as the source of truth, duplicating Telegram `AnimatedEmojiDrawable` caches per surface

**Document-backed leaf**:
A catalog cell identified by a document (animated/custom emoji, sticker) rather than only a unicode glyph. v1 prepares identity and placeholder modes for these even if full media decode ships later.
_Avoid_: Treating every cell as a glyph string forever

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
Telegram emoji/stickers rule: target view not currently attached AND `|targetFlatIndex - firstVisibleFlatIndex| > spanCount * 9`. Below that (or if the target header row is already visible), use near-path smooth scroll. Flat-row index counts one slot per section header plus one per leaf row (not per cell).
_Avoid_: Pixel-distance gates, treating “far” as synonymous with jumpTo, per-cell index for the gate

**Section jump**:
Programmatic navigation to a catalog section via [PanelCatalogController.jumpToSection]. Lands the section header under the viewport's reserved top inset ([PanelCatalogViewport.padding.top]). Path selection uses near-path smooth scroll or far-path stitch per the distance gate.
_Avoid_: Bare [jumpTo] as the only category navigation API from the shell, flat list indices where section indices are required

**Strip inset landing**:
Scroll offset `headerTop − padding.top` so the section title band aligns with the reserved top inset band. Content paints at `viewportY = contentY − offset`.
_Avoid_: Landing at offset `headerTop` when [padding.top] reserves strip space

**Section jump active**:
[PanelCatalogController.isSectionJumpActive] is `true` while a programmatic section jump animation owns scroll motion. Hosts suppress category-strip scroll sync during this window.
_Avoid_: Inferring programmatic motion from offset deltas alone, re-entrant strip updates during near-path animate

**Flat-row index**:
Adapter-style index for section-jump gating: each section contributes one index for its header, then one index per leaf row at [spanCount] columns. Matches Telegram flat list / SuperSliverList header+row lists.
_Avoid_: Per-cell index for the distance gate, message-id indices

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
Pointer mapping to a [CatalogLeaf] inside the catalog viewport: press scale in paint, tap and long-press callbacks to the catalog shell. Recognizers live on the viewport render object — not on per-cell widgets.
_Avoid_: Per-cell GestureDetector/InkWell as the default, temporary overlay widgets for every press

**Leaf tap callback**:
Shell hook fired when the user completes a tap on a leaf. Receives [CatalogLeaf] identity only. Header bands and padding are silent (no synthetic leaf). Null on the viewport disables tap recognition; scroll drag still works.
_Avoid_: Per-cell onTap widgets, inferring leaf identity from paint coordinates in the shell

**Leaf long-press callback**:
Shell hooks for a long-press session on a leaf: start (with gesture details for anchor placement), move while the session is live, end on lift. All three are wired through [PanelCatalogViewport] or none — null start disables the long-press recognizer entirely. The viewport forwards [CatalogLeaf] identity; it does **not** own picker UI, clear-recents dialogs, or variant/tone policy.
_Avoid_: Mounting LongPressGestureRecognizer on each cell, wiring move/end without start (registers a recognizer that cancels tap)

**Long-press eligibility**:
Optional host predicate ([PanelCatalogViewport.leafLongPressEligible]) evaluated on pointer-down. When it returns false for a leaf, the viewport does **not** register a long-press recognizer for that pointer — the leaf stays tap-only. Use when most leaves have no long-press action so plain glyphs are not cancelled after the long-press timeout (~500ms). When the predicate is null, every leaf is eligible whenever start is wired.
_Avoid_: Registering long-press on all cells and no-oping in the callback (loses tap on ineligible leaves)

**Fling-cancel leaf suppress**:
When the user touches down while a ballistic fling is coasting, the viewport cancels the coast and suppresses leaf tap and long-press for **that pointer only** so stopping scroll does not insert or open a picker. The next deliberate tap/long-press on a still leaf works normally.
_Avoid_: Per-cell fling guards, treating fling-cancel as a global “gestures off” mode

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

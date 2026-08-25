# Panel Catalog Viewport

Scrollable catalog body inside the keyboard-replacement panel (emoji, stickers,
GIFs). Owns recycle, cell paint, and near/far section navigation including
stitch. Does not own panel chrome or message-attachment media.

## Language

### Ownership

**Panel Catalog Viewport**:
The scrollable catalog body: sections, rows/cells, recycle, and near/far jumps with stitch.
_Avoid_: Media Grid, EmojiEngine, Chat Scroll Viewport, Attachment Grid

**KeyboardPanel**:
Keyboard-replacement panel chrome around one or more catalog pages — type tabs, search overlay, open/close motion, bottom bar, and data-source wiring for the active page. Does not own catalog scroll extent or cell paint. Public API name in chat chrome (replaces EmojiPanel as the domain term). Related chrome types use the `KeyboardPanel*` prefix (`Allow`, `Tab`, `Labels`, `Callbacks`, bottom bar, store, …). Prefs live on [KeyboardPanelStore] under `keyboard_panel_*` keys (no legacy dual-read). Unicode page / glyph / `emoji_data` keep the `Emoji*` prefix.
_Avoid_: CatalogPanel (mirrors Panel Catalog), Catalog shell, EmojiPanel (as the lasting domain name), renaming emoji catalog page types to Keyboard*, putting strip/search lifecycle inside the viewport

**KeyboardPanelController**:
Host-owned **source of truth** for KeyboardPanel chrome intents and presented desired state (open, tab, search, …). Constructed with bottom-inset arbitration and [KeyboardPanelStore]; `open` / `close` claim or release the inset slot themselves so the host does not dual-call `openPanel` + panel open. Commands always commit on the controller and notify typed listeners even when no KeyboardPanel is attached; the bound panel **projects** that state into motion/layout. Does not own inset math, composer text, or insert/backspace effects — those stay as widget/host callbacks. Distinct from PanelCatalogController (extent scroll on one catalog page). Host passes the controller into KeyboardPanel; chrome MUST NOT require GlobalKey on State. Observability uses typed listeners (and optional sealed panel events) with dedup-on-add, snapshot dispatch, and silent no-ops after dispose — not ChangeNotifier and not app-layer StateController. Widget-level declarative `open:` is not the lasting API.
_Avoid_: Driving chrome via GlobalKey on State, command-only silent no-op while unbound as the primary model, merging inset math into this controller, host dual-calling inset open plus panel open, putting insert/backspace on the controller, renaming PanelCatalogController to match, duplicating open state only in widget fields, blanket ChangeNotifier for host rebuilds

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
Telegram emoji rule (`EmojiView.scrollEmojisToPosition`): target view not currently attached AND `|adapterPos − firstVisible| > spanCount * 9` in **per-cell** adapter space. In flat-row index (one slot per section header + one per leaf row) that is `|targetFlatIndex − firstVisibleFlatIndex| > [kFarPathDistanceGateFactor]` (= 9). Below that (or if the target header row is already visible), use near-path smooth scroll.
_Avoid_: Multiplying the flat-row gate by spanCount again (over-widens near path), pixel-distance gates, treating “far” as synonymous with jumpTo, per-cell index for the gate when the catalog already uses flat rows

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
Pointer mapping to a [CatalogLeaf] inside the catalog viewport: press scale in paint, tap and long-press callbacks to KeyboardPanel. Recognizers live on the viewport render object — not on per-cell widgets.
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

**Leaf press chrome**:
Paint feedback on pointer-down: glyph scale (`0.8 + 0.2 × (1 − progress)`) plus list-selector highlight on the **full cell rect**. Tokens live in **Panel catalog theme** ([PanelCatalogThemeData] via [PanelCatalogTheme]).
_Avoid_: Per-cell Material/InkWell as the default, prop-drilling colors onto [PanelCatalogViewport]

**Panel catalog theme**:
Package-owned inherited paint tokens for the viewport: placeholder fill, list-selector press highlight, section header color, stand-in corner radius, document ready-path stub fill, density-scaled press-selector corner. [PanelCatalogTheme] scopes [PanelCatalogThemeData]; [PanelCatalogThemeData.lerp] supports animated palette transitions.
_Avoid_: [ThemeData.extensions] for catalog paint, per-viewport color ctor args

**Leaf presentation**:
How one catalog cell appears: ready content, a kind-specific loading placeholder, or failed.
_Avoid_: One generic “shimmer” for every leaf kind, ChatMessageStatus, Absent, navigation load-gate for ordinary pack/section jumps

**Circle placeholder**:
Reserved stand-in for async bitmap-page unicode leaves (solid circle ~0.4 × glyph bounds). Current unicode cells paint from paragraph cache and resolve unbound/loading to content — they MUST NOT flash this circle across pager keep-alive gaps.
_Avoid_: Using circle as the default for paragraph-painted unicode, moving gradient wash, sticker-shaped shimmer for unicode cells

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
Process-wide cache for emoji / sticker / GIF document thumbs and media, shared by the Panel Catalog Viewport and by Chat Scroll (inline animated emoji, sticker messages, etc.). Viewport and chat cells only bind and paint; they do not each keep a private decode store. Ready/failed entries survive the last surface detach so pager keep-alive leave/return does not flash loading; [isRetained] tracks live binds only.
_Avoid_: Per-panel-only drawable map as the source of truth, evicting settled readiness on every detach, duplicating Telegram `AnimatedEmojiDrawable` caches per surface

**Document-backed leaf**:
A catalog cell identified by a document (animated/custom emoji, sticker) rather than only a unicode glyph. v1 prepares identity and placeholder modes for these even if full media decode ships later.
_Avoid_: Treating every cell as a glyph string forever

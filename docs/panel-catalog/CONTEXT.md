# Panel Catalog Viewport

Scrollable catalog body inside the keyboard-replacement panel (emoji, stickers,
GIFs). Owns recycle, cell paint, and near/far section navigation including
stitch. Does not own panel chrome or message-attachment media.

## Language

### Ownership

**Panel Catalog Viewport**:
The scrollable catalog body: sections, rows/cells, recycle, and near/far jumps with stitch.
_Avoid_: Media Grid, EmojiEngine, Chat Scroll Viewport, Attachment Grid

**Panel shell** and **Panel presentation**:
The chrome around the viewport (tabs, search, bottom bar, open and close, where the panel appears) is not part of this context. See the [Chat Chrome glossary](../chrome/CONTEXT.md).
_Avoid_: Putting strip or search lifecycle inside the viewport

### Navigation

**Extent scroll**:
Scroll state is an absolute content offset against a known (or estimated) catalog content height.
_Avoid_: Anchor origin, message-id fan-out, Chat Scroll position model

**Near-path scroll**:
Continuous smooth scroll when the section target is already attached or within the far-path distance gate.
_Avoid_: Always stitch, always animateTo across the full catalog

**Far-path scroll**:
When the target is not attached and farther than the distance gate (or animations are disabled at the product flag). **Action is stitch**, not a bare content-offset jump.
_Avoid_: Naked `jumpTo` as the far-path UX, animateTo through the entire gap

**Far-path distance gate**:
Far path applies when the target view is not currently attached AND `|adapterPos − firstVisible| > spanCount * 9` in **per-cell** adapter space. In flat-row index (one slot per section header + one per leaf row, rows counted at each section's own column count) that is `|targetFlatIndex − firstVisibleFlatIndex| > [kFarPathDistanceGateFactor]` (= 9). Below that (or if the target header row is already visible), use near-path smooth scroll.
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
Adapter-style index for section-jump gating: each section contributes one index for its header, then one index per leaf row at [spanCount] columns, like SuperSliverList header+row lists.
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
Pointer mapping to a **catalog leaf** inside the catalog viewport: press scale in paint, tap and long-press callbacks to the page. Recognizers live on the viewport render object — not on per-cell widgets.
_Avoid_: Per-cell GestureDetector/InkWell as the default, temporary overlay widgets for every press

**Leaf tap callback**:
Page hook fired when the user completes a tap on a leaf. Receives the **leaf hit** only. Header bands and padding are silent (no synthetic leaf). Null on the viewport disables tap recognition; scroll drag still works.
_Avoid_: Per-cell onTap widgets, inferring leaf identity from paint coordinates in the page

**Leaf long-press callback**:
Page hooks for a long-press session on a leaf: start (with gesture details for anchor placement), move while the session is live, end on lift. All three are wired through [PanelCatalogViewport] or none — null start disables the long-press recognizer entirely. The viewport forwards the leaf hit; it does **not** own picker UI, clear-recents dialogs, or variant/tone policy.
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
Package-owned inherited paint tokens for the viewport: placeholder style tokens (circle, thumb and wash colours, shimmer parameters), list-selector press highlight, section header style, selector radius and skeleton colour. [PanelCatalogTheme] scopes [PanelCatalogThemeData]; [PanelCatalogThemeData.lerp] supports animated palette transitions. The pages package maps foundation tokens onto it; the viewport does not depend on the foundation.
_Avoid_: [ThemeData.extensions] for catalog paint, per-viewport color ctor args, failed or stub tokens

**Circle placeholder**:
Reserved stand-in for a unicode leaf whose glyph is not baked yet (solid circle ~0.4 × glyph bounds). It shows with no time limit until the glyph's sprite exists; with a valid disk cache it lasts at most 500 ms after a cold start. A strategy that draws paragraphs (web) never has an unbaked state and never shows it.
_Avoid_: Using circle for animated or sticker leaves, moving gradient wash, sticker-shaped shimmer for unicode cells, treating the circle as a failure state

**Thumb-first placeholder**:
Loading stand-in for document-backed animated/custom emoji: static/SVG thumb via the image pipeline until media is ready.
_Avoid_: Circle placeholder for animated leaves when a thumb exists

**Shaped loading wash**:
Loading stand-in for sticker leaves: sticker SVG silhouette with a moving gradient.
_Avoid_: Using this as the default for unicode emoji cells

### Seams

**Panel section**:
A projection of a collection plus presentation hints; never the data itself.
_Avoid_: Treating a section as the collection

**Section layout**:
Sealed per-section geometry. `Grid(spanCount, cell extent or cell aspect, header extent, insets)` now; other kinds (justified rows) can be added later. A value the layout leaves unset is inherited from the viewport-wide span, cell and header defaults, and a section with no layout is all defaults. Insets nest in the viewport padding: left and right narrow the section's columns and header text, top and bottom add space around the section. Landing, the near / far gate and the visible-window lookup all read the per-section geometry, and all slots of all sections stay in one ascending list, so a lookup is a binary search plus the visible band.
_Avoid_: One geometry for the whole viewport, per-leaf flex sizing, a lookup that walks sections or the catalogue

**Largest glyph box**:
The rule that sizes baked glyphs when sections have different cell sizes. A glyph is drawn in a box of 0.72 of its cell's shorter side; a host that bakes glyphs bakes **one** size per atlas, for the largest box any section it serves draws (`largestCatalogGlyphBox`, which uses the very formula the painter draws with), so a section with larger cells is not upscaled and one with smaller cells scales the same sprites down. The atlas layout still caps the baked size, which keeps the page count and the resident ceiling the same.
_Avoid_: A second atlas for a section with other cell sizes, sizing the bake for the smallest cell (blurs the larger ones), a size derived from the viewport default when a section overrides it

**Catalog leaf**:
A value: content key, descriptor paint facts (semantic kind, media form, animated, tintable, size hint), the spoken name and an opaque host tag. Equality covers the key, the facts and the spoken name and ignores the tag; the placeholder style is derived from the facts, and paint mode, readiness and sprite are never stored on it.
_Avoid_: Leaf class hierarchy, instance-keyed side map, generic `CatalogLeaf<T>`

**Leaf hit**:
The identity of an interaction: (section id, index, leaf). The cell is the identity, so equality covers the section id and the index, and the same key in two sections (or twice in one) is two hits. The leaf in a hit still carries the host tag.
_Avoid_: Key-only identity, host-owned (section, key) maps

**Catalog snapshot**:
The immutable list of sections the viewport renders, published through a `ValueListenable` (`package:listen`) and replaced once per logical mutation, the final snapshot assigned once.
_Avoid_: Catalog data source with listener channels, streams as the integration contract, fetch inside the viewport

**Section action**:
An optional trailing header action (label and / or icon, plus an action id) painted by the viewport and reported by `onSectionAction(sectionId, actionId)`. Its hit area is the whole header band tall and at least 48 px wide at the header's end.
_Avoid_: Host overlays on the header

**Section state**:
Where the collection behind a section stands for painting: loading, failed or loaded. It mirrors the collection's contents; a page maps idle to loading. The viewport paints a state and never changes one.
_Avoid_: An empty state of its own (empty is loaded with no leaves), a viewport that retries or fetches

**Empty message row**:
The row a loaded section with no leaves paints from its host-supplied message, centred under the header. Without a message the section is its header alone.
_Avoid_: Skeletons for an empty section, an error row

**Near-viewport event**:
A controller event telling a page that a section edge (leading or trailing) is inside the viewport band widened by the near extent, so the section can be loaded or paginated. Published once per approach; the trailing edge again when the section grew while still near. A teleporting jump announces only its landing. It is no motion and does not touch the scrolling and settled facts that pace the bake.
_Avoid_: Pages polling scroll offsets, announcing the sections a jump flew over, counting it as scroll activity

**Skeleton leaves**:
Placeholder-styled cells painted after a loading or failed section's leaves, in the section's placeholder style and content box. They are not cells: nothing is attached to the asset cache for them and they are not hit targets. Never an error UI.
_Avoid_: Error row, retry button, failed stand-in, binding a skeleton to the asset cache

**Grid direction**:
The direction a section fills its rows in, from the section's own text direction or, left unset, the `Directionality` the viewport sits in. Cells go start to end, so the first leaf of a right-to-left grid is at the right edge; a header reads and ends in the same direction (title at the start edge, action at the end edge). Only the x of a slot changes: rows, extents, landing offsets, slot order and the visible-window lookup are the same in both directions, and content is never mirrored.
_Avoid_: Mirroring glyphs, stickers or GIFs, a second projection for right to left, direction-dependent vertical offsets

**Windowed semantics**:
The semantic nodes the viewport describes for the slot range it already resolves for its bindings (the visible band plus one cell of overscan): a button per leaf labelled by its spoken name, a header node per section, a button for the header action, the empty message. The cost follows the window, not the catalogue, and no node reads a binding or a sprite. A node outside the viewport but inside the overscan is not hidden: asking for it on screen scrolls its leaf in.
_Avoid_: A semantic node for every leaf, page-level semantics only, asking the glyph source for a sprite to describe a leaf

**Roving focus**:
The one leaf cell that holds keyboard focus, owned by the attached viewport and driven through the controller (`focusLeaf`, `moveFocus`, `activateFocusedLeaf`, `clearFocus`). Arrow moves are physical, next and previous follow reading order; a vertical move keeps the screen column across sections; the focused cell scrolls into view and is painted with the focus highlight; activating reports the hit a tap would. Focus ends with the viewport and with the cell.
_Avoid_: A focus node per leaf, a focus the host mirrors in its own state, key bindings inside the viewport (a page maps keys to moves)

**Focus highlight**:
The press-highlight wash on the full cell of the focused leaf, at full alpha and under the content (a baked sprite is flushed after it). It follows the press highlight token unless the theme names a focus token.
_Avoid_: A new colour scale, a highlight drawn over the sprite

**Hover highlight**:
The wash a mouse hovering a leaf paints on its cell: a rounded rect inset from the cell, under the content, instant (no fade, ripple or scale), for the mouse only. Off unless the theme carries a hover token, so a page sets it for a pointer arrangement and leaves it null for touch. The cell is found again at every paint, so content moving under a still mouse moves the wash with it.
_Avoid_: A hover state the host mirrors, a hover animation, hover on a finger or stylus in contact

**Scroll event**:
The one typed controller event stream: drag, fling, section jump, near-viewport, focus and current-section changes, plus two derived activity facts. A scrolling-changed event fires at once when the catalogue starts moving and after one quiet frame when it stops; a settled event carries the visible leaf keys, top first.
_Avoid_: Separate listener channels per concern

### Glyph atlas

**Glyph atlas page**:
A fixed-size GPU image (2048 × 2048) holding baked glyph cells with a transparent gutter around each. Held through **page residency**, which the atlas and the asset cache's leaf bindings share and which counts holds per page; a leaf binding holds the page, never its pixels. A static page is immutable once composed.
_Avoid_: Per-leaf bitmap, per-binding pixel ownership, mutating a static page in place, sharing a static page with animation frames

**Bake**:
The paced, background rasterisation of the glyphs the data layer supplies into atlas pages. Runs on the root isolate behind a rasteriser seam, a few glyphs per frame under a frame-time governor; prioritises the visible band and pauses during the panel open animation and scrolling. Persisted pages are reloaded instead of re-baked while the cache key still matches.
_Avoid_: Detecting missing glyphs in the engine (the data layer decides the set), baking during a fling, a paragraph fallback on baking platforms, rasterising at scroll time

**Bake governor**:
The rule that sets how many glyphs the next frame may bake (up to about 16) from the measured cost of recent frames: it halves the pace when a frame nears its vsync budget and climbs back while frames stay cheap. It never reaches zero; stopping is the pause rules' job.
_Avoid_: A fixed glyphs-per-frame number tuned on one device, a governor that pauses by itself, reacting to the same slow frame twice

**Bake pause rules**:
Baking runs only while the panel is visible, nothing is scrolling (including the fling) and the panel is not animating open; it resumes after a few quiet frames. The host owns the three signals; the bake only reads them.
_Avoid_: Baking beside a fling or the open animation, a timer-based resume, wiring the signals inside the baker

**Visible-band priority**:
The host names the glyphs on screen and the bake composes their page first, then the nearest pages. A glyph's cell is fixed by catalogue order, so priority works per page: a visible glyph waits for its own page (about 44 frames at the default pace), never for the whole catalogue.
_Avoid_: Reordering cells to put the visible band first (a persisted page must still match its glyphs), partial pages drawn before they are complete

**Baked glyph (sprite)**:
One glyph rasterised once at the baked cell size and addressed as a page plus a source rectangle. The viewport draws the sprites of one atlas page in one batched atlas draw. A paintable without a sprite paints itself.
_Avoid_: Glyph drawn as text at scroll time on baking platforms, one image draw per leaf, a second paint path for emoji beside the shared paintable contract

**Glyph cache key**:
What a persisted set of atlas pages was baked for: the system emoji art version, the screen density, the baked glyph size, the atlas layout version and a hash of the planned glyph list. Compared with the key a launch needs, it gives one of four **cache verdicts**: hit (same key), stale (only the art version or the catalogue differs), discard (density, glyph size or layout version differs) and miss (nothing readable persisted).
_Avoid_: A cache keyed by file name or timestamp, treating a density change as stale, a verdict that depends on how the pages were stored

**Stale-while-rebake**:
On a stale verdict the old pages keep drawing the glyphs they hold while the new set bakes into a staged generation that nothing reads; when its last page is ready the new set is committed and every sprite changes in one step. A discard or a miss has nothing to keep drawing, so its cells show the circle placeholder as on a first run. The old and the new set are both resident for the duration, once, after an art or catalogue change; the old images are counted in the atlas's resident bytes and released with the resident pages under memory pressure.

The same hand-over serves a plan that changes in a running session (a skin tone chosen for the first time, a new screen density): the old atlas is **retired**, stops writing, and gives the art it was drawing to its successor, which draws it from its first frame and swaps once its own pages are ready. A persistent cache has one writer: the successor waits for the retired atlas's disk work before it touches the cache.
_Avoid_: Swapping page by page, deleting the old pages when the rebake starts, committing the staged pages before they are all baked, a blank grid while a replacement atlas reads its pages, two atlases writing one cache

**Art version signal**:
An opaque string that changes when the system emoji art may have changed (an OS or emoji font update), supplied behind the `GlyphArtVersionSource` seam without any native plugin. Part of the glyph cache key; a signal that cannot be read means nothing persisted is trusted for that launch. The intended source is a **sentinel fingerprint**: a pixel hash of a few sentinel glyphs spanning emoji versions, drawn by the same rasteriser the bake uses, one per frame, once per launch. It changes when a sentinel is restyled or a newer sentinel turns from a missing-glyph box into art; an OS version string is not part of it, because it changes without the art changing.
_Avoid_: Reading the OS version in the engine, a native call for the font version

**Glyph probe**:
Decides which glyphs the system cannot draw, from pixels it is handed: a glyph is unsupported when its cell is identical to the cell of a missing-glyph reference, or empty. It rasterises nothing itself, keeps only a hash per cell, and has no verdict (neither supported nor unsupported) for a glyph it has not seen; a missing verdict means "show it". Its result is valid for one art version and is discarded for another. Pure Dart, in the emoji data layer.
_Avoid_: A native glyph-support query, probing by drawing every glyph a second time, hiding a glyph that has no verdict

**Shared bake pass**:
The bake draws every glyph once into a strip; an optional **bake observer** is shown each wanted glyph's cell (and the reference glyphs, drawn once in a strip that is never baked into a page) after the strip is made, so the probe needs no rasterising pass of its own. The readback is off the baking step, a strip at a time, and skipped for strips nobody wants. The pass only sees what is baked: a cache hit restores pages and draws nothing, so the probe keeps its own persisted result for the art version. The atlas plans the unfiltered glyph list and the grid hides unsupported glyphs by filtering its data, so the cache key never depends on the probe's result.
_Avoid_: A second rasterising pass for the probe, filtering the atlas plan by the probe (it would re-bake every page once the probe finishes)

**Page residency**:
Which atlas pages are resident and for how long. A page is pinned by a hold: one per leaf binding (the page its glyph is on, from attach to detach) and one on every page while the panel is open. When nothing pins a page, its **retention** starts, a time-to-live layered on the cache's keep-until-pressure rule (60 seconds by default, host-configurable); a new hold within it cancels the release, so reopening needs no reload, and after it the page is read back from the page store. Pages that are not resident are read back one per frame, never in a scroll or the open animation. Memory pressure releases every page at once, pinned or not, ignoring the retention. Hold counts belong to the holder and survive the release of the image, so evicting or clearing a cache entry under a live binding never changes a count.
_Avoid_: Releasing a hold by looking the entry up again, a count stored with the image, keeping pages for the life of the shell, releasing pages on every panel close, holding pages through memory pressure, a timer or release rule inside the viewport

**Atlas page pool**:
The set of atlas pages of one kind resident at once, within a resident-memory ceiling (64 MiB for static glyph pages). A later dynamic pool for animation frames follows the same sprite contract and is kept separate from the static pool.
_Avoid_: One pool for static and animated content, a ceiling raised to avoid a size cap

**Document-backed leaf**:
A catalog cell whose content key is a `document` (animated or custom emoji, sticker) rather than a unicode sequence. Its placeholder style comes from the descriptor.
_Avoid_: Treating every cell as a glyph string forever

## Superseded terms

Migration notes. These terms name code that the package set replaces.

| Old term | Now |
| -------- | --- |
| KeyboardPanel, KeyboardPanelController | Panel shell, panel shell controller, presentation controller ([Chat Chrome glossary](../chrome/CONTEXT.md)) |
| Global catalog asset cache | Asset cache, host-created and scoped ([Content and Assets glossary](../content/CONTEXT.md)) |
| Catalog data source | Catalog snapshot |
| Leaf presentation (ready, loading, failed) | Placeholder derived from the descriptor; staged readiness has no failed stage |
| Leaf identity `[CatalogLeaf]` in callbacks | Leaf hit |

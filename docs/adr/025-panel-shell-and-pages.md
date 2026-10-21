# ADR 025: Panel shell, page contract and state ownership

The panel splits into a host-independent **panel shell** (`panel_shell`) and a
pages package (`panel_pages`). The shell takes an open registry of pages and
owns the page selection and search state. Pages own their content, results and
top strip. This supersedes the controller and widget-API parts of
[ADR 007](007-keyboard-panel-controller.md).

**Status**: Accepted  
**Date**: 2026-10-16  
**Amended**: 2026-10-16 — state is `package:listen`, typed events are synchronous `Stream`s ([ADR 023](023-data-layering-and-persistence.md) Amendment)  
**Amended**: 2026-10-16 — the **panel arrangement** (`touch`, `pointer`) splits the bottom chrome and places a page's strip ([Amendment](#amendment-panel-arrangement))  
**Amended**: 2026-10-16 — cell interactions under a mouse: the recents context menu, the variant picker rules and the hold seam ([Amendment](#amendment-cell-interactions-under-a-mouse))  
**Amended**: 2026-10-16 — under `touch` a page may place the search field itself and draw a sticky header ([Amendment](#amendment-where-the-field-sits)); the arrangement selects between the two  
**Amended**: 2026-10-17 — the touch strip with packs is the reference mobile client's ([Amendment](#amendment-the-touch-strip-with-packs))  
**Relates to**: [ADR 007](007-keyboard-panel-controller.md) (superseded in part), [ADR 020](020-package-topology.md), [ADR 023](023-data-layering-and-persistence.md), [ADR 024](024-panel-catalog-seams.md), [ADR 028](028-panel-presentation.md)

## Decided

| Area | Decision |
| ---- | -------- |
| Page contract | An open registry. The shell takes an ordered list of `PanelPage`: stable id, tab descriptor (semantic icon id and label key, mapped by presentation), page builder, and declared capabilities (search, bottom actions, top strip). The closed tab enum, the allow bitset and the closed switch are deleted. The shell never imports a concrete page. A desktop-style mode set is a different list plus per-page features. |
| Search | The shell owns the single field, the query, focus, open or closed mode and its transition, and tells the active page about query changes. The page maps the query to its `SearchSource` and renders results as its search collection in its viewport. A shared helper holds debounce and stale-result handling. The query survives page switches; closing search clears it. Escape (`DismissIntent`) closes search while it is open and otherwise forwards the intent to the nearest enclosing `Actions`, so a popup that hosts the shell closes on the second press. The popup binds Escape itself, because `Shortcuts` resolves the action nearest the focused widget. |
| Strip and bottom chrome | A page owns its top strip (category or set strip) and keeps it in sync with its catalog scroll. The shell owns the bottom bar: type tabs plus an action row from the active page's declared actions (backspace, search, settings). Bottom-bar hide and show is driven by a typed `PageScrollActivity` (drag, fling, idle) the page publishes; there is no `GlobalKey` reach-in. |
| State ownership | `PanelShellController` is the single source of truth for the selected page id and the search state (open, query, focus intent), on `package:listen` `ValueListenable`s; page events, scroll activity and result counts are synchronous broadcast `Stream`s. It persists the page id as a string through `PreferenceStore`. A separate presentation controller ([ADR 028](028-panel-presentation.md)) owns visibility and wraps the shell. Commands are one-way; user gestures call the same public intents hosts use (`selectPage`, `openSearch`); there are no `adopt*` back-doors. The host derives the composer's emoji-icon state from presentation visibility and the shell's selected page. |
| Effects | One sealed `PanelEvent` and a single handler: `ContentPicked(leaf hit, source: grid, recent or search)`, `BackspaceRequested`, `ActionInvoked(pageId, actionId)`, `ClearRecentsRequested`, `ContentCopyRequested(key, kind)`, `RecentRemoveRequested(key, kind)`, `PageChanged`, `SearchOpened`, `SearchClosed`. The host inserts content and calls `RecentsStore.record`; the panel never writes recents. Named-callback adapters, if wanted, live in the host. |
| Page internals | One shared `CatalogPage` scaffold: viewport hosting, snapshot building from collections, near-viewport loading and pagination, search-results mode, strip slot, scroll-activity publishing, long-press session plumbing. Per-kind policy objects supply section layout presets, leaf tag and pick policy, strip widget, long-press behaviour (emoji variant picker, sticker preview), placeholder overrides and declared actions. Emoji, sticker and GIF pages are thin compositions. The variant (skin-tone) picker is its own widget fed by the entry's variants. Extent and offset maths live in the viewport and its controller only. |
| Shell units | Pager, type tabs, bottom bar, search field. Page-switch and search transitions belong to the shell; open and close motion belongs to presentation; motion roles belong to foundation ([ADR 027](027-foundation-theme-glass-motion.md)). |
| Atlas host | The page that shows baked glyphs plans and creates the glyph atlas from the glyph list its `CollectionSource` supplies, and forwards scroll and visible-band events from the viewport controller to it. The pause signals (panel visible, panel opening) are published by the shell and presentation as `ValueListenable`s and wired by the host. |

Boundary items handled by presentation: search growing the panel
(`SearchOpened` and `SearchClosed` are the signal), IME hand-off on search
focus, and visibility, open and close, and persisted height or popup size.

## Amendment: panel arrangement

The shell had one layout, the one a finger needs. A popup or a docked section
under a mouse is a different arrangement of the same parts, not a different
shell. This amends the *Strip and bottom chrome* and *Search* rows above.

| Area | Decision |
| ---- | -------- |
| Vocabulary | `PanelArrangement { touch, pointer }`, defined in `panel_shell` beside `PanelShell`. A presentation chooses it and hands it to `PanelShell(arrangement:)`; the shell provides it to its pages through `PanelArrangementScope`, which answers `touch` where no shell is above. No package reads the platform for it: a presentation strategy decides. `KeyboardReplacement` and the fake presentation keep `touch`; `AnchoredPopup` and `Docked` pass `pointer`. |
| `touch` | Unchanged: type tabs and the page's actions in one floating bottom bar that slides away as the content is read; the page's strip over its catalogue, sliding away with the reading, and a search field a page may place among its content ([where the field sits](#amendment-where-the-field-sits)); an open search with no query keeps the whole catalogue on screen, as the reference clients do. |
| `pointer`, tabs | The type tabs pill moves to the top of the shell column, above the search field. One page has no tabs. |
| `pointer`, bar | The floating bar keeps the selected page's actions that the arrangement offers (`PanelArrangement.offersAction`: backspace is a touch idiom, not offered) at the end side, and is not built when none is left. Scrolling never hides it (a wheel step is a drag report; hide-on-scroll is a touch idiom); an open search does, as under `touch`. It rises above the strip the page pins at the bottom: the page tells the shell that strip's measured height (`PanelPageHost.reportBottomExtent`, kept per page, read as `PanelShellController.bottomExtent`), so no height is repeated in the shell. The shell keeps the safe inset for itself under `pointer`, and tells pages the bar's room only. |
| `pointer`, strip | A page that pins its strip at the bottom says so per arrangement (`CatalogPagePolicy.stripAtBottom`) and the strip stays page-owned: shell owns the bar, page owns the strip. The emoji strip is then a 1 px separator over 36 px of icons on its own fill, the active category marked by a 28 px square of radius 8 that slides to the next icon over the `selectionSlide` motion role (400 ms, ease-out cubic; placed, not moved, on the first selection and where animations are off), no paint on hover, the click cursor over an icon. |
| `pointer`, search | Where the page declared it: a page that places its field `inline` has it as the first thing in its content, under `pointer` too, where it scrolls away with the grid and does not pin when search opens (`PanelArrangement.pinsSearchWhenOpen` is a `touch` idiom); `pinned` is the shell's, below the tabs. An empty query with search open keeps the whole catalogue (and, under `pointer`, the strip). The trailing control is a clear control that exists only while there is text, under both arrangements: it empties the field and leaves search open. Search is left by Escape or the controller, never by a control of the field. |
| `pointer`, header | Nothing a page draws slides: a strip is a plain part of the page's column (above the catalogue, or pinned below it) and there is no sticky header. `PanelArrangement.headerSlidesAway` is the one question a page asks. |
| `pointer`, cells | A mouse hovering a cell paints the hover wash (rounded rect, inset from the cell, instant) through `PanelCatalogThemeData.leafHoverHighlightColor`, which the page maps from chrome tokens and sets only under `pointer`; the click cursor over a cell is the viewport's own. |

## Amendment: cell interactions under a mouse

A mouse has a second button and a pointer that stays where it is. This adds
what a page does with them, and the one new thing a page asks of the shell.

| Area | Decision |
| ---- | -------- |
| Events | Two additive `PanelEvent`s, both handled by the host like every effect: `ContentCopyRequested(key, kind)` (the host puts a representation of the content on the clipboard, for a unicode key its text) and `RecentRemoveRequested(key, kind)` (the host calls `RecentsStore.remove`). Pages ask through `PanelPageHost.requestCopy` and `requestRemoveRecent`. `ClearRecentsRequested` is reused; the host confirms before clearing. The panel still writes no recents and touches no clipboard. |
| Context menu | `PanelArrangement.usesContextMenu` is true under `pointer`. There a right click (mouse only, button up) on a cell goes to `CatalogPagePolicy.menuOf`, which returns declarative entries (`CatalogMenuEntry`: item with id, label and an attention flag, or separator), and a chosen item to `onMenuAction`. Empty entries mean the click does nothing at all. The emoji policy answers only on an emoji of the recents section: copy, remove from recent, a separator, clear recent (attention colour); the recents header has no clear action under either arrangement, and under `touch` there is no menu: a finger's long press on a recent asks the host to clear them (see *Amendment: desktop parity*). The menu is `CatalogContextMenuHost`, built on the widgets layer's `RawMenuAnchor` and `MenuController.open(position:)` (the framework owns the overlay and its open and close; the menu sees the page's theme and strings because it is built as part of the page). It is modal like a native menu: a press anywhere else closes it and goes no further. It takes focus for Escape, the arrows and Enter, and gives it back to the composer when it closes. Labels are `PanelStrings` members (`copyAction`, `removeRecentAction`, `clearRecentAction`). |
| Holds | `PanelPageHost.holdAutoHide()` returns a `PanelPageHold` (`release()` is idempotent). The shell counts the holds of every page and publishes the count as `PanelShellController.autoHideHolds` (a `ValueListenable<int>`); a hold taken after dispose is inert. The shell and its pages know no presentation, so the host listens and keeps one `PanelPresentationController.holdAutoHide()` while the count is above zero ([ADR 028](028-panel-presentation.md)). A menu or picker takes its hold as it opens and releases it as it starts to close, or with the page: such a surface stands outside the panel's own box, and the pointer moving onto it would read as leaving a popup. |
| Long press | The viewport takes a delay per cell and pointer kind ([ADR 024](024-panel-catalog-seams.md)); `CatalogPagePolicy.longPressDelayOf(hit, collection, kind)` answers it. The emoji policy answers, for a mouse on an emoji with variants: zero when the user has never chosen a variant of its base (the picker opens as the button goes down), 500 ms otherwise (a release before it picks the emoji as the grid shows it); the recents hold even before a choice, because a cell there is already the exact emoji used. A finger, a stylus or anything else keeps the platform's delay. That a choice was made is `PreferenceStore.preferredVariant(base) != null`, and choosing the base is remembered as the base itself, so no new preference exists. |
| Picker | One layout for every arrangement: `EmojiVariantPickerLayout` with the pressed cell's own size as the option size and the grid's glyph box and font scale for the glyph (`CatalogContentBox.glyphBoxExtent`, `TextGlyphProducer.defaultFontScale`), 8 px pads, a 1 px separator after the first of up to six options (more options are a grid of six columns with none), a 10 px shadow margin, 8 px radius. Above the cell with a 2 px gap, below it if it would cross the top of the viewport; horizontally proportional to the column and clamped to the viewport. It fades over the `fade` motion role. It sits on an opaque barrier: a press anywhere else (any button) dismisses it and goes no further. While open, the pressed cell keeps its hover wash and the wheel does not scroll (`pinnedLeaf` on the viewport, set by the page for as long as the session is open). A mouse that held for the delay: releasing over an option picks it, elsewhere on the card closes it, outside the card closes it without a pick. A mouse whose press opened it at once: the same, except that releasing outside the card leaves it open until the next click, so its options can be read and clicked. A finger: the highlight follows it along the row and lifting chooses the nearest option, as before. |
| Overflow | The old picker clipped each option to a 32 px rounded container, and a colour emoji font draws bitmaps larger than the em box it lays out, so a hand, a couple or a runner was cropped at the container's edge (measured with Apple Color Emoji: four of six options). The cell is now the grid's, larger than the glyph box, and nothing clips. |

The reference client has no backspace control; it is kept under `touch` because
the product asked for it, as the one action in a bar that stays out of the way.
The pointer arrangement does not offer it (`PanelArrangement.offersAction`).
Dropping it everywhere is one declaration: remove `PageAction.backspace()`
from the page's capabilities.

## Amendment: where the field sits

This is the `touch` arrangement's layout; under `pointer` the arrangement above
wins (the shell draws the field, the strip is plain column). A page reads the
arrangement and takes one layout or the other; the two are never blended, and a
page built with no shell above answers `touch`.

The first cut drew the one field in the shell, above the pager, and the page's
strip in a column above the catalogue. Both stood still while the catalogue
scrolled, which dropped the behavior the panel shipped with: the category strip
slides away as the user reads on and returns as they read back, and the search
field is the first thing in the content, scrolls away with it and pins to the
top once search opens.

| Area | Decision |
| ---- | -------- |
| State | Unchanged. The shell controller owns the query, the focus intent and open or closed; the field is a projection of it, wherever it is drawn. |
| Placement | `PageCapabilities.searchPlacement`: `pinned` (the default; the shell draws the field above the pager) or `inline` (the page draws it; honoured under `touch` only). An inline page places a `PanelSearchField` among its own content; the shell gives it the controller and the selection toolbar through a `PanelSearchFieldScope` above the pager. The shell draws no field for an inline page. |
| Sticky header | `CatalogPage` draws the policy's strip and, for an inline page, the field over the catalogue and pads the catalogue by their extent. The geometry (offsets, hairlines, when the strip yields) is one pure class, `CatalogStickyHeader`, fed by the catalogue's scroll events. The strip's extent is declared by the policy (`stripExtent`), and section jumps land under it (`headerLandingInset`). |
| Field chrome | The leading icon morphs (magnifier, progress ring, back chevron that clears), under both arrangements. Under `touch` the trailing control clears the query only and search is left through the controller (back, the composer, another page), not by a control of the field; `pointer` adds the cancel behavior above. |
| Motion | Two roles join the table: `stripReveal` and `iconMorph`. |

Why page placement and not shell-side translation: the field's position is a
function of the catalogue's offset and of the strip's, both of which the page
owns; reporting them out to the shell to move a widget back in would invent a
channel for one consumer. State stays in the shell, which is what lets the
field survive a page switch.

## Supersedes in ADR 007

| ADR 007 decision | Now |
| ---------------- | --- |
| One `KeyboardPanelController` spanning open, tab, search and the inset claim | Shell controller (page, search) plus presentation controller (visibility) |
| Typed-listener house pattern | `package:listen` ([ADR 023](023-data-layering-and-persistence.md)); typed events as synchronous `Stream`s |
| Selected tab stored as an int index | String page id |
| Widget API: one controller, presentation config, effect callbacks | Controller, page registry and one `PanelEvent` handler |

Kept: the controller is the source of truth, the widget projects it, and no
`GlobalKey` control path exists.

## Why

- Telegram iOS and Desktop separate the host from the selector, use a content model and an interaction bag, and treat mode and feature set as data. Desktop's selector owns the tab while the host owns visibility.
- The old panel code held state in four places with `adopt*` back-doors, was emoji-only by construction, and reached the page through `GlobalKey<EmojiPageState>`.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Closed tab enum with a feature bitset; pages as plain widgets | Adding a page edits the shell; no declared capabilities |
| Each page owning its search; the shell owning search results | The field, focus and query must survive page switches; results are page data |
| Shell owning strips; pages owning the bottom bar | Strips follow catalog scroll; the bottom bar spans pages |
| One controller spanning shell and presentation; widget-local state | Visibility and page selection change for different reasons; state must survive a presentation switch |
| Typed callback bag; per-concern streams | One sealed event type is exhaustive and testable |
| An independent page per kind; one fully config-driven generic page | Duplicated viewport glue, or a configuration language |

## Related

- Glossary: [Chat chrome](../chrome/CONTEXT.md)

## Amendment: desktop parity

A pass that took the pointer arrangement and the emoji page closer to the
reference clients. It amends the rows above where it says so.

| Area | Decision |
| ---- | -------- |
| Backspace | Not offered under `pointer` (`PanelArrangement.offersAction`). A page whose only action is backspace has no bar there: the shell builds none, so the column is the page's. |
| Search with no query | Search open with an empty query keeps the whole catalogue under both arrangements (Android keeps its grid adapter and iOS its item groups; only a non-empty query replaces them). `CatalogPagePolicy.visibleCollections` no longer takes a `searchOpen` flag and `PanelArrangement.narrowsEmptySearch` is gone. |
| Search field | Under `pointer` an `inline` field is the page's, scrolls away with the grid and never pins (`pinsSearchWhenOpen`); `searchPlacementOf` is gone, the declared placement is the placement. The trailing clear control shows only with text, in both arrangements. |
| Recents | The header is a title, with no button, in both arrangements. A finger's long press on an emoji of the recents asks the host to clear them (`requestClearRecents`) instead of opening the variant picker; a mouse keeps the hold that opens the picker, and the right-click menu. |
| Search results | A hit on any key of an emoji (its base, a tone, a gender) is one result, shown as the grid shows the emoji. The glyph atlas is planned from what the grid shows, so a result of a variant's own had no art and was drawn as a circle. |
| Sections | `EmojiCollectionSource` lists the reference client's categories (`EmojiSection.reference`): people (smileys and people), nature, food, activity, travel, objects and symbols, the flags after the symbols, in that order. The ids are those of `CollectionId.category`. A group no section names keeps a section of its own, so a catalogue that gains a group shows it. The order of the emoji inside a section is the catalogue's. |
| Tabs | The type tabs pill is scaled down as a whole when the column is narrower than it, instead of overflowing it (a dock at its narrowest, large text). |

## Amendment: desktop polish

| Area | Decision |
| ---- | -------- |
| Long press | Supersedes the zero delay of *Long press* above: a mouse on an emoji with variants always holds for 500 ms, chosen before or not; a click picks the emoji as the grid shows it. `EmojiVariantPickerMode.pointerImmediate` is gone, and a picker a mouse opened closes when the button lifts outside it. |
| Context menu | The menu takes focus on its own scope, not on its first item: nothing is highlighted until the pointer or a key says so (Down highlights the first item, Up the last). |
| Genders | `EmojiCatalog` lists the person, the man and the woman of an emoji as entries of their own, in that order, each with its tones only, as the reference clients do (`flattenGenders`, on by default). An emoji whose genders have no toneless form (two people of mixed tones) keeps its one entry. |
| Grid | Under `pointer` the emoji grid is adaptive ([ADR 024](024-panel-catalog-seams.md)): 37 px desired cells, 2 px shorter than wide, 8 px in from the start and 4 from the end. A dock or popup that changes width changes its columns and cell size. |
| Glyphs | A variant chosen for the first time is baked on its own, in a layer of the atlas host, and every glyph the host ever drew stays drawn ([ADR 022](022-asset-cache-and-media-pipeline.md)). |
| Emoji size | Under `pointer` an emoji is drawn at 24 logical pixels at every width, in the grid and in the variant picker (`EmojiPagePolicy.pointerGlyphSize`; the grid's `glyphExtent` is 24 over the glyph font scale). The reference desktop client draws its large emoji at 24 px whatever the cell, and a colour emoji font's art fills exactly its font size (measured with Apple Color Emoji: 😀 at 100 px is 100 x 100). The cell-relative box drew 21.4 to 23.3 px. Touch is unchanged. |
| Strip | Supersedes the pointer strip of *Panel arrangement*: under `pointer` the strip is the reference desktop client's footer as it is with packs of its own (`EmojiStripFooter`). 36 px on the strip fill, no line over it; a 30 px slot per icon from 3 px in, left-aligned: the recents, the categories folded into the first one's icon, then one per pack (a section of a `CollectionId.set`, drawn by its cover, else its first item, at 21 px). While a category is active the folded icon opens into the categories' icons, as wide as the footer leaves it (`clamp(W + 30 - n * 30, 165, 210)`, in whole icons plus a half; a narrower group scrolls its icons). The marker is a 28 px square of radius 8 under the recents or a pack, a pill of radius 14 over the open group; the category is told by its icon's colour, which changes at once. The marker slides over `selectionSlide` as the catalogue moves into a section, and is put in place at once by a click. The footer, and the open group, centre the active icon, linearly over 400 ms. The wheel (horizontal delta first) and a mouse drag (10 px before it counts; a drag picks nothing) scroll at once. An edge with icons beyond it fades into the fill. The touch strip has no pack tabs. |

## Amendment: desktop chrome and mobile search

| Area | Decision |
| ---- | -------- |
| Section tabs | Under `pointer` the shell's page switcher is the reference desktop client's tabs slider (`PanelSectionTabs`), not the pill: the column's width shared equally by one section per page, names centred (13 px semibold at 17 px from the top), a 3 px bar in the accent across the selected section at 50 px that slides linearly over 150 ms, labels going from the muted text colour to the accent as the bar comes over them, a ripple from the press, choice on release over the section, no hover, a line under the 53 px bar. Choosing slides the pages over 200 ms (ease-out circ), from the neighbouring page. The sizes and timings of the slider are the reference's defaults as remembered: its style file is not in the source checked. Under `touch` the pill stays in the bottom bar. |
| Strip layout | `EmojiStripLayout`: `automatic` (the default) is the reference client's rule, plain with no pack and grouped with any; a host can fix `plain` or `grouped` (`EmojiPage.stripLayout`). Plain: one slot per icon, `max(30, floor((W - 6) / n))` wide from 3 px in, the 28 px square in the middle of the active one. |
| Group motion | The group opens and closes linearly over 240 ms (the reference's slide duration, as remembered), its icons at their places revealed by a clip that grows, what follows it sliding with its width; while a category is active the marker grows towards the group's width as it is at that frame, on the reference's exact ease-out cubic (`1 - (1 - t)^3`). |
| Cell ink | Under `pointer` a hovered cell gets a 34 x 32 box of radius 8, centred, and a press draws nothing (`CatalogPressFeedback.none`): the box stays on the pressed cell. The variant picker draws the same box. Under `touch` the press wash and shrink stay. |
| Search keyboard | A drag on the catalogue while searching lowers the soft keyboard and leaves the field focused, as the reference mobile client does: the page releases search focus (as before), and the host lowers the keyboard when search lets go of its focus while it stays open. A press on the still-focused field asks for focus again (`requestSearchFocus`), and the field raises its keyboard. |

## Amendment: glass bands, the tone for all, the mobile picker

| Area | Decision |
| ---- | -------- |
| Glass bands | The shell publishes its background (`PanelBackgroundScope`): transparent on glass. A page's bands over the catalogue (the sticky strip, the search field) and the touch strip paint it instead of the panel tokens' background, and the catalogue is painted from their lower edge as they move, so no cell shows behind a see-through band. |
| Tab underline | `PanelShell.sectionTabsBar`: `label` (the default, the reference desktop client's: as wide as the label, rounded on top by 2 px, sliding between labels and taking their width) or `section` (across the section). |
| Landing | A jumped-to header lands at the page's own top padding plus a strip that overlays the catalogue, never under the field's band, which scrolls away (pointer) or keeps a band of its own. |
| Plain strip | Supersedes the even spread of *Amendment: desktop chrome and mobile search*: the plain layout is the grouped footer's look (30 px slots from 3 px in, the 28 px square) with nothing folded. |
| Tone for all | Under `pointer` the Smileys & People header ends in a button (`EmojiPagePolicy.colorAllActionId`) that opens the waving hand as it is and in each tone under `PanelStrings.colorAllTitle`. A choice is `PreferenceStore.setDefaultVariant`: every per-emoji choice is forgotten and the tone is shown for every emoji with a variant whose people all have it (others keep their base); a later choice for one emoji wins; recents keep what was picked; nothing is inserted. Policies get the action's bounds and a context (`onSectionAction(context:, bounds:, viewportBounds:)`), from `PanelCatalogController.sectionActionBoundsOf`. |
| Mobile picker | Anything but a mouse gets the reference mobile client's picker (`EmojiToneSession`, `EmojiTonePicker`): one person, a 222 x 47 window of 32 px emoji 5 px in and 4 px apart over a card with an arrow whose tip is on the top of the glyph's box, the saved tone over the pressed glyph, held 5 px inside the overlay; the finger moves the mark in 36 px steps once it has left a 0.2 cm slop, the mark (36 px, radius 4) sliding over 125 ms on an ease-out quint and the option under it at full size, the others at 0.9; lifting chooses. Two people: the emoji as it is beside a separator and a row of five tones per person (225 x 75.66); lifting leaves it up, a tap or drag on a row sets that person's tone (given to both while the other has none) and keeps the choice at once, a press elsewhere closes it. Haptics as Flutter maps them on Android: `vibrate` on open, `selectionClick` per change, `mediumImpact` on the choice. An assistive tap on an option chooses it. Not ported: the cell springing back as the picker opens, and the system dropdown animation (it fades). |

## Amendment: the touch strip with packs

Supersedes "The touch strip has no pack tabs" (*Amendment: desktop polish*).
Under `touch` the emoji strip follows `EmojiStripLayout` as the pointer
footer does: plain with no pack, grouped with any, unless the host fixes one.
Grouped is the reference mobile client's `EmojiTabsStrip` with custom emoji
(`EmojiStripTabs`).

| Area | Decision |
| ---- | -------- |
| Row | 36 px, 11 px in from both ends, 30 px tabs 3 px apart: the recents, the group of the categories, then a tab per pack drawn by its cover, else its first item, at 24 px (a still). It scrolls sideways when it does not fit. |
| Group | Open while a category is active: 32 px a category, as wide as `32 · min(5.7, n)`, scrolling inside beyond that. Otherwise one tab wide, showing its first category, back at its start. Its width moves over 475 ms ease-out quint. |
| Pill | One pill marks the active tab, or the whole open group; the category in it is told by its icon's colour (350 ms). It slides between tabs over 350 ms ease-out quint, widening by up to 30 % and flattening by 5 % at the middle of its way. The group is drawn only inside the pill and its first tab's circle, so it is revealed as the pill reaches it. |
| Scroll | A pack is kept 50 px in from either edge; the recents and the group bring the row back to its start; an open group keeps its active category in view; 250 ms ease-out quint. First build, disabled animations and instant motion place everything at once. |

Metrics and traces: the `telegram-java-to-flutter` skill's
`emoji-tabs-strip.md`.


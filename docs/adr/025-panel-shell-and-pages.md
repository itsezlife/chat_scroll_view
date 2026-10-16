# ADR 025: Panel shell, page contract and state ownership

The panel splits into a host-independent **panel shell** (`panel_shell`) and a
pages package (`panel_pages`). The shell takes an open registry of pages and
owns the page selection and search state. Pages own their content, results and
top strip. This supersedes the controller and widget-API parts of
[ADR 007](007-keyboard-panel-controller.md).

**Status**: Accepted  
**Date**: 2026-10-16  
**Amended**: 2026-10-16 — state is `package:listen`, typed events are synchronous `Stream`s ([ADR 023](023-data-layering-and-persistence.md) Amendment)  
**Amended**: 2026-10-16 — a page may place the search field itself and draw a sticky header (see *Amendment: where the field sits*)  
**Relates to**: [ADR 007](007-keyboard-panel-controller.md) (superseded in part), [ADR 020](020-package-topology.md), [ADR 023](023-data-layering-and-persistence.md), [ADR 024](024-panel-catalog-seams.md), [ADR 028](028-panel-presentation.md)

## Decided

| Area | Decision |
| ---- | -------- |
| Page contract | An open registry. The shell takes an ordered list of `PanelPage`: stable id, tab descriptor (semantic icon id and label key, mapped by presentation), page builder, and declared capabilities (search, bottom actions, top strip). The closed tab enum, the allow bitset and the closed switch are deleted. The shell never imports a concrete page. A desktop-style mode set is a different list plus per-page features. |
| Search | The shell owns the single field, the query, focus, open or closed mode and its transition, and tells the active page about query changes. The page maps the query to its `SearchSource` and renders results as its search collection in its viewport. A shared helper holds debounce and stale-result handling. The query survives page switches; closing search clears it. Escape (`DismissIntent`) closes search while it is open and otherwise forwards the intent to the nearest enclosing `Actions`, so a popup that hosts the shell closes on the second press. The popup binds Escape itself, because `Shortcuts` resolves the action nearest the focused widget. |
| Strip and bottom chrome | A page owns its top strip (category or set strip) and keeps it in sync with its catalog scroll. The shell owns the bottom bar: type tabs plus an action row from the active page's declared actions (backspace, search, settings). Bottom-bar hide and show is driven by a typed `PageScrollActivity` (drag, fling, idle) the page publishes; there is no `GlobalKey` reach-in. |
| State ownership | `PanelShellController` is the single source of truth for the selected page id and the search state (open, query, focus intent), on `package:listen` `ValueListenable`s; page events, scroll activity and result counts are synchronous broadcast `Stream`s. It persists the page id as a string through `PreferenceStore`. A separate presentation controller ([ADR 028](028-panel-presentation.md)) owns visibility and wraps the shell. Commands are one-way; user gestures call the same public intents hosts use (`selectPage`, `openSearch`); there are no `adopt*` back-doors. The host derives the composer's emoji-icon state from presentation visibility and the shell's selected page. |
| Effects | One sealed `PanelEvent` and a single handler: `ContentPicked(leaf hit, source: grid, recent or search)`, `BackspaceRequested`, `ActionInvoked(pageId, actionId)`, `ClearRecentsRequested`, `PageChanged`, `SearchOpened`, `SearchClosed`. The host inserts content and calls `RecentsStore.record`; the panel never writes recents. Named-callback adapters, if wanted, live in the host. |
| Page internals | One shared `CatalogPage` scaffold: viewport hosting, snapshot building from collections, near-viewport loading and pagination, search-results mode, strip slot, scroll-activity publishing, long-press session plumbing. Per-kind policy objects supply section layout presets, leaf tag and pick policy, strip widget, long-press behaviour (emoji variant picker, sticker preview), placeholder overrides and declared actions. Emoji, sticker and GIF pages are thin compositions. The variant (skin-tone) picker is its own widget fed by the entry's variants. Extent and offset maths live in the viewport and its controller only. |
| Shell units | Pager, type tabs, bottom bar, search field. Page-switch and search transitions belong to the shell; open and close motion belongs to presentation; motion roles belong to foundation ([ADR 027](027-foundation-theme-glass-motion.md)). |
| Atlas host | The page that shows baked glyphs plans and creates the glyph atlas from the glyph list its `CollectionSource` supplies, and forwards scroll and visible-band events from the viewport controller to it. The pause signals (panel visible, panel opening) are published by the shell and presentation as `ValueListenable`s and wired by the host. |

Boundary items handled by presentation: search growing the panel
(`SearchOpened` and `SearchClosed` are the signal), IME hand-off on search
focus, and visibility, open and close, and persisted height or popup size.

## Amendment: where the field sits

The first cut drew the one field in the shell, above the pager, and the page's
strip in a column above the catalogue. Both stood still while the catalogue
scrolled, which dropped the behavior the panel shipped with: the category strip
slides away as the user reads on and returns as they read back, and the search
field is the first thing in the content, scrolls away with it and pins to the
top once search opens.

| Area | Decision |
| ---- | -------- |
| State | Unchanged. The shell controller owns the query, the focus intent and open or closed; the field is a projection of it, wherever it is drawn. |
| Placement | `PageCapabilities.searchPlacement`: `pinned` (the default; the shell draws the field above the pager) or `inline` (the page draws it). An inline page places a `PanelSearchField` among its own content; the shell gives it the controller and the selection toolbar through a `PanelSearchFieldScope` above the pager. The shell draws no field for an inline page. |
| Sticky header | `CatalogPage` draws the policy's strip and, for an inline page, the field over the catalogue and pads the catalogue by their extent. The geometry (offsets, hairlines, when the strip yields) is one pure class, `CatalogStickyHeader`, fed by the catalogue's scroll events. The strip's extent is declared by the policy (`stripExtent`), and section jumps land under it (`headerLandingInset`). |
| Field chrome | The leading icon morphs (magnifier, progress ring, back chevron that clears); the trailing control clears the query only. Search is left through the controller (back, the composer, another page), not by a control of the field. |
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

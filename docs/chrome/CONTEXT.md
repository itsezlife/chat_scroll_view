# Chat Chrome

The chrome around a chat's message list: the theme and glass it paints with,
the panel shell and its pages, how the panel is presented, and the composer.
Covers `chrome_foundation`, `panel_shell`, `panel_pages`, `panel_presentation`
and `chat_composer`. Does not cover the catalog viewport (see the
[Panel Catalog glossary](../panel-catalog/CONTEXT.md)) or content and asset
terms (see the [Content and Assets glossary](../content/CONTEXT.md)).

Decisions: [ADR 025](../adr/025-panel-shell-and-pages.md),
[ADR 026](../adr/026-composer-model.md),
[ADR 027](../adr/027-foundation-theme-glass-motion.md),
[ADR 028](../adr/028-panel-presentation.md),
[ADR 029](../adr/029-host-integration.md),
[ADR 031](../adr/031-localization-accessibility-and-input.md).

## Language

### Foundation

**Chrome palette**:
A small semantic color set (surface, onSurface, accent, separator, destructive, placeholder) with light, dark and custom constructors.
_Avoid_: Flat per-widget color class, `ThemeData` colors as the chrome source

**Token group**:
An immutable per-component token class (composer, panel, glass, actions) derived from the palette, with `copyWith` and `lerp`.
_Avoid_: One flat token class, `ThemeExtension`

**Chrome theme scope**:
Required, nestable, animatable theme scope. Lookup asserts without one; a nested scope overrides only the groups it supplies.
_Avoid_: Silent light fallback, theme parameter on every widget

**Glass material**:
A named glass preset (composer island, panel button, top panel) drawn by `GlassSurface`. Its colours are a token group; its shape of effect is fixed by the material.
_Avoid_: Flag-driven glass widgets

**Glass quality**:
Host policy (full liquid, frosted, flat, off) plus a lite-mode flag, combined with detected capabilities, the presence of a glass source and route motion to pick a strategy.
_Avoid_: A public renderer interface, per-widget quality flags

**Glass source**:
The content subtree that sampled glass frosts, marked by `GlassSource` inside a `GlassSourceScope`. One capture per frame is shared by every surface in the scope.
_Avoid_: Reading back the onscreen target for each surface

**Motion role**:
A named duration and curve (list transition, panel slide, search, popup show). A global speed scale implements reduce-motion and lite mode.
_Avoid_: Literal durations in components

**Chrome icon**:
A semantic icon id resolved through the foundation registry; hosts register painters for custom ids.
_Avoid_: Icon widgets named by shape in composer or tab descriptors

**Chrome strings**:
Required scope of grouped, host-provided strings, including plural functions. No production default language.
_Avoid_: Per-package label classes, hard-coded English defaults

### Panel shell and pages

**Panel shell**:
The host-independent panel: pager, type tabs and bottom bar around the active page, and the search field for a page that does not place it itself. No insets, no positioning.
_Avoid_: KeyboardPanel, catalog shell, emoji panel

**Panel arrangement**:
How the shell lays out its chrome for the way the user points: `touch` (tabs and page actions in one floating bottom bar that hides as the content is read; the page's strip and inline search field as a sticky header that slides away with the reading) or `pointer` (tabs above the search field, which is always the shell's; a bar of page actions that never hides on scroll and rises above the strip the page pins at the bottom; nothing a page draws slides). It is the one switch between those two layouts. Chosen by the presentation, given to the shell, read by pages through the scope. The platform is never read for it.
_Avoid_: Layout mode, platform layout, desktop / mobile shell

**Panel page**:
A registry entry: id, tab descriptor, builder and declared capabilities (search, bottom actions, top strip). The registry is open.
_Avoid_: Tab enum, allow bitset, plain widget page

**Sticky header**:
What a catalogue page draws over its content at the top under the `touch` arrangement (under `pointer` there is none): the strip, which slides away as the user reads on and returns as they read back, and, for a page that places its search field inline, the field, which is the first thing in the content, scrolls away with it and pins to the top once search opens. The page pads the catalogue by their extent; the geometry is `CatalogStickyHeader`.
_Avoid_: A header that stands still, a field the shell draws for a page that placed it itself

**Panel shell controller**:
The single source of truth for the selected page id and the search state (open, query, focus intent). Presentation visibility is a separate controller.
_Avoid_: One controller for shell and visibility, `adopt*` back-doors, `GlobalKey` control

**Focus intent**:
Part of the search state: whether the search field should hold focus. The field realises it; losing focus withdraws it without closing search.
_Avoid_: Focus node owned by the host, search open as a proxy for focus

**Panel presence**:
Two `ValueListenable`s (`package:listen`) the shell publishes for the host's pause signals: panel visible (on screen, including while moving) and panel opening (moving). The presentation controller reports them.
_Avoid_: A shell that reads its own visibility, pause flags inside pages

**Page controller registry**:
The per-page store of controllers (scroll offsets, loaded collections) that the shell controller owns, so a presentation switch restores page state.
_Avoid_: State kept in the page widget, `GlobalKey` reach-in

**Panel event**:
The one sealed outward effect type: content picked, backspace, action invoked, clear recents, page changed, search opened or closed. The host handles it and records recents.
_Avoid_: Callback bag, panel writing recents

**Page scroll activity**:
A typed drag, fling or idle signal a page publishes to drive bottom-bar hide and show.
_Avoid_: Reaching into page state through a key

**Catalog page**:
The shared page scaffold of `panel_pages`. Per-kind **page policies** supply layout presets, leaf tags, strips, long-press behaviour and declared actions.
_Avoid_: One page class per kind with copied viewport glue, a fully config-driven generic page

### Panel presentation

**Panel presentation**:
The sealed kind of host for the panel: keyboard replacement, anchored popup, docked section (a sheet later).
_Avoid_: Platform-only fixed pair, open registry of presentations

**Presentation policy**:
A pure-Dart `$Mobile` / `$Desktop` strategy owning open triggers, dismissal, sizing and animation roles. Defaults come from OS family and window class.
_Avoid_: `_vm` / `_js` forks, switching by last pointer kind

**Occupancy**:
A `ValueListenable` (`package:listen`) of the space a presentation takes (bottom, inline-end). The host aggregates it with composer extent into the viewport padding.
_Avoid_: A shared inset service every presentation reports into

**IME input port**:
The single host-fed entry for raw IME samples (height, animating, safe area).
_Avoid_: Foundation reading platform insets

**Presentation controller**:
The host-facing controller: sealed visibility state, show, hide, toggle, back, and strategy-aware intents. It wraps the shell controller.
_Avoid_: One controller class per presentation kind

**Auto-hide guard**:
True exactly while any `holdAutoHide()` hold is unreleased (a menu, a variant picker, a drag, a pointer button pressed inside the popup). The presentation controller counts the holds; the shell reports no such flag, and search focus is not a hold. A popup stays open while it holds, and hides 3 s after the last release if the pointer is away.
_Avoid_: Timers that ignore the guard, a flag the shell sets, search focus as a hold

**Anchored popup**:
The desktop and web presentation kind: the panel floats above the composer, opens at once on mouse hover over the toggle or on a click, hides when the pointer leaves it (at the next event pass from the toggle, after a short grace from the popup), and takes no layout space. It never takes focus: the composer keeps the caret however it was opened.
_Avoid_: Tooltip, dropdown, a popup that takes composer focus on any open, an idle timeout

**Popup hover area**:
What counts as the popup to the pointer: its card, a transparent gutter around it for the shadow, and a bridge down to the toggle, so there is no gap between the two where the pointer is over neither. A press in it is not an outside press.
_Avoid_: A gap between the toggle and the popup, hit-testing only the visible card

**Exempt region**:
A region of the host's screen, registered with the popup (the composer), where a press does not dismiss it. The toggle is exempt by itself.
_Avoid_: Dismissing on the press that is the user returning to type

**Panel toggle**:
The composer's one button for the panel. On the mobile kind it opens the panel and, while it is up, shows the keyboard glyph to give the keyboard back; on a desktop kind it opens, docks or undocks (per state) with one glyph in every state, drawn active while docked.
_Avoid_: A separate dock button, a second glyph for the open state on a desktop kind

**Dock preference**:
The user's choice to keep the panel docked at the inline end in a wide window. It lives in the `PreferenceStore`; the controller starts from it and writes every dock and undock to it.
_Avoid_: A flag held only in the widget, persistence by the presentation package itself

**Hand-off**:
The phases by which the keyboard-replacement panel and the soft keyboard exchange the bottom slot: the panel keeps its emptied sheet until the keyboard reports a settled reading, or closes cold after a timeout.
_Avoid_: Cross-fade between keyboard and panel, sample counters, wall-clock windows

**Panel height**:
The measured soft-keyboard height (content height without the safe area), remembered per orientation. The keyboard-replacement panel takes at least this height; a window-class default stands in until one is known.
_Avoid_: A fixed panel height, a height that includes the safe area

**Composer safe inset**:
The part of the bottom safe band that the keyboard presentation's occupancy has not covered yet: `max(0, band - occupancy)`. The host hands it to the composer as its bottom safe-area pad so the bottom of the window never steps.
_Avoid_: Adding the safe area to the occupancy a second time, peeling the safe area by platform

### Composer

**Composer spec**:
A host-built, declarative description of the composer: header, panel, actions, enabled and busy.
_Avoid_: Mode enum, controller-owned mode state

**Composer header** / **panel** / **actions**:
Orthogonal slots: what sits above the field, what occupies the input row, and the data list of action descriptors.
_Avoid_: One growing mode enum, hard-coded buttons

**Action descriptor**:
Id, semantic icon, placement, enabled and visible, tap handler, and a required semantic label.
_Avoid_: Button widgets passed in

**Composer controller**:
Input only: text, focus, selection, queries, field scroll and height, and insert, backspace and clear.
_Avoid_: Reply or edit state, stored message ids

**Composer extent**:
The height the composer view takes in its parent, published as data while it animates: island, header, margins and its own bottom safe-area pad, without any panel or keyboard below. The host adds the presentation occupancy and feeds the sum to the viewport padding.
_Avoid_: Reading the composer's render box from the host, a composer that knows insets

**Primary action**:
The one action of a composer spec that submit (Enter on a desktop policy) invokes. Flagged `primary` on its descriptor; submit does nothing when no primary action can be tapped.
_Avoid_: Looking an action up by id to submit

**Panel id**:
A `ComposerPanelId`: the name of what occupies the input row (the text field by default, or a host-resolved panel such as recording or restricted). An open set.
_Avoid_: A closed mode enum, the composer panel confused with the emoji panel

**Input query**:
The active token at the caret (kind, text, replace range, caret anchor) exposed for host-built suggestion panels.
_Avoid_: Suggestion panels inside the composer

### Host integration

**Composition root**:
The one place a host creates long-lived services in dependency order: KV adapter, stores, asset cache, data sources, resolver.
_Avoid_: Service locator, facade package

**Host contract**:
The README table of each package: what the host provides and what it must not do.
_Avoid_: Prose-only integration notes

**Inline embed**:
The generic painter-based seam in markdown bodies. A resolver maps scheme, id and alt to a size hint and a paint callback; the alt text is the copy, selection and accessibility text.
_Avoid_: `WidgetSpan` embeds, `ImageProvider` embeds

### Localization, accessibility and input

**Spoken name**:
The per-locale accessible name of a content item (CLDR `tts`).
_Avoid_: Using the keyword list as a label

**Windowed semantics**:
Semantic nodes only for the visible leaves plus a small overscan.
_Avoid_: A node per leaf, page-level semantics only

**Panel focus policy**:
What takes focus when the panel opens and where focus returns when it closes.
_Avoid_: Leaving focus where the toggle was

**Roving focus**:
Arrow-key focus movement across leaves and sections of the catalog.
_Avoid_: Hard-coded key handlers, tab stops on every leaf

## Superseded terms

Migration notes. These terms name code that the package set replaces.

| Old term | Now |
| -------- | --- |
| KeyboardPanel | Panel shell, with a panel presentation |
| KeyboardPanelController | Panel shell controller (page, search) and presentation controller (visibility) |
| KeyboardPanelStore, `keyboard_panel_*` prefs | `PreferenceStore` and `KeyValueStore`, string page id |
| KeyboardPanelAllow, KeyboardPanelTab | Panel page registry |
| KeyboardPanelLabels | Chrome strings |
| ChatChromeColors | Chrome palette and token groups |
| ChatComposerMode, ChatEnterView | Composer spec and slots |
| ChatBottomInsetController | Occupancy and the host's padding aggregation |

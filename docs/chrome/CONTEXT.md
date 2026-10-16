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
The host-independent panel: pager, type tabs, bottom bar and search field around the active page. No insets, no positioning.
_Avoid_: KeyboardPanel, catalog shell, emoji panel

**Panel page**:
A registry entry: id, tab descriptor, builder and declared capabilities (search, bottom actions, top strip). The registry is open.
_Avoid_: Tab enum, allow bitset, plain widget page

**Panel shell controller**:
The single source of truth for the selected page id and the search state (open, query, focus intent). Presentation visibility is a separate controller.
_Avoid_: One controller for shell and visibility, `adopt*` back-doors, `GlobalKey` control

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
An Observable of the space a presentation takes (bottom, inline-end). The host aggregates it with composer extent into the viewport padding.
_Avoid_: A shared inset service every presentation reports into

**IME input port**:
The single host-fed entry for raw IME samples (height, animating, safe area).
_Avoid_: Foundation reading platform insets

**Presentation controller**:
The host-facing controller: sealed visibility state, show, hide, toggle, back, and strategy-aware intents. It wraps the shell controller.
_Avoid_: One controller class per presentation kind

**Auto-hide guard**:
A shell-reported condition (variant picker open, search focused, drag in progress) that keeps a popup open.
_Avoid_: Timers that ignore the shell

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

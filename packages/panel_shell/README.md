# panel_shell

The host-independent **panel shell**: an open registry of **panel pages**, the
**panel shell controller** that owns the selected page and the search state,
and the widgets that project it (pager, type tabs, bottom bar, search field).
It positions nothing and reads no insets: where the panel sits, how tall it is
and what it does to the keyboard belong to a presentation. It depends on
`chrome_foundation` and `content_model` only (`scripts/check` enforces that)
and imports no concrete page.

Decisions: [ADR 025](../../docs/adr/025-panel-shell-and-pages.md) (shell and
pages), [ADR 031](../../docs/adr/031-localization-accessibility-and-input.md)
(strings, RTL, semantics, input), [ADR 020](../../docs/adr/020-package-topology.md)
(dependency direction). Glossary: [Chat chrome](../../docs/chrome/CONTEXT.md).

## Types

| Type | Role |
| --- | --- |
| `PanelPage`, `PanelTab`, `PageCapabilities`, `PageAction` | One registry entry: a stable id, the **tab descriptor** (semantic icon id and label key, never glyph or text), a builder, and what it declares (search, top strip, bottom actions). Every action carries a required semantic label. |
| `PanelShellController` | The single source of truth for the selected page id and `PanelSearchState`, as `Observable`s. One-way intents (`selectPage`, `openSearch`, `closeSearch`, `setQuery`, `invokeAction`, `handleBack`, ...) used by hosts and by the widgets' own gestures alike. No `adopt*`, no `GlobalKey`. Persists the page id as a string through `PreferenceStore`. |
| `PanelSearchState` | Open, query and **focus intent** in one snapshot. |
| `PanelPageHost`, `PageControllerRegistry`, `PanelPageController` | A page's whole connection to the shell (search state, `pick`, scroll and search reports) and the per-page registry the controller owns, so a presentation switch restores scroll offsets and loaded collections. |
| `PanelEvent` (`ContentPicked`, `BackspaceRequested`, `ActionInvoked`, `ClearRecentsRequested`, `PageChanged`, `SearchOpened`, `SearchClosed`) | The one sealed outward effect type, delivered on `controller.events`. The panel inserts nothing and writes no recents. |
| `PageScrollActivity` (`PageScrollDrag`, `PageScrollFling`, `PageScrollJump`, `PageScrollIdle`), `BottomBarVisibility` | The typed scroll report a page publishes and the rule that turns it into bottom-bar hide and show. No clock is read. |
| `DebouncedSearch<R>` | The shared search helper: debounce, generation (a newer text invalidates anything in flight) and stale-result handling, with a delayed `busy` flag. |
| `PanelShell`, `PanelTabDisplay` | The widget: search field above a pager, bottom bar floating over it. A projection of the controller; it keeps no state of its own. |
| `PanelSelectPageIntent`, `PanelSearchIntent`, `PanelShortcuts`, `PanelFocusPolicy`, `PanelAnnouncer` | Intents and actions with a default shortcut map, focus on open and restore target, and the announcement seam. |
| `package:panel_shell/testing.dart` | `FakePanelPage`, `FakePageControllerRegistry`, `FakePanelAnnouncer`, `PanelShellTestScope`, `runPageControllerRegistryContract` and `PanelSemanticsRule`. Tests only. |

## Using it

```dart
final controller = PanelShellController(
  pages: [emojiPage, stickerPage],        // PanelPage entries, in tab order
  preferences: preferenceStore,           // loaded PreferenceStore
);
controller.events.addListener((event) => switch (event) {
  ContentPicked(:final key, :final kind, :final source) =>
      composer.insert(key) /* and recents.record(key, kind: kind, source: source) */,
  BackspaceRequested() => composer.backspace(),
  ClearRecentsRequested(:final kind) => confirmThen(() => recents.clear(kind: kind)),
  ActionInvoked() || PageChanged() || SearchOpened() || SearchClosed() => null,
});

// under ChromeThemeScope + ChromeStringsScope:
PanelShell(controller: controller);
```

- **Search.** The shell owns the one field, the query, focus and the open
  state. A page declares `search: true`, reads `host.search` and maps the query
  to its own results (`DebouncedSearch` carries the debounce and the stale-reply
  rule), then reports `host.reportSearchProgress` and
  `host.reportSearchResultCount`. The query survives page switches. Closing
  search forgets the query.
- **Bottom bar.** The shell owns the bar: type tabs plus the selected page's
  declared actions. A page reports `PageScrollDrag` / `PageScrollFling`
  deltas, `PageScrollJump` before a programmatic scroll and `PageScrollIdle`
  at rest. The bar is held hidden while search is open, shows on every page
  change and when it takes focus.
- **Presence.** `controller.visible` and `controller.opening` are the two
  pause signals of work that must not run while the panel is hidden or moving
  (the glyph atlas bake, for one). A presentation controller reports them with
  `updatePresence`; the host wires the observables to whatever it pauses.
- **Escape and back.** The shell's `DismissIntent` action closes search while
  it is open and otherwise forwards the intent to the nearest enclosing
  `Actions`, so a popup that hosts the shell closes on the second press. The
  popup must bind Escape itself (`Shortcuts` looks only at the action nearest
  the focused widget). `handleBack()` is the same step for a system back button.
- **Directional layout.** Tabs, the action row and the pager mirror in a
  right-to-left layout; page content is never mirrored by the shell. Text in
  the fixed-height pill and search field is scaled up to 1.3x.

## Host contract

| The host provides | The host must not |
| --- | --- |
| A `ChromeThemeScope` and a `ChromeStringsScope` above `PanelShell` (both required). A `ChromeMotionScope` is optional; map `MediaQuery.disableAnimations` to `ChromeMotionSpeed.instant` there. | Expect a default theme or language. Reduce motion is only the scope's speed. |
| A loaded `PreferenceStore` and an ordered `List<PanelPage>` with unique ids, each tab label key answered by `PanelStrings.tabLabel` and each action label resolvable from `ChromeStrings`. | Expect the shell to import a concrete page, or to persist anything but the selected page id. |
| One handler on `controller.events` that inserts content, edits its input on `BackspaceRequested` and calls `RecentsStore.record` / `clear`; plus haptics, if it wants them. | Expect the panel to write recents, insert content or give haptic feedback. |
| Presence, through the presentation controller's `updatePresence`, if it wires pause signals. | Call `updatePresence` from a page or widget of the shell. |
| Bottom padding through `MediaQuery`: the shell lifts the bar by it and passes pages the bar's height on top. | Expect the shell to size itself, read the keyboard or touch an inset. |
| An enclosing `Shortcuts` / `Actions` for `DismissIntent` when the shell sits in a popup. | Expect Escape to reach the popup without one. |
| A `searchContextMenuBuilder` if the search field needs a selection toolbar (paste on touch); the field is built on `EditableText` and needs no Material ancestor. | Expect a toolbar without one. |
| `PanelSemanticsRule.expectLabelled(strings, pages)` in a test, to fail on a page, tab or action whose label resolves to nothing. | Import `testing.dart` from production code. |

## Not in this package

The catalog viewport and page scaffold (`panel_catalog`, `panel_pages`), opening
and closing, the keyboard and insets (`panel_presentation`), the composer, and
any recents or data source. Inline emoji selection and the variant picker live
in the pages that own the content.

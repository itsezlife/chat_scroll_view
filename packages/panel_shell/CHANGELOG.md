# Changelog

All notable changes to `panel_shell` are documented in this file. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Changed

- `ContentPicked` says what the content is and which recents list it is
  filed in apart: `kind` is the content's own kind, as in every other event
  about content (`ContentCopyRequested.kind`), and the new `recentsKind`
  (`kind` when omitted) names the list, as `RecentRemoveRequested` and
  `ClearRecentsRequested` do. A host records a pick under `recentsKind`, so a
  page with one list for several kinds (the emoji page's custom emoji among
  the unicode ones) needs no inference from the key.
- Source-breaking: `PanelPageHost.pick` takes `recentsKind`; an
  implementation of the host adds the parameter.

- Source-breaking: `runPageControllerRegistryContract(...)` in `testing.dart`
  is `PageControllerRegistryContract.run(...)`.

### Changed

- `PanelBackgroundScope`: the shell's background for a page's bands
  (transparent on glass).
- `PanelShell.sectionTabsBar` (`PanelSectionTabsBar.label`, the default, or
  `section`): the underline as wide as the label, rounded on top.
- A press on the focused search field raises its keyboard again.
- Under `pointer` the page switcher is the reference desktop client's tabs
  slider (equal sections, a sliding accent bar, labels following it, a ripple,
  choice on release, a line under it), and choosing a page slides the pages
  over 200 ms. The pill stays in the bottom bar under `touch`.
- A press on a search field that kept its focus when search let go of it asks
  for focus again (`requestSearchFocus`).
- `PanelShell.background`: what the shell paints behind its column (null for
  the panel tokens' background); a presentation on glass passes transparent.
- Source-breaking: `PanelArrangement.narrowsEmptySearch` and `searchPlacementOf`
  are gone. An open search with no query keeps the whole catalogue under both
  arrangements, and a page's declared search placement is its placement: an
  `inline` field under `pointer` is the page's, scrolls with the grid and does
  not pin (`PanelArrangement.pinsSearchWhenOpen` is touch-only).
- The search field's trailing control shows only with text, under both
  arrangements, and only clears: it no longer closes search when the field is
  empty.
- The pointer arrangement does not offer backspace
  (`PanelArrangement.offersAction`), and builds no bar when a page has no
  other action. `PanelBottomBar` takes the `actions` it shows.
- The type tabs pill under `pointer` scales down as a whole when the column is
  narrower than it, instead of overflowing.

### Added

- `PanelPageHost.holdAutoHide()` returning a `PanelPageHold`, and
  `PanelShellController.autoHideHolds` (a `ValueListenable<int>`): pages hold a
  presentation's auto-hide while a menu or picker is open; the host forwards
  the count to its presentation. Source-breaking for an implementer of
  `PanelPageHost` (the fake in `panel_pages/testing.dart` is updated).
- `PanelPageHost.requestCopy` and `requestRemoveRecent`, and the matching
  `PanelEvent`s `ContentCopyRequested(key, kind)` and
  `RecentRemoveRequested(key, kind)`. Source-breaking for an exhaustive `switch`
  over `PanelEvent` and for an implementer of `PanelPageHost`.
- `PanelArrangement.usesContextMenu` (true under `pointer`).
- `PanelArrangement` (`touch`, `pointer`), `PanelShell(arrangement:)` and
  `PanelArrangementScope`, which hands the arrangement to the pages below the
  shell (`touch` outside any shell). `touch` is what the shell always did.
  Under `pointer` the type tabs sit above the search field, the floating bar
  holds the page actions only and is hidden by an open search alone (a
  scroll report, a wheel step included, never hides it), and it rises above
  the strip a page pins at the bottom. The shell keeps the safe inset for
  itself there and tells pages the bar's room only. Goldens for `pointer`
  were generated on macOS.
- `PanelPageHost.reportBottomExtent`, kept per page, and
  `PanelShellController.bottomExtent` (the selected page's). Source-breaking
  for a class that implements `PanelPageHost`; `FakePanelPageHost` records
  the reports.
- `BottomBarVisibility(hidesOnScroll:)`: a bar that scroll activity does not
  hide.
- `SearchPlacement` and `PageCapabilities.searchPlacement`. A page that
  declares `inline` draws the search field itself (a `PanelSearchField` under
  the `PanelSearchFieldScope` the shell provides above its pager), among its own
  content, so it can scroll away with it and pin when search opens; the shell
  draws none for it. `pinned`, the default, is the previous behavior. Only
  `touch` honours `inline`: `PanelArrangement.searchPlacementOf` answers
  `pinned` for `pointer`, where the shell draws the field below the type tabs
  whatever the page declared. `PanelArrangement.headerSlidesAway` says whether a
  page's strip and inline field may slide away (`touch`).
- `PanelSearchField` and `PanelSearchStateIcon` are exported. The field's
  controller is optional (the scope's is used), and it takes a `shadow`
  listenable for the hairline under it.

### Changed

- The search field looks and acts as the panel's did: the leading icon morphs
  from magnifier to progress ring (while a search is in flight) to a back
  chevron that clears the query (once it settled); the trailing control is a
  clear control that shows only with text. **Under `touch` the cancel control that
  closed search is gone**: search is left through the controller (`closeSearch`,
  `handleBack`), as the panel's back handling already did. Existing code that
  tapped the field's "Cancel" to close search closes it through the controller
  instead.
  Under `pointer`, which has no back gesture, the trailing control stays the
  cancel control it was: it shows while search is open, the first press empties
  the query and the second closes search. `FakePanelPage` with an inline
  placement draws its field only where the arrangement lets a page place it.
- The progress ring is the morphing icon's arc, which follows its own ticker;
  the `loop` motion role is no longer read by this package.

### Changed

- Change notification is `package:listen` (`listen: ^1.0.1`), not
  `content_model`'s removed `Observable` family. `selectedPageId`, `search`,
  `searchBusy`, `visible` and `opening` are `ValueListenable`s (import
  `package:listen/listen.dart`; Flutter's type of that name is a different
  one), `PanelPageHost.reselected` is a `Listenable`, and `events`,
  `scrollActivity` and `searchResultCounts` are synchronous broadcast
  `Stream`s: `listen` and cancel the subscription instead of
  `addListener` / `removeListener`. An event a listener publishes
  (selecting a page from a `SearchOpened` handler) is delivered once the event
  in flight has reached every listener, still before the intent returns. The
  same callback added twice is called twice. `BottomBarVisibility` ignores
  input after `dispose`.

### Fixed

- The pager's starting page is known to the type tabs before the pager mounts,
  so tabs mounted ahead of the pager (the `pointer` arrangement) are not marked
  dirty during the build.

- The search field's progress ring turns on the `loop` motion role and stands
  still under an instant speed, instead of spinning at a literal 900 ms.

### Added

- `PanelPage` registry entries (`PanelTab`, `PageCapabilities`, `PageAction`)
  and `PanelPageHost`, the page's connection to the shell.
- `PanelShellController`: selected page id (persisted as a string through
  `PreferenceStore`) and `PanelSearchState` as `ValueListenable`s, one-way intents,
  the per-page controller registry, `events` (one sealed `PanelEvent`), and
  `visible` / `opening` presence listenables for the host's pause signals.
- `PanelShell` with the pager, type tabs, bottom bar and search field;
  `PageScrollActivity` and `BottomBarVisibility` replace the clock-based
  scroll heuristics of the old panel; `DebouncedSearch` is the shared search
  helper.
- `PanelSelectPageIntent`, `PanelSearchIntent`, `PanelShortcuts`,
  `PanelFocusPolicy` and `PanelAnnouncer`.
- `testing.dart`: `FakePanelPage`, `FakePageControllerRegistry`,
  `FakePanelAnnouncer`, `PanelShellTestScope`,
  `runPageControllerRegistryContract` and `PanelSemanticsRule`.

### Changed

- `PanelPageHost` gains `panelVisible` and `panelOpening` (the presence the
  presentation reported, for a page that paces work on it) and
  `releaseSearchFocus` (a page asks for the soft keyboard to go when the user
  takes hold of its content). Implementers of the interface must add them.
- `PanelShell.deferSearchField` mounts the search field one frame after the
  first, for a cold mount that spreads its cost over frames.

### Fixed

- Under `ChromeMotionSpeed.instant` the search field slot no longer throws
  `RenderAnimatedSize was mutated in its own performLayout`: a zero duration
  skips `AnimatedSize`.

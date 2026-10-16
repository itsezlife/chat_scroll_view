# Changelog

All notable changes to `panel_shell` are documented in this file. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added

- `PanelPage` registry entries (`PanelTab`, `PageCapabilities`, `PageAction`)
  and `PanelPageHost`, the page's connection to the shell.
- `PanelShellController`: selected page id (persisted as a string through
  `PreferenceStore`) and `PanelSearchState` as `Observable`s, one-way intents,
  the per-page controller registry, `events` (one sealed `PanelEvent`), and
  `visible` / `opening` presence observables for the host's pause signals.
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

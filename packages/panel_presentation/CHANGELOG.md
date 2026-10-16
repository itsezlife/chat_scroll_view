# Changelog

All notable changes to `panel_presentation` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Added

- Sealed `PanelPresentation` kinds (`KeyboardReplacement`, `AnchoredPopup`,
  `Docked`), the sealed `PanelVisibility` state and `PanelOccupancy`.
- `PanelPresentationPolicy` with `$Mobile` and `$Desktop` variants, defaulting
  from `PanelOsFamily` and `PanelWindowClass`, overridable per call.
- `PanelPresentationController`: `show` / `hide` / `toggle` / `handleBack`,
  `dock` / `undock`, `anchor`, `updateWindow`, published occupancy, auto-hide
  guard and interactions; drives `PanelShellController.updatePresence`.
- `PanelPresentationStrategy` and `PanelPresentationView`, which projects the
  visibility through the strategy of the active kind.
- `ImeInputPort` / `ImeInput` / `ImeSample` and `PanelClock`.
- `testing.dart`: `FakeImeInput`, `ManualPanelClock`,
  `FakePresentationStrategy`, `runPresentationPolicyContract` and
  `runImeInputPortContract`.
- `AnchoredPopupStrategy`, the desktop and web popup: mouse-only hover open
  through `AnchoredPopupToggleRegion`, leave (300 ms) and idle (3 s) hide on
  the `PanelClock`, auto-hide guard, outside-press and Escape dismissal,
  bottom-end anchoring that mirrors in RTL, policy-sized height, scale and
  fade from the bottom-end corner with the `popupShow` / `popupHide` roles,
  focus in and back to the composer, zero occupancy.
- `AnchoredPopupStyle`, `AnchoredPopupLayout`, `AnchoredPopupActions`,
  `AnchoredPopupShortcuts`, `AnchoredPopupToggleIntent`.

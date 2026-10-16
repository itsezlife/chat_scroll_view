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
- `KeyboardReplacementStrategy`: the panel replaces the soft keyboard in the
  bottom slot. Hand-off state machine (`KeyboardSlot`, `KeyboardSlotState`)
  with a fallback timeout, animated occupancy on the `listTransition` role,
  search expansion, safe area and the nav-bar scrim, and `composerSafeInset`.
- `KeyboardHeightStore` over a `KeyValueStore`: keyboard height per
  orientation, sanity floor, window-class defaults in
  `KeyboardReplacementTuning`.

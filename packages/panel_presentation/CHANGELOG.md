# Changelog

All notable changes to `panel_presentation` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Added

- `KeyboardReplacementTuning.sheetCornerRadius` (29): the keyboard-replacement
  sheet has rounded top corners, seen at rest.

### Documented

- `ImeSample.height` counts the bottom safe area as part of the keyboard. A host
  whose platform reports the keyboard without it adds it back.

### Changed

- Change notification is `package:listen` (`listen: ^1.0.1`), not
  `content_model`'s removed `Observable` family: `occupancy`, `state`, `window`,
  `anchorRect`, `samples` and the like are `ValueListenable`s (the
  `package:listen` type, not Flutter's), `PanelPresentationController
  .interactions` and `KeyboardSlot.changes` are `Listenable`s, and
  `ValueObservableBuilder` becomes `ListenValueBuilder`. `dispose` of the
  strategies, `ImeInput` and the fakes stays idempotent, and
  `DockedStrategy` drops a late occupancy report after its disposal.

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
- `AnchoredPopupStrategy`, the desktop and web popup: mouse-only hover open
  through `AnchoredPopupToggleRegion`, leave (300 ms) and idle (3 s) hide on
  the `PanelClock`, auto-hide guard, outside-press and Escape dismissal,
  bottom-end anchoring that mirrors in RTL, policy-sized height, scale and
  fade from the bottom-end corner with the `popupShow` / `popupHide` roles,
  focus in and back to the composer, zero occupancy.
- `AnchoredPopupStyle`, `AnchoredPopupLayout`, `AnchoredPopupActions`,
  `AnchoredPopupShortcuts`, `AnchoredPopupToggleIntent`.
- `DockedStrategy` and `DockedStyle`, the desktop and web docked section:
  end-edge placement that mirrors in RTL, `panelSlide` motion, animated
  inline-end occupancy, focus back to the composer on close.
- `PanelPresentationController(preferences:)`: the dock preference is read
  from and written to a `PreferenceStore`, and follows changes made elsewhere;
  `toggleDock()`; a docked section narrowed into a popup docks again when the
  window is wide.

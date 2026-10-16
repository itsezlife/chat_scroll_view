# Changelog

All notable changes to `panel_presentation` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Changed

- Source-breaking: the dock is a standing section ([ADR 028](../../docs/adr/028-panel-presentation.md)
  amendment). `PanelPresentationPolicy.canDock`, `defaultKind` and `resolve`
  take the `PanelWindow` instead of its class; a window has the room for a
  dock when the content keeps 380 and the dock is at least 292. The dock shows
  by itself while preferred and fitting, goes (no popup) when the window
  narrows, returns when it widens, and is dismissed by no gesture
  (`dismissalsFor(Docked)` is empty; `handleBack` leaves it up).
- `DockedStyle.width` is optional: a dock nobody dragged is the policy's
  narrowest.

### Added

- Resizing: `PanelPresentationPolicy.dockMinWidth`, `dockMaxWidth`,
  `dockMinChatWidth`, `dockResizeExtent` and `dockWidthIn`;
  `PanelPresentationController.resizeDock`, `endDockResize` and `dockWanted`; a
  6 px strip on the docked view's start edge; `DockWidthStore` (the
  `dockWidths:` argument) keeps the width across sessions.
- `AnchoredPopupStyle.edgeGap` and `AnchoredPopupLayout.gap`: the room between
  the popup and the composer's top and end edges.

### Added

- `KeyboardReplacementTuning.sheetCornerRadius` (29): the keyboard-replacement
  sheet has rounded top corners, seen at rest.
- `KeyboardReplacementStrategy.animating`: whether the slot is moving, so a
  host can wait for search to collapse back to the panel's height before it
  hands the slot to the keyboard.
- `KeyboardReplacementTuning.settleConfirmation` (80 ms): how long a settled
  reading of a raised keyboard must stand, with no other reading after it,
  before the slot takes the keyboard to be up.

### Documented

- `ImeSample.height` counts the bottom safe area as part of the keyboard. A host
  whose platform reports the keyboard without it adds it back.

### Changed

- **The hand-off to the keyboard waits for a confirmed reading.** A settled
  reading of a raised keyboard counts once it has stood for
  `settleConfirmation` with no other reading after it, before a close and
  during the hold alike. Before, one settled reading handed over, and the
  lone full-height reading a crossing hide and show report between zeros
  dropped the composer by the keyboard's height and raised it again. A
  panel that replaces the keyboard drops the confirmation (it asks that
  keyboard down), and a hand-off that times out over a keyboard still
  reading settled up hands over instead of closing cold. A legitimate
  hand-off ends up to 80 ms later, while the emptied sheet sits under the
  keyboard at its height.
- **The anchored popup never takes focus when it opens.** Before, a click-opened
  popup moved the caret from the composer into the panel (a hover-opened one
  did not). Now no open does: the composer keeps the caret, the search field is
  focused only when the user clicks into it, and the panel is still reachable
  by Tab. Closing hands focus to `composerFocus` only if the popup held it.
  Code that relied on Escape working with no focus anywhere after opening by
  click must now have focus in the composer (the host wraps it in
  `AnchoredPopupActions`) or in the popup.
- **The hover machine follows the reference client.** Leaving the toggle hides
  at the next event pass (it used to wait 300 ms), cancelled by entering the
  popup; the popup's hover area now includes a transparent gutter and a bridge
  down to the toggle, so the pointer never crosses a gap. Leaving the popup
  hides after 300 ms, or at the next pass while it is still appearing. Entering
  the popup during the fade-out shows it again. After a hold is released with
  the pointer away it hides after 3 s.
- **There is no idle timer any more.** An interaction in the panel with the
  pointer away used to hide the popup after 3 s; it arms nothing now, so a
  popup opened by click or key and never hovered stays until dismissed.
  `PanelDismissal.idle` is `PanelDismissal.afterHold` and
  `PanelPresentationPolicy.idleDelay` is `afterHoldDelay`.
- **Search focus is not a hold.** `autoHideGuard` is true exactly while a
  `holdAutoHide()` is unreleased. A popup with search focused and the pointer
  away now hides by the leave rule.
- A pointer button pressed inside the popup holds auto-hide until it is
  released, wherever the pointer goes meanwhile (a scrollbar drag, a
  selection).
- A press on the toggle, in the popup's own hover area or in a registered
  exempt region no longer dismisses the popup.
- Stale pointer flags are cleared: the touch flag when the popup is hidden, the
  toggle flag when the toggle leaves the tree under the pointer. The hover
  open no longer records which kind of open it was (nothing reads it).
- `popupHide` is 200 ms (was 150) in `chrome_foundation`.

- Change notification is `package:listen` (`listen: ^1.0.1`), not
  `content_model`'s removed `Observable` family: `occupancy`, `state`, `window`,
  `anchorRect`, `samples` and the like are `ValueListenable`s (the
  `package:listen` type, not Flutter's), `PanelPresentationController
  .interactions` and `KeyboardSlot.changes` are `Listenable`s, and
  `ValueObservableBuilder` becomes `ListenValueBuilder`. `dispose` of the
  strategies, `ImeInput` and the fakes stays idempotent, and
  `DockedStrategy` drops a late occupancy report after its disposal.

### Added

- `AnchoredPopupExemptRegion`, `AnchoredPopupStyle.hoverGutter` (default 10)
  and `AnchoredPopupLayout.outset`.
- Tests for `holdAutoHide` reentrancy: independent holds in any release order,
  idempotent release, a hold across a hide and show, inert after dispose.
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

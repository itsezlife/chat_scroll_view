# ADR 028: Panel presentation strategies (mobile vs desktop and web)

`panel_presentation` decides where the panel appears and how it opens, closes
and takes space. A sealed set of presentation kinds is chosen by a pure-Dart
`$Mobile` / `$Desktop` policy, each kind publishes the space it occupies as an
`Observable`, and one controller owns visibility. This supersedes the
inset-controller parts of [ADR 007](007-keyboard-panel-controller.md).

**Status**: Accepted  
**Date**: 2026-10-16  
**Relates to**: [ADR 007](007-keyboard-panel-controller.md) (superseded in part), [ADR 012](012-cross-platform-selection-policies.md) (same policy shape), [ADR 025](025-panel-shell-and-pages.md), [host chrome insets](../architecture/14-host-chrome-insets.md) (amended by this ADR)

## Decided

| Area | Decision |
| ---- | -------- |
| Kinds and policy | Sealed `PanelPresentation`: `KeyboardReplacement` (in-flow, takes the bottom slot), `AnchoredPopup`, `Docked`. A pure-Dart policy in the [ADR 012](012-cross-platform-selection-policies.md) shape (`$Mobile`, `$Desktop`, no `_vm` / `_js` forks) owns open triggers, dismissal, sizing and animation roles. The default follows OS family (iOS and Android: `$Mobile`; desktop and web: `$Desktop`) and an adaptive window class; the host may override per call. A sheet or modal kind can be added later. |
| Occupancy | Each presentation publishes an `Observable` occupancy (bottom extent, inline-end extent). `KeyboardReplacement`: animated `max(IME, panel)`. `AnchoredPopup`: zero. `Docked`: inline-end width. The host adds composer extent and `occupancy.bottom` into the viewport `bottomPadding` and applies `inlineEnd` in layout. |
| IME input | The host feeds raw IME samples (height, animating, safe area) through one input port, from `MediaQuery` or a keyboard-insets package. The mobile strategy applies filtering, hold and hand-off internally. Foundation reads no platform insets. |
| Controller | One `PanelPresentationController`: sealed visibility state (`hidden`, `showing`, `shown`, `hiding`, plus the active kind), `show`, `hide`, `toggle`, `handleBack`, and strategy-aware intents (`waitForIme`, anchor, dock and undock). Commands commit when unbound. It wraps the `PanelShellController` and reacts to `SearchOpened`, `SearchClosed` and `PageChanged`. |
| Switching | Selected page, search state, per-page scroll offsets and loaded collections live in controllers (shell and per-page), not widget state. A switch rebuilds the shell subtree and restores everything. No `GlobalKey` reparenting. The transition is a motion role. |
| AnchoredPopup | Copied from Desktop `TabbedPanel`. Hover over the toggle opens it; a click toggles. Leaving hides after 300 ms and a 3 s idle delays a hide. The shell reports `preventAutoHide` while the variant picker is open, search is focused or a drag is in progress. Esc and outside click dismiss. It anchors bottom-end of the composer rect, which the host supplies. Height is 0.75 times the window height clamped to 278..640. It scales and fades from the bottom-end origin (`popupShow` / `popupHide` roles). Hover-open applies to mouse only; touch is click only. |
| Docked | Copied from Desktop `TabbedSection`. A persisted `PreferenceStore` choice. The toggle moves a popup to docked when the window class is wide, and undock closes it. Occupancy is the inline-end width. |
| KeyboardReplacement | Android `WindowInsetsStateHolder` and the iOS height table are the references. Occupancy animates with the `listTransition` role. Panel height comes from the measured IME height persisted per orientation (sanity floor, device-class default). Explicit IME and panel hand-off states have a fallback timeout (Android: 1 s). `SearchOpened` grows the panel to an expanded height. Safe area and navigation bar are added inside the strategy. `handleBack` closes search first, then the panel. The host sets the composer's `softKeyboard` from presentation visibility. |

## Why

- Desktop (`tdesktop` tabbed panel and compose controls): the toggle is an event filter on the popup with hover open, click toggles, hide timers of 300 and 3000 ms, `preventAutoHide` from the selector, bottom-right anchoring and ratio sizing. The third-section docked mode is a persisted setting when it fits and the layout is not one column. The selector is borrowed between host and panel.
- Android arbitrates `max(system, ime, inApp)` with one animator, persists the keyboard height and has explicit hand-off states. iOS uses a per-device height table and no measured height.
- The old inset controller was 412 lines of heuristic IME filtering, and panel state sat in four holders with `adopt*` back-doors.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Two fixed platform presentations; an open registry of presentations | A fixed pair cannot add a sheet; an open registry cannot be switched on exhaustively |
| Presentation owning the whole bottom stack (composer, panel, IME, viewport link); a shared inset service every presentation reports into | The host already aggregates; desktop popups have no inset |
| One controller class per presentation kind; merging visibility back into the shell controller | The host would hold one controller per kind; visibility and page selection change for different reasons |
| `GlobalKey` reparenting; switching that resets the panel | Loses scroll offsets, search and loaded collections |

## Related

- Glossary: [Chat chrome](../chrome/CONTEXT.md)

# panel_presentation

How the panel is **presented**: where it appears, what opens and dismisses it,
and how much space it takes. A sealed set of **panel presentation** kinds is
chosen by a pure-Dart **presentation policy**, one **presentation controller**
owns the visibility and wraps the `panel_shell` controller, and each kind
publishes its **occupancy** as a `ValueListenable` (`package:listen`) the host aggregates. It depends
on `panel_shell`, `chrome_foundation` and `content_model` only
(`scripts/check` enforces that) and never sees page content or data payloads.

Decisions: [ADR 028](../../docs/adr/028-panel-presentation.md) (presentation),
[ADR 025](../../docs/adr/025-panel-shell-and-pages.md) (the shell it wraps),
[ADR 012](../../docs/adr/012-cross-platform-selection-policies.md) (the
`$Mobile` / `$Desktop` policy shape),
[ADR 031](../../docs/adr/031-localization-accessibility-and-input.md) (input).
Glossary: [Chat chrome](../../docs/chrome/CONTEXT.md). Constructor
requirements: `PanelPresentationController` takes the `shell` and optionally
`policy`, `strategies`, `window` and `preferences`; `KeyboardReplacementStrategy`
takes `ime`, `heights` and `window`. Host layout:
[host chrome insets](../../docs/architecture/14-host-chrome-insets.md).

## Types

| Type | Role |
| --- | --- |
| `PanelPresentation` (`KeyboardReplacement`, `AnchoredPopup`, `Docked`) | The sealed kinds. Values only; what draws a kind is a strategy. |
| `PanelPresentationPolicy` (`PanelPresentationPolicy$Mobile`, `PanelPresentationPolicy$Desktop`) | Plain-Dart decisions: the default kind from OS family, window class and dock preference, whether hover opens, how each kind is dismissed (`PanelDismissal`), the 300 ms leave and 3 s after-hold delays (`PanelDismissal.afterHold`), popup height (0.75 of the window, clamped 278..640) and the motion role of showing, hiding and switching. A host override of the kind wins. |
| `PanelOsFamily`, `PanelWindowClass`, `PanelWindow` | The inputs of the policy: Android and iOS are mobile, every other OS and the web are desktop; compact below 600 px, medium below 840, expanded (wide) from 840. |
| `PanelPresentationController` | Owns the sealed `PanelVisibility` (`hidden`, `showing`, `shown`, `hiding`, each with its kind), `show` / `hide` / `toggle` / `handleBack`, `anchor`, `dock` / `undock`, `updateWindow`, the published `occupancy`, the `autoHideGuard` (true while a `holdAutoHide()` is unreleased; search focus is not one) and the `interactions` signal. Reports presence to the shell with `updatePresence`. Intents commit when no view is mounted. |
| `PanelOccupancy` | The space taken, `bottom` and `inlineEnd`, both non-negative. |
| `PanelPresentationStrategy`, `PanelStrategyContext` | What draws one kind and publishes its occupancy. The three kinds' strategies are registered with the controller; a kind without one takes no space and draws nothing. |
| `PanelPresentationView` | The mounted widget: projects the visibility through the strategy of the active kind and keys it by kind. Keeps no state; switching kinds restores everything from the shell controller. |
| `AnchoredPopupStrategy`, `AnchoredPopupStyle` | The desktop and web popup: floats above the composer, hover opens at once, leaving hides, Escape and an outside press dismiss, scale and fade from the bottom-end corner, zero occupancy, never takes focus. The style carries the width, corner radius, shadows, start scale and `hoverGutter`; none but the gutter have a default from a reference client. |
| `AnchoredPopupToggleRegion`, `AnchoredPopupExemptRegion` | The first wraps the host's toggle; only a mouse entering it opens the popup, touch and stylus click, and a press on it never dismisses. The second marks a region (the composer) where a press does not dismiss. |
| `AnchoredPopupActions`, `AnchoredPopupShortcuts`, `AnchoredPopupToggleIntent` | `DismissIntent` steps back (search first, popup second), the toggle intent toggles, `PanelSearchIntent` shows the panel and focuses search. |
| `AnchoredPopupLayout` | Where the popup sits: bottom on the anchor top, end edge on the anchor end edge, kept inside the window. |
| `DockedStrategy`, `DockedStyle` | The desktop and web docked section: full height on the end edge (the left in RTL), slides in with the `panelSlide` role, publishes its visible width as `inlineEnd` occupancy so the host can shrink the chat. No hover, idle or outside-press dismissal; Escape only closes search. The style carries the width and an optional separator line. |
| `ImeInputPort`, `ImeInput`, `ImeSample` | The single port raw soft-keyboard samples enter by (height, animating, bottom safe area). The height counts the safe area as part of the keyboard: a platform that reports the keyboard without it (the Android inset plugin) has the band added back by the host. |
| `KeyboardReplacementStrategy` | The mobile strategy: the panel takes the place of the soft keyboard under the composer. Publishes `occupancy` (animated `max(keyboard, panel)`, safe area included), `state` (the hand-off phase) and `composerSafeInset`. |
| `KeyboardSlot`, `KeyboardSlotState` | The hand-off state machine behind the strategy and its animated extent: `idle`, `opening`, `replacing`, `open`, `closing`, `handOffToIme`. Driven by `advance(elapsed)` and a `PanelClock`; no ticker, no wall clock. |
| `KeyboardHeightStore`, `PanelOrientation` | The keyboard height remembered per orientation in a `KeyValueStore` (sanity floor 180, never lowered by one sample). |
| `KeyboardReplacementTuning` | Default panel heights by window class, the 175 search expansion, the 1 s hand-off timeout, the cold-open delay, the sheet's top corner radius (29). |
| `KeyboardNavBarFade` | The scrim over the bottom safe band of the sheet. |
| `PanelClock`, `PanelTimer` | The one way presentation code waits; `PanelClock.system` in the app, a manual clock in tests. |
| `package:panel_presentation/testing.dart` | `FakeImeInput`, `ManualPanelClock`, `FakePresentationStrategy`, `runPresentationPolicyContract`, `runImeInputPortContract`. Tests only. |

## Using it

```dart
final presentation = PanelPresentationController(
  shell: shellController,               // the PanelShellController
  strategies: [keyboard, popup, docked], // one per kind you support
  window: PanelWindow(width: size.width, height: size.height),
);

// Layout: the host adds the composer and the occupancy itself.
presentation.occupancy.addListener(() {
  final occupancy = presentation.occupancy.value;
  bottomPadding.value = composerExtent + occupancy.bottom;
  // occupancy.inlineEnd is applied in layout, mirrored in RTL.
});

presentation.toggle();                  // the composer's emoji button
final consumed = presentation.handleBack(); // search first, then the panel

// In the tree, in the box the host reserved for the panel:
PanelPresentationView(controller: presentation);
```

- **Kinds are data, strategies are widgets.** The policy decides; the
  controller holds the state; a strategy builds the panel for its kind (it
  mounts `PanelShell(controller: view.controller.shell)`), animates it and
  calls `view.motionSettled()` when `showing` or `hiding` ends.
- **Commit when unbound.** With no view mounted, `show` lands in `shown` and
  `hide` in `hidden` at once. With one mounted they pass through `showing` and
  `hiding`. Unmounting the last view settles whatever is moving.
- **Switching.** `show(kind: ...)` on a visible panel swaps the kind in
  place. Page, query, focus intent and every page's scroll offset live in the
  shell controller and its page registry, so the new subtree reads them back.
  No `GlobalKey` moves a widget.
- **Occupancy.** The occupancy of the active kind's strategy; while hidden,
  of the kind the policy would open. A keyboard strategy keeps publishing the
  soft keyboard's height then, so the host never adds it a second time.
- **Docking.** `dock()` records the preference and, in a wide window, moves a
  popup into the docked section; `undock()` closes the section; `toggleDock()`
  is the dock button's action. Pass the host's `PreferenceStore` as
  `preferences:`: the controller starts from its `dockPreferred`, writes every
  `dock()` / `undock()` to it (a failed write is reported through
  `FlutterError.reportError`, the choice stays in memory) and follows a change
  made elsewhere. Without a store the preference is in memory, seeded by the
  `dockPreferred` flag. A docked section that the window narrows falls back to
  a popup and docks again when the window is wide, unless the user changed
  something in between.
- **Docked section.** Register `DockedStrategy(style: ..., composerFocus: ...)`.
  The view publishes the section's visible width as `occupancy.inlineEnd`
  while it slides, so apply it as end padding (mirrored in RTL) on the chat
  viewport. With no mounted view the occupancy is zero. Opening does not take
  focus from the composer; focus inside returns to `composerFocus` on close.
  The box the view fills must be bounded and at least `DockedStyle.width`
  wide.
- **Auto-hide guard and holds.** `holdAutoHide()` is the one seam through
  which anything keeps a self-dismissing popup open (an open menu or variant
  picker, a drag, a button pressed inside the popup). Holds are counted and
  independent: release them in any order, release is idempotent, the guard
  notifies on the first hold and the last release only, a hold taken after
  `dispose` is inert. The guard is true exactly while a hold is unreleased;
  search focus is not a hold. `interactions` signals every shell event for
  hosts; no popup times out on it.
- **Anchored popup.** Register `AnchoredPopupStrategy(style: ..., composerFocus:
  ...)` and wrap the toggle in `AnchoredPopupToggleRegion`. A mouse over the
  toggle opens the popup at once. Leaving the toggle hides it at the next event
  pass, unless the pointer has entered the popup by then: the popup's hover
  area (card, `hoverGutter` around it, and a bridge down to the toggle) leaves
  no gap. Leaving the popup hides it after 300 ms, at the next pass while it is
  still appearing; entering either while it fades out shows it again. A held
  guard defeats those, and releasing the last hold with the pointer away hides
  after 3 s. There is no other idle timer. A press outside the popup hides it,
  except on the toggle, in the popup's own hover area and in an
  `AnchoredPopupExemptRegion`; Escape closes search first and then the popup.
  The popup never takes focus; closing hands focus to `composerFocus` only if
  the popup held it (search was focused). A popup last pressed by touch or
  stylus has no leave or after-hold delay.
- **Back.** `handleBack` closes search through the shell first, then hides the
  panel. A panel that is already hiding still consumes the press.

## Keyboard replacement

```dart
final ime = ImeInput();                       // the host feeds this
final window = ValueNotifier(PanelWindow(width: w, height: h)); // package:listen
final heights = await KeyboardHeightStore.open(keyValueStore);
final keyboard = KeyboardReplacementStrategy(
  ime: ime,
  heights: heights,
  window: window,
);

// Every MediaQuery / keyboard-insets change, honestly flagged:
ime.report(ImeSample(
  height: viewInsets.bottom,
  animating: keyboardIsMoving,
  safeAreaBottom: viewPadding.bottom,
));

// Layout: composer extent + max(safe area, keyboard.occupancy.value.bottom)
// into the bottom padding, and the composer's bottom safe area is
// keyboard.composerSafeInset.
```

- **One slot, two holders.** The bottom space is `max(keyboard, panel)`,
  safe area included. A panel that replaces the keyboard claims the slot at
  once, at least as tall as the keyboard; the keyboard collapsing or
  glitching beneath it changes nothing.
- **Paced mount.** The strategy mounts the shell with the search field one
  frame after the page when the panel grows into a free slot, and all at once
  when it replaces the keyboard (chrome would pop in over content already on
  screen). `keyboardIsUp` is the same fact for a host's own pages: read it when
  a page mounts to decide whether to pace its chrome the same way.
- **Hand-off to the keyboard.** `hide(waitForIme: true)` keeps the emptied
  sheet and the occupancy until the keyboard is *confirmed up*: a settled
  reading (`animating` false, height up) that stands for
  `KeyboardReplacementTuning.settleConfirmation` (80 ms) with no other
  reading after it. A hide and a show that cross report one settled reading
  at full height between zeros, which the confirmation lets pass. A keyboard
  the panel has just replaced was asked down and must read up again. With no
  confirmation within one second the panel closes cold, or hands over to a
  keyboard that still reads settled up. Hosts must report `animating`
  honestly.
- **Panel height.** The measured keyboard height (content height without the
  safe area), remembered per orientation, never below the 180 floor, with a
  window-class default when nothing is known.
- **Search.** Opening search in the shell grows the panel by 175, capped by
  the window; closing it shrinks it back. `handleBack` closes search first,
  then the panel.
- **Safe area.** The sheet is the slot, the content height plus the band the
  host reported when at rest, with the shell seeing that band as its bottom
  padding and a scrim over it. `composerSafeInset` is the part of the band the occupancy has
  not covered yet, so the bottom of the window is `max(safe band, occupancy)`
  with no step.
- **Frame cost.** The shell widget is built once; a frame of the motion costs
  the layout of the sheet, which follows the slot, and no build (a headless
  test asserts it). Frame
  budgets on a device are open: the table in
  [the QA notes](../../docs/panel-presentation/qa-keyboard-handoff.md) holds
  the numbers once someone measures them.

## Host contract

| The host provides | The host must not |
| --- | --- |
| A `PanelShellController` (it owns the shell, the presentation never disposes it) and one `PanelPresentationStrategy` per kind it supports. | Expect a kind without a strategy to draw or take space. |
| The window size, from `MediaQuery.sizeOf`, through `updateWindow`, again on rotation and resize. | Expect the controller to read `MediaQuery` or any platform inset. |
| Raw soft-keyboard readings through one `ImeInputPort` handed to the keyboard strategy. | Filter, debounce or smooth them, or feed a second port. |
| The composer rectangle through `anchor` for a popup. | Expect the popup to find the composer by itself. |
| The aggregation of `occupancy` with its composer extent into the viewport padding, and `inlineEnd` in layout. | Add the keyboard height a second time while the occupancy already contains it. |
| The loaded `PreferenceStore` (from `content_model`), passed as `preferences:`; its `dockPreferred` is the persisted dock choice. | Persist the choice a second time, or expect `dock()` to persist without a store. |
| The docked section's width in `DockedStyle`, `inlineEnd` applied to the chat viewport's layout, and a box for the view that is bounded and at least that wide. | Expect the docked section to cover the chat, to be dismissed by hover or an outside press, or a default width from a reference client. |
| For the keyboard strategy: every keyboard reading through the `ImeInputPort` with an honest `animating` flag and the bottom safe area, the window through a `ValueListenable<PanelWindow>` from `package:listen`, a `KeyboardHeightStore` over a `KeyValueStore`, and `composerSafeInset` as the composer's bottom safe area. | Read `SystemChannels` or platform insets in the strategy's place, report a settled reading while the keyboard moves, or add the keyboard height to the occupancy again. |
| The popup's `AnchoredPopupToggleRegion` around the composer's panel button (placed under the popup), an `AnchoredPopupExemptRegion` around the composer, a click handler on that button (`toggle()`, or `dock()` / `undock()` on a desktop kind), and `AnchoredPopupActions` with `AnchoredPopupShortcuts.standard` above the composer so Escape and a toggle shortcut work while focus is there. The popup width, corners, shadow and gutter in `AnchoredPopupStyle`. | Expect the popup to take focus, to be dismissed by a click back into the composer, or a default popup size from a reference client. |
| `MediaQuery.disableAnimations` mapped to `ChromeMotionSpeed.instant`, and `holdAutoHide()` taken for as long as a menu or variant picker is open. | Expect the controller to read reduce motion or to know about the picker. |
| `Esc` and outside-press bindings in any other strategy (the popup binds its own). | Expect the controller to bind keys. |
| `dispose()` of the controller, the shell and the strategies, each by their owner, in either order. | Expect the controller to dispose the shell or the strategies. |

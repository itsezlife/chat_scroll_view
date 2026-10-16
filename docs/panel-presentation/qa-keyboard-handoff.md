# QA: keyboard replacement open and hand-off

The keyboard-replacement presentation (`panel_presentation`,
[ADR 028](../adr/028-panel-presentation.md)) is judged on two numbers and a
set of visual checks: the frames a cold open and a keyboard hand-off drop, and
whether the bottom of the window ever jumps.

Only the reference devices gate: a mid-range Android phone and an iPhone.
Other devices and desktop runs are indicative; label their numbers non-gating.

## What the tests already prove

Headless, in `packages/panel_presentation/test/keyboard/`:

- **State machine** (`keyboard_slot_test.dart`): open from nothing, open over
  the keyboard, close cold, close to the keyboard, the one-second fallback,
  search expansion with the keyboard up, rotation, measuring and persisting
  the keyboard height, the safe band. Time is driven by hand, so the
  assertions are exact.
- **Frame cost** (`keyboard_replacement_strategy_test.dart`, "rebuilds nothing
  under the sheet"): across the whole motion the shell and its pages are built
  once. A frame of the open costs the clip's relayout and the occupancy
  listeners of the host; the sheet is a fixed-height box clipped by the slot,
  so its content never reflows.
- **Pause signals**: the shell is told `opening` for the whole `showing` phase
  and `visible` while the panel is on screen, so the atlas bake and the
  paced mount keep their signals.

What headless cannot tell is how long a real frame takes on a device.

## Before you start

- Display fixed at its top refresh rate, cool, on a charger, screen on,
  nothing else in the foreground. Profile build; debug timings say nothing
  about raster cost.
- Release the soft keyboard once and show it again so a keyboard height is
  stored; clear the app's storage to see the window-class default instead.
- Measure with the panel acceptance harness (`example/tool/panel_perf.dart`,
  suites `panel_open` and the chat variants) and write the numbers into the
  table at the end. Where the host has not ported a scenario, record a
  timeline with `flutter run --profile` and DevTools: count frames over one
  vsync budget between the tap and the end of the slide.

## Checklist

Each item: pass, or fail with the observed jump.

1. **Cold open.** Keyboard hidden, tap the panel button. The page appears
   under the composer, nothing moves for about 50 ms, then the slot grows over
   250 ms. The composer rises with it, no frame shows the page half-built
   beyond the paced mount.
2. **Keyboard to panel.** Keyboard up, tap the panel button. The panel is on
   screen at once; the composer does not move; the keyboard disappears
   beneath. No frame where the slot is smaller than the keyboard was.
3. **Panel to keyboard.** Panel up, tap the text field. The emptied sheet
   stays while the keyboard rises, the composer does not drop and rise again,
   and the sheet gives way when the keyboard has taken the slot. Repeat 20
   times quickly.
4. **Panel to keyboard, keyboard blocked.** With the keyboard suppressed
   (hardware keyboard attached, or the field unable to focus), the sheet
   closes cold after one second and the composer settles at the bottom.
5. **Hide the keyboard after a hand-off.** After 3, dismiss the keyboard: the
   slot follows it down with no snap back to the old height.
6. **Search expand.** Panel up, tap search. The panel grows by about 175 and
   the field takes focus; the keyboard rises under the grown panel with no
   change of the occupancy. Back closes search and shrinks the panel; a second
   back closes the panel.
7. **Rotation.** Open the panel, rotate both ways. The panel takes the height
   stored for each orientation; first time in an orientation it takes the
   default.
8. **Safe band.** On a phone with a gesture bar and one with a three-button
   bar: the composer's bottom padding disappears as the slot covers the band,
   the scrim shows only over a three-button bar, and the bottom of the window
   never shows a gap.
9. **Reduce motion.** With the platform animation scale at zero the panel
   lands at once, in every item above.

## Results

| Device | Build | Cold open: frames over budget / raster p99 | Hand-off: frames over budget | Items 1-9 |
| --- | --- | --- | --- | --- |
| Mid-range Android | profile | not measured | not measured | not run |
| iPhone | profile | not measured | not measured | not run |

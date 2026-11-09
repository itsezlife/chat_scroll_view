# bulletins

**Bulletins**: short notices shown over a surface for a few seconds ("Copied",
"Stickers removed — Undo"). One is visible per surface and a new one replaces
it. An Undo bulletin commits its change when it leaves by any way but Undo.
Depends on `chrome_foundation` only.

Decisions: [ADR 045](../../docs/adr/045-bulletins.md). Glossary:
[Chat chrome](../../docs/chrome/CONTEXT.md) (*Bulletin*, *Bulletin
controller*, *Bulletin host*, *Bulletin policy*, *Commit on leave*, *Bottom
obstruction*).

## Types

| Type | Role |
| --- | --- |
| `Bulletin` | The value: message, optional title, leading, action, duration, placement, body tap, spoken label, links (`BulletinLink` ranges of the message). `effectiveDuration` applies the default duration rule when none is named (Undo: prolonged; under 20 characters: short; else long). |
| `BulletinLeading` | The content kind: `icon`, `animation(source)`, `thumbnail(source)`, `countdown`, `custom`. |
| `BulletinAction` | `undo(onUndo:, onCommit:)` or `button(label:, onPressed:)`. |
| `BulletinDuration` | `short`, `long`, `prolonged`, `untilDismissed`, `exactly(Duration)`. |
| `BulletinController`, `BulletinHandle`, `BulletinExit` | The surface's slot. `show` returns a handle; every handle closes once with an exit; `closed` completes with it. Commit on leave runs `onCommit` once for every exit but `undone`. The timer starts at `markEntered`; `pause` holds it, `resume` restarts it. |
| `BulletinClock` | Time for the controller; `ManualBulletinClock` in `testing.dart`. |
| `BulletinPolicy` (`$Android`, `$IOS`, `$Desktop`) | Layout, text and motion values per platform family; `forPlatform` / `current` pick one. Not sealed: extend a stock family to change a value. `minWidth` makes the card as wide as its content (desktop); `transitionAt` moves a card by where it sits; `passesThroughWhenInert` lets pointers through a card with nothing to press. |
| `BulletinTransition` | `slide` (spring), `timedSlide(enter:, exit:)`, `fadeScale`, `fade({enter, exit})`; a timed one without its own `MotionSpec` (or, for `fadeScale`, its own `BulletinFadeScaleMotion`: fade and scale timed apart) reads the `bulletinShow` / `bulletinHide` motion roles. |
| `BulletinIOS`, `BulletinCountdownIOS` | The iOS card's builders for `BulletinPolicy.ios()`: `BulletinIOS.builders(animation:, thumbnail:)` draws the blurred card, the leading at the card's edge, the 17 action label that dims while pressed, and the countdown whose digits tick every half second. |
| `BulletinHost` | Mounts a controller over a surface: layout inside the obstruction, enter and exit, press and swipe, announcement, `surfaceGone` on unmount. |
| `BulletinBuilders`, `BulletinView`, `BulletinCard` | How a card is drawn: `frame`, `content`, `leading`, `action`, and the host's `animation` and `thumbnail` resolvers. Each null part uses its `stock*` builder. |
| `BulletinMessage` | The message text with its links (owns their tap recognizers) after an optional prefix. |
| `DesktopBulletinBuilders` | The desktop toast's builders (`create(animation:, ...)`): one wrapping text block with a bold title line, up to 16 lines, an icon slot in place of the start padding. Pair with `BulletinPolicy.desktop()` and `BulletinTokens.desktop`. |
| `BulletinPolicyContract` | `testing.dart`: the suite every policy passes. |

## Host contract

| Step | What the host does |
| --- | --- |
| Scopes | A `ChromeThemeScope` (the `bulletin` token group) and a `ChromeStringsScope` (`ChromeStrings.bulletin`) above the host; a `ChromeMotionScope` with `ChromeMotionSpeed.instant` for reduce-motion. |
| Mount | One `BulletinController` per surface, created and disposed with it; `BulletinHost(controller:, obstruction:, child:)` over the surface's content. |
| Obstruction | A `ValueListenable<EdgeInsets>` of what covers the edges (composer, its safe inset and the keyboard at the bottom). Null: the `MediaQuery` padding and keyboard inset. |
| Undo | Apply the change, show `Bulletin(action: BulletinAction.undo(onUndo:, onCommit:))`. Exactly one of the two runs. |
| Look | Replace the policy (extend a stock family) and the builders; colours through `BulletinTokens`. |

```dart
final applied = library.apply(edit, undoWindow: const Duration(seconds: 30));
bulletins.show(
  Bulletin(
    title: strings.stickersRemoved,
    message: strings.stickersRemovedInfo(title),
    leading: const BulletinLeading.countdown(),
    action: BulletinAction.undo(
      onUndo: () => applied.undo(),
      onCommit: applied.commit,
    ),
  ),
);
```

# Composer editable

Ubiquitous language for text selection chrome and gesture entry in
`composer_editable`: the composer's editable, a copy of Flutter's text field
with the Telegram composer's selection behaviour.

## Language

### Handles and magnifier

**Handle settle**:
On touch platforms, after handle drag ends the moving handle overlay animates
(~250ms `easeOut`, no overshoot) from the last pointer position to the
**extent caret anchor** (where the moving selection end sits when the finger
lifts), then one chrome refresh applies live handle types/orientations. Logical
selection offsets are already final on UP; settle is visual-only.
_Avoid_: Instant snap (strict AOSP `filterOnTouchUp`); overshoot on settle;
animating selection offsets on release; settling toward the fixed-base endpoint
when the grabbed physical handle’s layer link sits on the opposite side

**Frozen handle chrome**:
From handle drag **DOWN** until **handle settle** completes (~250ms easeOut
after UP), visual handle chrome is frozen: (1) the **grabbed** physical handle
(start or end overlay) stays the moving overlay — it does not swap when
selection inverts; (2) **start/end handle types** (left/right orientation) stay
as at drag start; (3) after settle finishes, one refresh applies live types
and caret anchors. Logical selection offsets and highlight still update live
during drag. Telegram composer parity: avoids inward-facing overlap when
handles cross.
_Avoid_: Live orientation flip on invert mid-drag; moving overlay swapping to
the other handle widget when `extent` crosses `fixedBase`; treating invert as
instant handle-type refresh

**Finger-tracked handle**:
On **touch platforms**, for every **`ExtendedTextField`** (the editable only,
not read-only selectable text): during handle drag the **moving** handle overlay follows `pointer + grab offset` on **both
axes** (finger / scrcpy touch). Grab offset is the finger→handle delta frozen
at drag start (AOSP `mTouchToWindowOffset` / Telegram `movingOffsetX/Y`).
Selection offsets still update by character hit-test from that same touch path.
While **frozen handle chrome** is active, overlay position is **extent-anchored**
and the **fixed** handle is **fixedBase-anchored** via follower delta against
its physical layer link (layer links may sit on the opposite end under the
invert model). **On release**, the moving overlay **settles** to the extent
caret (see **Handle settle**). **Desktop platforms** keep stock caret-anchored
handle motion. The grabbed handle keeps its size; only the appear animation
scales (overshoot from the center).
_Avoid_: Caret-anchored drag on touch; line-anchored Y only during drag;
instant snap with no settle on release; jumping overlay to raw pointer on DOWN;
per-screen opt-in flags; bubble / read-only selection in the same pass;
uncorrected fixed handle following the moving extent; a drag scale on the
grabbed handle (no Telegram source)

**Pointer-line magnifier**:
During handle drag on touch **`ExtendedTextField`**, the magnifier
focal **X** follows the pointer clamped to the current visual line; focal **Y**
is the vertical center of that line (AOSP `Magnifier` / `Editor` rule). Motion
uses **AOSP-style ~100ms settle** (`MagnifierMotionAnimator` parity):
continuous while dragging; **Y** gets a short interpolation mainly on line
jump; **X** tracks with the same rate. Not caret-anchored; not free pointer Y;
not bubble `TextSelectionHelper` 100/200ms split. The moving handle stays
visible under the loupe.
_Avoid_: Caret-anchored loupe; finger Y for loupe; desktop loupe forks; keeping
bubble 100/200ms rates for composer parity

**Composer selection chrome**:
Selection in the chat **composer** (`EditTextBoldCursor` → stock
`android.widget.Editor`). Handles, magnifier, and drag physics come from
**AOSP `Editor.HandleView` / `SelectionHandleView`**, not from
`TextSelectionHelper`. Telegram only themes handles (`setHandlesColor`) and
cursor (`EditTextBoldCursor`); no custom drag overlay in Telegram Java.
_Avoid_: Assuming composer reuses `TextSelectionHelper`; porting bubble
selection code to the composer

**Bubble selection chrome**:
Selection in **message bubbles** (chat list, articles). Custom
`TextSelectionHelper` overlay: appear/hide (`handleViewProgress`), magnifier
(`lastX`, 100/200ms settle), direction settling, `movingOffsetX` grab offset.
Handle **draw** is still caret-anchored (`getPrimaryHorizontal`); magnifier is
finger-tracked.
_Avoid_: Treating bubble helper as the composer reference

### Gesture entry

**Universal field gestures**:
Enter and dismiss semantics for selection on **touch platforms** (`android`,
`iOS`, and `fuchsia`) are defined once in `composer_editable` and apply to every
`ExtendedTextField` — including **finger-tracked handle** drag/settle
and magnifier pointer tracking. Desktop/web targets (`linux`, `macOS`, `windows`)
keep stock Flutter editable gesture defaults — their UX is pointer/keyboard
driven and is not forced through the touch enter matrix.
_Avoid_: Per-screen gesture forks; forcing the touch enter matrix onto desktop

**Touch platforms** / **Desktop platforms**:
Touch = `TargetPlatform.android` | `iOS` | `fuchsia`. Desktop = `linux` |
`macOS` | `windows` (including Flutter web when it resolves to those targets).
_Avoid_: Pointer-kind forks as the primary split (unless a later ADR says so)

**Long-press enter**:
On touch platforms: press-and-hold past the long-press delay on a non-newline
character expands to a word (or atomic span), shows handles, and starts the
one-touch phase. On desktop platforms, long-press follows stock Flutter defaults
(including platform-specific cursor / floating-cursor behavior). **iOS keeps
its caret gesture:** a long-press on a focused, editable field moves the caret
with the floating cursor, as the platform's own text views do; a field without
focus, or a read-only one, takes the word-and-one-touch path.
_Avoid_: Treating long-press as the only enter path on touch; forcing one-touch
onto desktop; selecting a word on a focused iOS field

**Double-tap enter**:
On touch platforms: second tap within the double-tap timeout and slop, while not
already in selection mode, starts the same word/span selection as long-press
enter, then ends the one-touch phase immediately (no finger-down expand). Resets
the tap clock so a third tap does not chain another enter. There is no triple-tap
→ paragraph path on touch. On desktop platforms, triple-tap follows stock Flutter
(paragraph / line / select-all); double-tap may share the common `selectWord`
path (near stock).
_Avoid_: Stock double-tap as an unrelated parallel pipeline on touch; consecutive
double-tap storms on touch; applying the no-triple-tap rule to desktop

**Capture**:
Pre-selection press tracking: touch-down inside the text area arms a delayed
long-press enter; moving past touch slop cancels without selecting. Double-tap
enter short-circuits capture by starting selection on the second down.
_Avoid_: Soft cancel, pending select

**One-touch phase**:
Finger still down after long-press enter only. Magnifier is suppressed; the
selection may still expand under the finger; lifting ends the phase and shows
actions. Double-tap enter skips this phase.
_Avoid_: Initial drag, first press selection

**Direction settling**:
Right after word enter, ignore handle extents strictly inside the selected word
until the finger exits past `start` or `end`, then lock which end is moving.
While settling freezes **selection offsets**, the **moving** handle overlay and
pointer-line magnifier still follow the pointer (composer / AOSP parity).
_Avoid_: Handle settle, invert lock; freezing overlay during settling

**Tap dismiss**:
A single tap while selection mode is active clears the non-collapsed selection,
hides handles/toolbar, and places a collapsed caret at the tap position.
_Avoid_: Tap to reselect; leaving a non-collapsed range after dismiss

**Idle caret tap**:
A single tap while not in selection mode places (or moves) the collapsed caret
at the tap position without entering selection mode. On iOS, a finger tap on
the collapsed caret of a focused, editable field instead toggles the toolbar
(the Paste menu), as in the platform's text views.
_Avoid_: Treating every tap as enter

**Editable-field defaults**:
On desktop platforms, the stock Flutter editable gesture matrix is the default
(including long-press and triple-tap). On touch platforms, unnamed edges not
covered by universal enter/dismiss (handle drag after idle selection, toolbar
toggles, etc.) still follow ordinary editable-field defaults; universal
enter/dismiss wins on conflict for touch only.
_Avoid_: Inventing one-off gesture forks per screen

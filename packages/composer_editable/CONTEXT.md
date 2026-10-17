# Extended text selection

Ubiquitous language for text selection geometry and gesture entry in
`extended_text`.

## Language

### Highlight and handles

**Hybrid selection highlight**:
Selection chrome that paints completed visual lines full-width (`max`) and the
content end line glyph-tight (`tight`), except when an exclusive end uses
empty-edge (then the content end line is `max`).
_Avoid_: Stock selection width, BoxWidthStyle.max everywhere

**Content end line**:
The visual line that holds the last selected character (`selection.end - 1`, or
the last painted offset after omitting a hard-break `\n`). For a content-less
exclusive end, it is the line that receives the synthesized trailing box.
_Avoid_: Active line (ambiguous when exclusive end sits on the next line), extent line

**Completed line**:
A fully selected visual line before the content end line; painted full-width.
_Avoid_: Finished line, middle line

**Exclusive line end**:
A selection whose exclusive `end` sits at the start of the following visual
line (soft wrap or hard break). Selected glyphs usually remain on the previous
line; see content-less exclusive end when they do not.
_Avoid_: Line-break selection, wrap selection

**Soft-wrap exclusive end**:
Exclusive line end where the previous character is not `\n`.
_Avoid_: Soft break end

**Hard-break exclusive end**:
Exclusive line end where the previous character is `\n`; paint omits that
newline so no leading box appears on the following line.
_Avoid_: Newline exclusive end

**Content-less exclusive end**:
Exclusive line end whose painted range on the content end line contains no
glyphs (typical hard-break case: selection covers only the omitted `\n`).
Chrome synthesizes a trailing box on the content end line: upstream = tight
anchor at the end of the last glyph; downstream = max to line end + empty-edge
handle. Offsets stay unchanged; never leave hybrid boxes empty for this case.
_Avoid_: Empty selection (collapsed caret); treating omit-`\n` as “no chrome”

**Empty-edge handle**:
End handle placed with downstream affinity at `selection.end` on the following
visual line. Used only when exclusive-end affinity is [TextAffinity.downstream]
at an exclusive line end. Upstream keeps the handle on the content end line at
the last glyph.
_Avoid_: Far-right handle on empty trailing space (that is max paint, not the
handle rule)

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
On **touch platforms**, for every **`ExtendedTextField`** consumer (composer /
editable only — not read-only `flutter_md` / `SelectionArea`): during handle
drag the **moving** handle overlay follows `pointer + grab offset` on **both
axes** (finger / scrcpy touch). Grab offset is the finger→handle delta frozen
at drag start (AOSP `mTouchToWindowOffset` / Telegram `movingOffsetX/Y`).
Selection offsets still update by character hit-test from that same touch path.
While **frozen handle chrome** is active, overlay position is **extent-anchored**
and the **fixed** handle is **fixedBase-anchored** via follower delta against
its physical layer link (layer links may sit on the opposite end under the
invert model). **On release**, the moving overlay **settles** to the extent
caret (see **Handle settle**). **Desktop platforms** keep stock caret-anchored
handle motion. Drag grab scale grows from the handle **anchor corner** toward
the finger; appear scale may still overshoot from center.
_Avoid_: Caret-anchored drag on touch; line-anchored Y only during drag;
instant snap with no settle on release; jumping overlay to raw pointer on DOWN;
per-screen opt-in flags; bubble / read-only selection in the same pass;
uncorrected fixed handle following the moving extent; drag scale from center

**Pointer-line magnifier**:
During handle drag on touch **`ExtendedTextField`** (editable only), magnifier
focal **X** follows the pointer clamped to the current visual line; focal **Y**
is the vertical center of that line (AOSP `Magnifier` / `Editor` rule). Motion
uses **AOSP-style ~100ms settle** (`MagnifierMotionAnimator` parity):
continuous while dragging; **Y** gets a short interpolation mainly on line
jump; **X** tracks with the same rate. While the loupe overlaps the **moving**
handle, that handle is hidden (AOSP `handleOverlapsMagnifier`); fixed handle
stays visible. Not caret-anchored; not free pointer Y; not bubble
`TextSelectionHelper` 100/200ms split.
_Avoid_: Caret-anchored loupe; finger Y for loupe; always showing handle under
loupe; desktop loupe forks; keeping bubble 100/200ms rates for composer parity

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

**Exclusive-end affinity**:
[TextSelection.affinity] as the mode of the exclusive line end at
`selection.end`: upstream = content end line tight + handle on last glyph;
downstream = content end line max + empty-edge handle on the following line.
When the exclusive end is the **moving extent** of a handle drag, hit-test
affinity updates it. When the exclusive end (`selection.end`) is the **fixed
base** of a handle drag (start or end handle; `extent <= fixedBase` and that
offset is an exclusive line end), affinity is preserved from drag-start —
moving the other end must not flip empty-edge ↔ tight. A fixed start that
merely sits at a visual line start does not freeze affinity.
Non-collapsed [TextSelection.==] ignores affinity in Flutter — affinity-only
updates are forced through the editable/controller.
_Avoid_: Extent affinity (ambiguous once the exclusive end is fixed base);
start-handle-only preserve (both handles share the rule); treating any
line-start fixedBase as exclusive-end preserve; gesture Y bias (optional
future); line bias

**Paint selection cache**:
Hybrid boxes stored on [ExtendedRenderEditable] only for the editable’s current
`selection` (offsets + affinity). Paint and warm-cache write this; subrange
queries (magnifier, line probes) must not overwrite it.
_Avoid_: One shared cache for every `getBoxesForSelection` range

**Ephemeral hybrid boxes**:
Hybrid (and synthesize) computed for a range that is not the paint selection;
returned to the caller and discarded — never stored as the paint cache.
_Avoid_: Stale paint after magnifier/subrange rebuild

### Gesture entry

**Universal field gestures**:
Enter and dismiss semantics for selection on **touch platforms** (`android`,
`iOS`, and `fuchsia`) are defined once in `extended_text` and apply to every
`ExtendedTextField` consumer — including **finger-tracked handle** drag/settle
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
(including platform-specific cursor / floating-cursor behavior).
_Avoid_: Treating long-press as the only enter path on touch; forcing one-touch
onto desktop

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
at the tap position without entering selection mode.
_Avoid_: Treating every tap as enter

**Editable-field defaults**:
On desktop platforms, the stock Flutter editable gesture matrix is the default
(including long-press and triple-tap). On touch platforms, unnamed edges not
covered by universal enter/dismiss (handle drag after idle selection, toolbar
toggles, etc.) still follow ordinary editable-field defaults; universal
enter/dismiss wins on conflict for touch only.
_Avoid_: Inventing one-off gesture forks per screen

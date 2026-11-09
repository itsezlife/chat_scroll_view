# swipe_pager

A horizontal **pager** for any surface with swipeable pages. Its swipe is
claimed only past a slop and a direction rule, so a slightly diagonal drag
over a page's vertical list scrolls the list rather than changing the page.
It depends on the Flutter SDK only.

Decisions: [ADR 020](../../docs/adr/020-package-topology.md) (where it sits).

## Types

| Type | Role |
| --- | --- |
| `SwipePager` | The widget: `pageCount` pages from `pageBuilder`, one or two on screen at a time. Swipes with touch, stylus and trackpad pans (`dragDevices`; add `PointerDeviceKind.mouse` for mouse drags). Mirrors in right-to-left. Offers scroll left / right semantics actions, and pages with the arrow keys while it holds the focus itself (`focusable`). |
| `SwipePagerController` | `page` (rested on or settling to), `position` (continuous), `animateTo` (540 ms ease out quint by default; a far page slides in next to the current one), `jumpTo`, typed `addPageListener` / `addPositionListener`. One pager at a time; detached, `animateTo` jumps. |
| `SwipePagerPhysics` | The claim slop (0.3 cm, about 18.9 px) and the cross-axis slop (8 px) that decide a swipe, the fling that starts one under the slop, the release rule (a third of a page, or a fling of 3500 physical px/s) and the settle (quintic ease out, 150..600 ms). |
| `SwipePagerKeepAlive` | Which pages stay built off screen: `all`, `none`, `recent(n)`. A kept page is offstage, out of focus and semantics, with its tickers off. |

## Contracts

- A drag is the pager's when, on the straight line from the down position,
  it moves `claimSlop` along the axis before `crossAxisSlop` across; it lets
  the drag go otherwise. The claim slop is never under the platform drag
  slop, so a nested scroller along the same axis claims its own drags first.
- A nested horizontal scroller at its edge in the drag's direction (start
  edge dragged toward the start, end edge toward the end, as it is laid out,
  so mirrored right to left) does not keep the drag: on the move it would
  claim on, the pager takes the arena when none of the scrollers under the
  down can scroll that way and the pager can move, then swipes by the rule
  above. Scrollers are found by their sliver viewport in a hit test of the
  page; a `SingleChildScrollView` is not seen and keeps its drags, as does
  a scroller when the pager cannot move that way.
- There is no overscroll: the first and last page do not swipe outward. A
  drag moves at most one page; a touch on a settling pager catches it. A
  slide from `animateTo` is not interrupted by a swipe.
- With `MediaQuery.disableAnimations`, settles and slides land at once.
- Pages are identified by index; reordering them needs a new pager key.

## Rules and values

The defaults of `SwipePagerPhysics`, rule by rule. Physical px are device
pixels; logical px are the units the pager lays out in.

| Rule | Behaviour | Value (`SwipePagerPhysics`) |
| --- | --- | --- |
| Claim slop | A drag is claimed once it moves this far along the axis, when it is further along the axis than across. | 0.3 cm, about 18.9 logical px at 160 per inch (`claimSlop`) |
| Vertical list wins | A vertical list in the page starts scrolling past the platform touch slop and takes the drag; the pager lets go of its pending claim. Decided on the straight line from the down. | 8 logical px across the axis (`crossAxisSlop`) |
| Nested horizontal scroller | A child that scrolls horizontally under the finger keeps the gesture; one at its edge consumes nothing and the pager takes the drag. The claim slop is never under the platform drag slop, so one that cannot scroll the drag's way loses the arena to the pager on the move it would claim on. | Scrollers are found by their sliver viewport in a hit test of the page |
| Edges | No claim outward past the first or last page; no overscroll. | none |
| Fling under the slop | A release faster along the axis than across, at or above this speed, starts a swipe. | 3000 physical px/s (`flingStartVelocity`) |
| Release | Back when less than a third of the next page shows, unless the release is at least 3500 physical px/s and faster along the axis than across. After catching a settle, a release faster than 1500 physical px/s goes the way of the fling; otherwise the nearer page. | `commits` |
| Settle | Quintic ease out, `1 + (t - 1)^5`. Duration from the distance and the velocity, clamped to the range. | `settleCurve`, 150..600 ms (`settleDuration`) |
| Catch a settle | A down during a settle takes it over. | `catchesOnDown` |
| Programmatic | `animateTo` slides the target in next to the current page; swipes are refused meanwhile. | 540 ms, ease out quint (`animateTo`) |

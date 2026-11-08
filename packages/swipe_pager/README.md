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
- There is no overscroll: the first and last page do not swipe outward. A
  drag moves at most one page; a touch on a settling pager catches it. A
  slide from `animateTo` is not interrupted by a swipe.
- With `MediaQuery.disableAnimations`, settles and slides land at once.
- Pages are identified by index; reordering them needs a new pager key.

## Reference

The defaults port the reference mobile client's own pager
(`Telegram/TMessagesProj/src/main/java/org/telegram/ui/Components/ViewPagerFixed.java`):

| Rule | Reference | Here |
| --- | --- | --- |
| Claim slop 0.3 cm | `touchSlop = getPixelsInCM(0.3f, true)` (181); claim when `abs(dx) >= touchSlop && abs(dx) > dy` (656-659) | `claimSlop`, 18.9 logical px at 160 per inch |
| Vertical list wins | the page's `RecyclerView` starts dragging past the 8 dp touch slop (`RecyclerView.java` 3249) and calls `requestDisallowInterceptTouchEvent` (3393), which drops the pager's pending claim (`ViewPagerFixed` 575-579) | `crossAxisSlop` 8, decided on the straight line from the down |
| Nested horizontal scroller | a child that scrolls horizontally under the finger keeps the gesture (626-631, `findScrollingChild` 2324-2344) | the claim slop is never under the platform drag slop |
| Edges | `prepareForMoving` refuses past the first and last page (517-520) | no claim outward, no overscroll |
| Fling under the slop | `abs(velX) >= 3000 && abs(velX) > abs(velY)` (691) | `flingStartVelocity`, physical px/s |
| Release | back when `abs(x) < width / 3 && (abs(velX) < 3500 \|\| abs(velX) < abs(velY))` (717); after catching a settle, `abs(velX) > 1500` goes the way of the fling, else the nearer page (702-716) | `commits` |
| Settle | quintic `t^5 + 1` on `t - 1` (86-89); duration rule and 150..600 ms clamp (759-772, `distanceInfluenceForSnapDuration` 874-878) | `settleCurve`, `settleDuration` |
| Catch a settle | a down during the settle takes it over (597-622, `checkTabsAnimationInProgress` 842-872) | `catchesOnDown` |
| Programmatic | `scrollToPosition`: the target slides in next to the current page, 540 ms `EASE_OUT_QUINT` (221-289, 291-293); swipes refused meanwhile (`manualScrolling`, 518) | `animateTo` |

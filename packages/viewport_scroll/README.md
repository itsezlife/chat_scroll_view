# viewport_scroll

A viewport's user-driven scroll, for any scroll engine: per-platform
**scroll physics** (a fling paired with an edge effect) and their runtime,
the keyboard scroll keys, and a **fast scrollbar** with a section label. The
chat's anchor viewport, the panel catalogue and plain `Scrollable`s share
it. It depends on the Flutter SDK only.

Decisions: [ADR 020](../../docs/adr/020-package-topology.md) (where it sits).

## Types

| Type | Role |
| --- | --- |
| `ViewportScrollPhysics` | A fling (`ViewportFling$Decay`, `$Spline`) paired with an edge effect (`ViewportEdgeEffect$None`, `$RubberBand`, `$Stretch`), with a preset per platform family. A viewport that runs them reads their runtime from `engine.dart`. |
| `ViewportScrollKeys` | Arrow, page, Home and End scrolling through callbacks (`onScrollBy`, `onScrollToStart`, `onScrollToEnd`): no engine of its own. |
| `FastScrollbar` | A thumb on the trailing edge that drags the content through its whole length, and a label beside it naming the section reached (`labelAt`, by progress). `FastScrollbarPolicy` sets shape, show and hide, haptics; `FastScrollbarStyle` the colours. |
| `FastScrollTarget` | What a fast scrollbar drives: the content as a fraction. `progress` (0 to 1, null when it cannot scroll), `visibleShare`, `jumpTo(progress)`, `stop()`, `dragStarted` / `dragEnded`, and a change signal (`Listenable`). |
| `ScrollControllerFastScrollTarget` | The target of a `ScrollController`'s one position; `offsetAt(progress)` for labels keyed by offset. |

## Contracts

- A target is fraction-based so an engine that only estimates its length
  (an anchor viewport over rows not yet measured) needs no fake pixel
  extent. It notifies on every move and on any length or viewport change
  its engine reports; a `ScrollMetricsNotification` from a scrollable under
  the scrollbar also resyncs it.
- A press stops the target (`stop`) and moves nothing. A drag is relative
  to the press: the thumb's travel spans the content, so a finger move of
  a share of the travel moves the progress by that share. A drag is
  bracketed by `dragStarted` and `dragEnded`.
- Each engine's adapter lives beside the engine, so the scrollbar knows
  none of them.

## Testing

`package:viewport_scroll/testing.dart`: `FakeFastScrollTarget` (set by
hand, records jumps, stops and drags) and `FastScrollTargetContract`, which
an adapter runs against its engine.

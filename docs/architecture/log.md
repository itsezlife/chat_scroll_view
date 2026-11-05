# Architecture Bundle Update Log

## 2026-07-04

* **Creation**: Established OKF knowledge bundle for the chat scroll runtime constitution.
* **Creation**: Concepts 01–13 covering coordinate model, invariants, layers, layout, Tier-1 scroll, boundaries, data source, element, day groups, navigation, animation integration, function reference, and known limitations.

## 2026-10-16

* **Update**: `14-host-chrome-insets.md` aggregates composer extent and panel presentation occupancy into the reserved padding ([ADR 026](../adr/026-composer-model.md), [ADR 028](../adr/028-panel-presentation.md)).

## 2026-11-02

* **Update**: A held navigation placement is no longer re-applied when its target's row chrome changes; the row chrome hold keeps the target's body still (`02`, `04`, `10`, `12`).

## 2026-11-05

* **Update**: Fan-out builds rows past the `cacheExtent` band within a per-frame prefetch budget and resumes on the next tick; `groupBy` is memoized per message (`04`, `05`).
* **Update**: A press that catches a fling drags from its first pixel; other presses use the platform's touch slop (`05`).
* **Update**: A fling counts from the last frame the drag showed, so the frame after the release moves on (`05`).
* **Update**: The tick also lays out once the directional lead runs short (`_leadNoLongerCovers`), so a fling builds rows as they come due instead of in a burst per band crossing (`02`, `04`, `05`, `12`).

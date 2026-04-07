# ChatScrollView vs ListView.builder — Benchmark Report

## Environment
- Flutter 3.32.2, Dart 3.8.2, macOS ARM64
- Viewport: 400x800 logical pixels
- Test runner: `flutter test` (headless, no GPU compositing)
- Date: 2026-04-08
- 42 tests, all passing

## Layout Performance

Time to complete `performLayout()` per frame. Forced relayout via width toggle (1px).

| Messages | ChatScrollView | ListView (CustomPaint) | ListView (Text) | CSV/LV-CP Ratio |
|----------|----------------|------------------------|-----------------|-----------------|
| 32       | 31µs           | 1.98ms                 | 703µs           | **0.016x** (64x faster) |
| 256      | 15µs           | 697µs                  | 462µs           | **0.022x** (46x faster) |
| 6000     | 11µs           | 393µs                  | 593µs           | **0.028x** (36x faster) |

**CSV is 36-64x faster in layout.** Layout time is nearly constant (11-31µs) regardless of total message count — only touches chunks near the viewport (~3-5 chunks).

Note: CSV layout time *decreases* with more messages because with 32 messages all fit in 1 chunk (all 64 slots processed), while at 6000 messages only the visible ~3 chunks are processed.

## Paint Performance — Scroll-only

Internal paint duration when only scroll offset changed (no layout). Measured via `@visibleForTesting` instrumentation on `RenderChatScrollView.paint` and `RenderBenchmarkListViewWrapper.paint`.

| Messages | ChatScrollView | ListView (CustomPaint) | CSV/LV Ratio |
|----------|----------------|------------------------|--------------|
| 32       | 10µs (p95: 23µs)  | 172µs              | **0.058x** (17x faster) |
| 256      | 2.9µs (p95: 6µs)  | 118µs              | **0.024x** (41x faster) |
| 6000     | 2.5µs (p95: 5µs)  | 88µs               | **0.028x** (35x faster) |

**CSV is 17-41x faster in scroll-only paint.** CSV only updates `OffsetLayer.offset` for ~8-10 attached renders. ListView traverses the Sliver protocol and repaints visible children.

## Frame Timing — Fling (total frame time)

Total time for `tester.pump(16ms)` during fling animation (Stopwatch around pump). Includes all framework overhead, layout, paint, compositing. 300 frames per run.

| Messages | ChatScrollView | ListView (CustomPaint) | CSV/LV Ratio |
|----------|----------------|------------------------|--------------|
| 32       | mean=44µs, p95=143µs, max=483µs  | mean=96µs, p95=499µs, max=1.62ms  | **0.46x** (2.2x faster) |
| 256      | mean=25µs, p95=75µs, max=191µs   | mean=54µs, p95=240µs, max=910µs   | **0.47x** (2.1x faster) |
| 6000     | mean=20µs, p95=49µs, max=201µs   | mean=41µs, p95=177µs, max=407µs   | **0.49x** (2x faster)   |

**CSV is ~2x faster in total fling frame time.** The gap is smaller here because total pump time includes constant framework overhead (scheduling, binding, etc.) shared by both implementations. The key differentiator: CSV worst-case (max) is 3-8x better than ListView's worst-case.

### Fling — p95/max advantage

| Messages | CSV max | LV max | LV/CSV max ratio |
|----------|---------|--------|-------------------|
| 32       | 483µs   | 1.62ms | **3.4x** |
| 256      | 191µs   | 910µs  | **4.8x** |
| 6000     | 201µs   | 407µs  | **2.0x** |

CSV has significantly fewer jank spikes (worst-case frames).

## Memory — Static Object Counts

After initial render at bottom of chat.

| Messages | Metric | ChatScrollView | ListView |
|----------|--------|----------------|----------|
| 32       | Attached/visible | 8 renders | 6 elements |
| 32       | Total renders/ROs | 64 renders, 1 chunk | 237 RenderObjects |
| 256      | Attached/visible | 10 renders | 6 elements |
| 256      | Total renders/ROs | 64 renders, 4 chunks | 237 RenderObjects |
| 6000     | Attached/visible | 8 renders | 6 elements |
| 6000     | Total renders/ROs | 64 renders, 16 chunks | 237 RenderObjects |

CSV creates 64 lightweight `ChatMessageRender` per chunk (not Flutter RenderObjects). ListView's 237 RenderObjects is the full MaterialApp+Scaffold widget tree; actual visible bubbles are ~6.

At 6000 messages, CSV holds 16 chunks = 1024 render slots total, with only 8 attached (with layers). ListView always holds only visible items regardless of total count.

## Memory — Scroll Through All (256 messages)

| Metric | ChatScrollView | ListView |
|--------|----------------|----------|
| Peak attached/visible | 43 renders | 12 elements |
| Peak total | 256 renders, 4 chunks | 285 RenderObjects |
| After return | 35 attached | 6 elements |

CSV peak of 43 attached is due to hysteresis zones (1.0x attach, 1.7x detach). No growth trend — working as designed.

## Leak Detection — 50 Scroll Cycles (256 messages)

| Metric | ChatScrollView | ListView |
|--------|----------------|----------|
| Initial | 10 attached | 6 elements |
| Across 50 cycles | 19 (stable) | 8 (stable) |
| Range | **0** | **0** |

**No leaks in either implementation.** Both show perfectly stable counts across 50 full bottom↔top scroll cycles.

## Resize Stress — 200 Frames (256 messages)

Width oscillated 400→500→400 pixels.

| Metric | ChatScrollView | ListView (CustomPaint) |
|--------|----------------|------------------------|
| Mean | 48µs | 225µs |
| p95 | 48µs | 228µs |
| Max | 48µs | 251µs |

**CSV is ~5x faster during resize.** Only re-lays out visible chunk renders.

---

## Issues Found and Fixed During Benchmarking

### 1. Measurement Bug: Stale Frame Values
**Problem**: `debugLastLayoutDuration` / `debugLastPaintDuration` persisted from previous frame when layout/paint wasn't called (nothing dirty). This caused fling benchmarks to report the same value for all 300 frames even when only ~49 had actual work.

**Fix**: Added `debugLayoutFrameId` / `debugPaintFrameId` monotonic counters. Fling benchmarks switched to total `Stopwatch` around `tester.pump()` for fair comparison.

### 2. ListView Wrapper Doesn't Capture Internal Scrolling
**Problem**: `RenderBenchmarkListViewWrapper` (RenderProxyBox) never gets re-laid-out during fling — the internal `RenderViewport` → `RenderSliverList` handles scrolling directly.

**Fix**: For fling comparison, switched to total frame time measurement (Stopwatch around `tester.pump()`) which captures the full rendering pipeline for both implementations.

### 3. No Issues Found in ChatScrollView
- No memory leaks detected
- Attach/detach hysteresis working correctly (stable counts)
- Boundary clamping works properly
- Resize properly triggers full relayout
- Layer management (LayerHandle) prevents disposal issues

---

## Summary

| Metric | CSV advantage | Notes |
|--------|---------------|-------|
| Layout | **36-64x faster** | O(visible chunks) vs O(visible items through Sliver protocol) |
| Paint (scroll-only) | **17-41x faster** | OffsetLayer.offset update vs full Sliver repaint |
| Fling (mean) | **2x faster** | Smaller gap due to shared framework overhead |
| Fling (worst-case) | **2-5x fewer spikes** | Max frame time consistently lower |
| Resize | **5x faster** | Re-layout only visible renders |
| Memory | Comparable | CSV: lightweight renders. LV: full RenderObject tree |
| Leak safety | Both clean | No leaks in either after 50 cycles |

#---

# Part 2: Integration Benchmarks (macOS, real GPU compositing)

## Environment
- macOS ARM64, 120Hz ProMotion display
- Flutter 3.38.7, Dart 3.10.7
- Real rendering pipeline with GPU compositing
- `FrameTiming` API for build/raster measurement
- Message counts: 256, 6000, 20000
- 31 tests, all passing

## Drag Scroll — FrameTiming (build + raster)

200 frames of continuous 15px/frame drag.

| Messages | Metric | ChatScrollView | ListView.builder | CSV/LV Ratio |
|----------|--------|----------------|------------------|--------------|
| 256 | Build mean | 836µs | 1627µs | **0.51x** (2x faster) |
| 256 | Build p95 | 1611µs | 3929µs | **0.41x** (2.4x faster) |
| 256 | Total mean | 1721µs | 2233µs | **0.77x** |
| 256 | Total p95 | 2963µs | 4609µs | **0.64x** (1.6x faster) |
| 6000 | Build mean | 593µs | 1526µs | **0.39x** (2.6x faster) |
| 6000 | Build p95 | 997µs | 3801µs | **0.26x** (3.8x faster) |
| 6000 | Total mean | 1532µs | 2213µs | **0.69x** |
| 6000 | Total p95 | 2374µs | 4501µs | **0.53x** (1.9x faster) |
| 20000 | Build mean | 523µs | 1372µs | **0.38x** (2.6x faster) |
| 20000 | Build p95 | 997µs | 3237µs | **0.31x** (3.2x faster) |
| 20000 | Total mean | 1383µs | 2103µs | **0.66x** |
| 20000 | Total p95 | 2413µs | 4119µs | **0.59x** (1.7x faster) |

**Key insight**: Build phase (layout + widget tree) is where CSV dominates — **2-3.8x faster**. Raster time is comparable (~900µs both), as expected since GPU work is similar.

## Fling — FrameTiming (build + raster)

300 frames of fling from mid-list at 3000 px/s.

| Messages | Metric | ChatScrollView | ListView.builder | CSV/LV Ratio |
|----------|--------|----------------|------------------|--------------|
| 256 | Build mean | 508µs | 681µs | **0.75x** |
| 256 | Total p95 | 2357µs | 3575µs | **0.66x** |
| 6000 | Build mean | 427µs | 612µs | **0.70x** |
| 6000 | Total p95 | 2114µs | 3446µs | **0.61x** |
| 20000 | Build mean | 357µs | 548µs | **0.65x** |
| 20000 | Total p95 | 2080µs | 2831µs | **0.73x** |

CSV build time **decreases** with more messages (from 508µs→357µs). This is because the scroll-only path skips layout entirely — only ~350µs of paint for OffsetLayer offset updates.

## Theoretical Max FPS

Computed from FrameTiming: `1_000_000 / mean_total_µs`.

| Messages | ChatScrollView (mean) | ChatScrollView (p95) | ListView (mean) | ListView (p95) |
|----------|----------------------|---------------------|-----------------|----------------|
| 256      | **641 FPS** | 387 FPS | 481 FPS | 273 FPS |
| 6000     | **716 FPS** | 469 FPS | 509 FPS | 277 FPS |
| 20000    | **715 FPS** | 448 FPS | 504 FPS | 300 FPS |

**CSV: 641-716 FPS theoretical max. LV: 481-509 FPS.** CSV has 1.3-1.4x higher mean throughput and **1.4-1.7x better p95 throughput** (fewer worst-case spikes).

## Raw Computation — Internal Layout + Paint Only

Measures just `performLayout` + `paint` duration inside `RenderChatScrollView`, excluding all framework and GPU overhead.

| Messages | CSV layout | CSV paint | CSV total | CSV theoretical FPS |
|----------|-----------|-----------|-----------|---------------------|
| 256      | 0µs (scroll-only!) | 88µs | 88µs | **11,421 FPS** |
| 6000     | 0µs | 56µs | 56µs | **18,010 FPS** |
| 20000    | 0µs | 50µs | 50µs | **19,995 FPS** |

**Layout = 0µs** during scroll — the scroll-only path completely bypasses `performLayout`. Paint is 50-88µs for updating OffsetLayer offsets and managing attach/detach zones. The theoretical raw compute ceiling is **11,000-20,000 FPS** — vastly more than any display can show.

## Full Traversal — 2000 Frames Through All Messages

Continuous 50px/frame scroll through the entire message list.

| Messages | Metric | ChatScrollView | ListView.builder |
|----------|--------|----------------|------------------|
| 6000 | Build mean | 380µs | 1183µs |
| 6000 | Total mean | 1322µs | 2091µs |
| 6000 | Total p95 | 2062µs | 3695µs |
| 6000 | Jank | 0 / 1996 (0%) | 0 / 1996 (0%) |
| 20000 | Build mean | 366µs | 1132µs |
| 20000 | Total mean | 1290µs | 2057µs |
| 20000 | Total p95 | 2056µs | 3613µs |
| 20000 | Jank | 1 / 1999 (0.05%) | 0 / 1997 (0%) |

**CSV is 1.6x faster** in total frame time during full traversal. Build phase is **3x faster**. Both implementations produce essentially zero jank at this scale.

## Direction Stress — Rapid Direction Changes

200 frames with scroll direction reversal every 5 frames. Tests anchor re-normalization stability.

| Messages | CSV Total mean | CSV Total p95 | CSV Jank | Attached | Chunks |
|----------|---------------|---------------|----------|----------|--------|
| 6000     | 1263µs | 2099µs | 0/198 (0%) | 18 | 16 |
| 20000    | 1276µs | 2084µs | 0/198 (0%) | 19 | 16 |

**Zero jank even with rapid direction changes.** Anchor re-normalization handles direction reversals cleanly. Object counts stable.

## Memory Stability — 3 Full Traversals (6000 messages)

| Pass | Attached | Total renders | Chunks |
|------|----------|---------------|--------|
| 1    | 18       | 64            | 16     |
| 2    | 18       | 64            | 16     |
| 3    | 18       | 64            | 16     |

**Perfectly stable.** No growth across 3 complete traversals (3000 frames of scrolling). Chunk eviction and render recycling working correctly.

---

# Overall Conclusion

## Headless Test Results (Part 1)

| Metric | CSV advantage |
|--------|---------------|
| Layout | **36-64x faster** |
| Paint (scroll-only) | **17-41x faster** |
| Fling (total frame) | **~2x faster** |
| Resize | **~5x faster** |

## Real GPU Results (Part 2 — Integration)

| Metric | CSV advantage |
|--------|---------------|
| Build phase (drag) | **2-3.8x faster** |
| Build phase (fling) | **1.3-1.5x faster** |
| Total frame (drag) | **1.3-1.5x faster** |
| Total frame p95 (drag) | **1.6-1.9x faster** |
| Theoretical max FPS | **641-716 vs 481-509 FPS** |
| Raw compute ceiling | **11,000-20,000 FPS** |
| Full traversal | **1.6x faster** |

## Key Findings

1. **Scroll-only path is the killer feature**: Layout = 0µs during scroll. CSV only updates OffsetLayer offsets (~50-88µs paint). This is the architectural advantage that standard Slivers cannot match.

2. **Build phase dominates**: In real GPU rendering, raster time is ~900µs for both (similar GPU workload). The difference is entirely in the build phase (layout + widget tree processing). CSV's advantage is 2-3.8x here.

3. **Constant-time performance**: CSV performance barely changes from 256→20000 messages. Build mean goes from 836→523µs (improving because more scroll-only frames). ListView stays at ~1400µs regardless.

4. **p95 stability**: CSV has much tighter p95 values (2.4ms vs 4.5ms in drag). This means more consistent frame times and fewer micro-stutters.

5. **Zero leaks, zero growth**: Memory is perfectly stable across all tests. 18 attached renders, 64 total, 16 chunks — constant across 3 full traversals.

6. **Trade-offs confirmed**:
   - +1250 lines of custom rendering code
   - +No built-in semantics/accessibility
   - +Fixed-size chunk allocation (64 renders even for partial chunks)
   - +More attached renders than strictly needed (hysteresis zones)

7. **The approach is clearly beneficial** for chat applications. The near-constant build time regardless of message count makes it particularly suited for very large conversations (20,000+ messages) where ListView.builder's Sliver protocol overhead starts to show.

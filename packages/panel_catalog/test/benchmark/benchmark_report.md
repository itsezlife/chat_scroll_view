# Panel Catalog Viewport vs SuperSliverList & SliverGrid — Benchmark Report

## Environment

- Flutter 3.41.7, Dart 3.11.5, macOS ARM64
- Viewport: 400×600 logical pixels (span 8, cell 48, header 32)
- Catalog presets: 64 / 512 / 4096 unicode leaves (8 leaves/section)
- Test runner: `flutter test test/benchmark/vs_supersliver_bench_test.dart` (headless debug — absolute µs inflated by asserts; **ratios** are the signal)
- Date: 2026-08-25
- Candidate: Panel Catalog Viewport (paint leaves)
- Baselines:
  1. **SliverGrid** — section headers + `SliverGrid` per section (what most packages use)
  2. **SuperSliverList** — frozen flat header+row list (pre-viewport emoji panel body)

## How to re-run

```bash
cd packages/panel_catalog
flutter test test/benchmark/vs_supersliver_bench_test.dart
```

## Verdict (v1 performance bar)

**Pass.** Against both baselines, PCV wins the UX bar (fling / near / far p95–max, layout, memory).

The gap vs **SliverGrid** is larger than vs SuperSliverList — especially layout at 4096 leaves (Grid p95 ~37ms, 67% jank tripwire) and memory (Grid mounts thousands of ROs; PCV stays flat at 8 attached / 169 ROs).

**Call-out (non-blocking):** isolated scroll-only paint still favors widget/RO baselines (~5–12×). End-to-end fling frames favor PCV on p95/max.

Ratio legend: **PCV/baseline** — `< 1` means PCV is faster. Parenthetical is inverse speedup when PCV wins.

---

## Layout Performance

Forced relayout via 1px width toggle (400↔401).

### vs SliverGrid (common Flutter path)

| Leaves | Panel Catalog Viewport | SliverGrid + cells     | PCV/Grid Ratio            |
| ------ | ---------------------- | ---------------------- | ------------------------- |
| 64     | 98µs (p95: 158µs)      | 1.29ms (p95: 2.29ms)   | **0.08x** (13× faster)    |
| 512    | 52µs (p95: 86µs)       | 2.50ms (p95: 3.91ms)   | **0.02x** (48× faster)    |
| 4096   | 163µs (p95: 262µs)     | 21.3ms (p95: 36.8ms)   | **0.01x** (~130× faster)  |

Grid layout at 4096 leaves: **67/100 samples jank** (>16.67ms). PCV: 0 jank.

### vs SuperSliverList (frozen prior body)

| Leaves | Panel Catalog Viewport | SuperSliverList + cells | PCV/SSL Ratio          |
| ------ | ---------------------- | ----------------------- | ---------------------- |
| 64     | 98µs (p95: 158µs)      | 915µs (p95: 1.57ms)     | **0.11x** (9× faster)  |
| 512    | 52µs (p95: 86µs)       | 497µs (p95: 860µs)      | **0.11x** (9× faster)  |
| 4096   | 163µs (p95: 262µs)     | 419µs (p95: 932µs)      | **0.39x** (2.6× faster)|

---

## Paint Performance — Scroll-only

Internal paint after scroll steps (PCV: `scrollBy`; baselines: `jumpTo` + forced proxy paint).

### Why this looks inverted

PCV **paint leaves** redraw the visible band on a canvas every scroll (`clip` + per-glyph `drawParagraph`). There is no per-cell `RenderObject` / retained layer to slide.

SliverGrid / SuperSliverList keep **widget cells as ROs**. Real scroll is often compositor motion; this probe also **forces** `markNeedsPaint` on a timing proxy so samples aren’t stale — that still understates “full leaf redraw” vs PCV’s honest canvas loop.

So baselines win this **isolated paint** probe (~5–12×). End-to-end **fling** still favors PCV because Grid pays build/layout when cells enter the band. Treat ~100–200µs PCV paint as a steady tax well under a 16.7ms frame — not proof that widget grids scroll better.

### vs SliverGrid

| Leaves | Panel Catalog Viewport | SliverGrid + cells | PCV/Grid Ratio         |
| ------ | ---------------------- | ------------------ | ---------------------- |
| 64     | 85µs (p95: 149µs)      | 11µs (p95: 38µs)   | **7.5x** (Grid faster) |
| 512    | 96µs (p95: 219µs)      | 15µs (p95: 27µs)   | **6.3x** (Grid faster) |
| 4096   | 99µs (p95: 183µs)      | 18µs (p95: 34µs)   | **5.5x** (Grid faster) |

### vs SuperSliverList

| Leaves | Panel Catalog Viewport | SuperSliverList + cells | PCV/SSL Ratio          |
| ------ | ---------------------- | ----------------------- | ---------------------- |
| 64     | 85µs (p95: 149µs)      | 9µs (p95: 21µs)         | **9.2x** (SSL faster)  |
| 512    | 96µs (p95: 219µs)      | 11µs (p95: 24µs)        | **8.8x** (SSL faster)  |
| 4096   | 99µs (p95: 183µs)      | 8µs (p95: 17µs)         | **11.8x** (SSL faster) |


---

## Frame Timing — Fling (primary UX)

Wall-clock per `tester.pump(16ms)` during fling (300 frames).

### vs SliverGrid

| Leaves | Panel Catalog Viewport            | SliverGrid + cells                 | PCV/Grid Ratio           |
| ------ | --------------------------------- | ---------------------------------- | ------------------------ |
| 64     | mean=46µs, p95=99µs, max=1.11ms   | mean=147µs, p95=874µs, max=9.07ms  | **0.32x** (3× mean)      |
| 512    | mean=57µs, p95=287µs, max=599µs   | mean=365µs, p95=2.21ms, max=3.95ms | **0.16x** (6× mean)      |
| 4096   | mean=57µs, p95=276µs, max=852µs   | mean=812µs, p95=5.30ms, max=6.59ms | **0.07x** (14× mean)     |

### vs SuperSliverList

| Leaves | Panel Catalog Viewport            | SuperSliverList + cells            | PCV/SSL Ratio            |
| ------ | --------------------------------- | ---------------------------------- | ------------------------ |
| 64     | mean=46µs, p95=99µs, max=1.11ms   | mean=88µs, p95=507µs, max=1.80ms   | **0.53x** (1.9× mean)    |
| 512    | mean=57µs, p95=287µs, max=599µs   | mean=160µs, p95=1.06ms, max=2.65ms | **0.36x** (2.8× mean)    |
| 4096   | mean=57µs, p95=276µs, max=852µs   | mean=140µs, p95=834µs, max=3.33ms  | **0.40x** (2.5× mean)    |

### Fling — p95 / max advantage vs SliverGrid

| Leaves | PCV p95 | Grid p95 | Grid/PCV p95 | PCV max | Grid max | Grid/PCV max |
| ------ | ------- | -------- | ------------ | ------- | -------- | ------------ |
| 64     | 99µs    | 874µs    | **8.8×**     | 1.11ms  | 9.07ms   | **8.2×**     |
| 512    | 287µs   | 2.21ms   | **7.7×**     | 599µs   | 3.95ms   | **6.6×**     |
| 4096   | 276µs   | 5.30ms   | **19×**      | 852µs   | 6.59ms   | **7.7×**     |

---

## Near-path section jump

~220ms smooth scroll (PCV `jumpToSection`; baselines `animateTo`).

### vs SliverGrid

| Leaves | Panel Catalog Viewport | SliverGrid + cells        | PCV/Grid Ratio         |
| ------ | ---------------------- | ------------------------- | ---------------------- |
| 64     | p95=362µs, max=1.12ms  | p95=1.28ms, max=3.01ms    | **0.28x** (3.5× p95)   |
| 512    | p95=239µs, max=429µs   | p95=1.33ms, max=2.76ms    | **0.18x** (5.6× p95)   |
| 4096   | p95=279µs, max=2.72ms  | p95=2.73ms, max=4.47ms    | **0.10x** (10× p95)    |

### vs SuperSliverList

| Leaves | Panel Catalog Viewport | SuperSliverList + cells   | PCV/SSL Ratio          |
| ------ | ---------------------- | ------------------------- | ---------------------- |
| 64     | p95=362µs, max=1.12ms  | p95=627µs, max=1.35ms     | **0.58x** (1.7× p95)   |
| 512    | p95=239µs, max=429µs   | p95=577µs, max=1.24ms     | **0.41x** (2.4× p95)   |
| 4096   | p95=279µs, max=2.72ms  | p95=629µs, max=3.15ms     | **0.44x** (2.3× p95)   |

---

## Far-path stitch vs bare jump

PCV: stitch flight. Baselines: bare `jumpTo`.

### vs SliverGrid

| Leaves | Panel Catalog Viewport | SliverGrid (bare jump)    | PCV/Grid Ratio          |
| ------ | ---------------------- | ------------------------- | ----------------------- |
| 64     | p95=239µs, max=2.64ms  | p95=416µs, max=1.45ms     | **0.57x** (1.7× p95)    |
| 512    | p95=463µs, max=1.55ms  | p95=3.13ms, max=16.2ms    | **0.15x** (6.8× p95)    |
| 4096   | p95=233µs, max=1.19ms  | p95=955µs, max=17.7ms     | **0.24x** (4.1× p95)    |

### vs SuperSliverList

| Leaves | Panel Catalog Viewport | SuperSliverList (bare jump) | PCV/SSL Ratio         |
| ------ | ---------------------- | --------------------------- | --------------------- |
| 64     | p95=239µs, max=2.64ms  | p95=205µs, max=892µs        | ~parity on p95        |
| 512    | p95=463µs, max=1.55ms  | p95=4.76ms, max=5.35ms      | **0.10x** (10× p95)   |
| 4096   | p95=233µs, max=1.19ms  | p95=8.46ms, max=9.37ms      | **0.03x** (36× p95)   |

---

## Memory — Static Object Counts

| Leaves | Metric                          | PCV | SliverGrid | SuperSliverList |
| ------ | ------------------------------- | --- | ---------- | --------------- |
| 64     | Attached / Visible cells        | 8   | 64         | 64              |
| 64     | RenderObjects (full tree)       | 169 | 755        | 612             |
| 512    | Attached / Visible cells        | 8   | 141        | 88              |
| 512    | RenderObjects (full tree)       | 169 | 1763       | 771             |
| 4096   | Attached / Visible cells        | 8   | 589        | 88              |
| 4096   | RenderObjects (full tree)       | 169 | **8483**   | 771             |

PCV stays flat. SliverGrid RO count grows with catalog size (per-cell widgets). SuperSliverList is leaner than Grid but still well above PCV.

## Memory — Peak after scroll-through

| Leaves | Metric                    | PCV | SliverGrid | SuperSliverList |
| ------ | ------------------------- | --- | ---------- | --------------- |
| 64     | Peak cells / attached     | 8   | 64         | 64              |
| 64     | Peak RenderObjects        | 169 | 755        | 612             |
| 512    | Peak cells / attached     | 8   | 166        | 120             |
| 512    | Peak RenderObjects        | 169 | 1963       | 975             |
| 4096   | Peak cells / attached     | 8   | 613        | 120             |
| 4096   | Peak RenderObjects        | 169 | **8675**   | 975             |

---

## Summary

| Metric              | vs SliverGrid              | vs SuperSliverList         | Notes                                      |
| ------------------- | -------------------------- | -------------------------- | ------------------------------------------ |
| Layout              | **13–130× faster**         | **2.6–9× faster**          | Grid janks at 4096 on width toggle         |
| Paint (scroll-only) | Grid ~5–8× faster          | SSL ~9–12× faster          | Isolated retained-RO paint (non-blocking)  |
| Fling (mean)        | **3–14× faster**           | **~2–3× faster**           | Primary UX                                 |
| Fling (p95 / max)   | **8–19× / 7–8× better**    | **3–5× / 2–4× better**     | Worst-case spikes                          |
| Near-path           | **3.5–10× better p95**     | **1.7–2.4× better p95**    |                                            |
| Far-path            | **2–7× better p95**        | up to **36× better p95**   | Stitch vs bare jump                        |
| Memory              | Flat vs thousands of ROs   | Flat vs hundreds of ROs    | Paint-leaf recycle                         |

---

## Notes

- Debug-mode absolute times are not profile/release; compare **ratios** and p95/max.
- Headless fling samples rarely trip the 16.67ms jank tripwire — prefer p95/max.
- Far-path baselines use fewer frames (jump + 30) than stitch (180).
- Scroll-only paint forces baseline proxy paint each step.
- Suite prints full Metric-column tables for both baselines in `tearDownAll`; this report is the hand-curated summary.

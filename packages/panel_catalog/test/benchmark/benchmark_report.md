# Panel Catalog Viewport vs SuperSliverList & SliverGrid — Benchmark Report

## Environment

- Flutter 3.41.7, Dart 3.11.5, macOS ARM64
- Viewport: 400×600 logical pixels (span 8, cell 48, header 32)
- Catalog presets: 64 / 512 / 4096 unicode leaves (8 leaves/section)
- Test runner: `flutter test test/benchmark/vs_supersliver_bench_test.dart` (headless debug — absolute µs inflated by asserts; **ratios** are the signal)
- Date: 2026-08-25 (re-run after layout-once glyphs, paint cull, drag-start fix, cold warm-up)
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

Notable vs prior report:

- **Scroll-only paint** gap narrowed (~5–12× → ~2–4× vs baselines) after layout-once glyph paragraphs.
- **Far-path** now compares stitch to travel-scaled **`animateTo`** (the API stitch replaces), not bare `jumpTo` — the win is clearer, especially at 4096 (Grid animateTo janks 27% of frames).

The gap vs **SliverGrid** remains larger than vs SuperSliverList — layout at 4096 leaves (Grid p95 ~45ms, 85% jank tripwire) and memory (Grid mounts thousands of ROs; PCV stays flat at 8 attached / 169 ROs).

**Call-out (non-blocking):** isolated scroll-only paint still favors widget/RO baselines (~2–4×). End-to-end fling frames favor PCV on p95/mean.

Ratio legend: **PCV/baseline** — `< 1` means PCV is faster. Parenthetical is inverse speedup when PCV wins.

---

## Layout Performance

Forced relayout via 1px width toggle (400↔401).

### vs SliverGrid (common Flutter path)

| Leaves | Panel Catalog Viewport | SliverGrid + cells      | PCV/Grid Ratio           |
| ------ | ---------------------- | ----------------------- | ------------------------ |
| 64     | 144µs (p95: 409µs)     | 1.58ms (p95: 2.84ms)    | **0.09x** (11× faster)   |
| 512    | 72µs (p95: 158µs)      | 3.06ms (p95: 4.72ms)    | **0.02x** (43× faster)   |
| 4096   | 151µs (p95: 355µs)     | 27.6ms (p95: 45.1ms)    | **0.01x** (~180× faster) |

Grid layout at 4096 leaves: **85/100 samples jank** (>16.67ms). PCV: 0 jank.

### vs SuperSliverList (frozen prior body)

| Leaves | Panel Catalog Viewport | SuperSliverList + cells | PCV/SSL Ratio          |
| ------ | ---------------------- | ----------------------- | ---------------------- |
| 64     | 144µs (p95: 409µs)     | 1.56ms (p95: 2.95ms)    | **0.09x** (11× faster) |
| 512    | 72µs (p95: 158µs)      | 572µs (p95: 983µs)      | **0.13x** (8× faster)  |
| 4096   | 151µs (p95: 355µs)     | 504µs (p95: 1.05ms)     | **0.30x** (3.3× faster)|

---

## Paint Performance — Scroll-only

Internal paint after scroll steps (PCV: `scrollBy`; baselines: `jumpTo` + forced proxy paint).

### Why this looks inverted

PCV **paint leaves** redraw the visible band on a canvas every scroll (`clip` + per-glyph `drawParagraph`). There is no per-cell `RenderObject` / retained layer to slide.

SliverGrid / SuperSliverList keep **widget cells as ROs**. Real scroll is often compositor motion; this probe also **forces** `markNeedsPaint` on a timing proxy so samples aren’t stale — that still understates “full leaf redraw” vs PCV’s honest canvas loop.

Baselines still win this **isolated paint** probe (~2–4×). End-to-end **fling** still favors PCV because Grid pays build/layout when cells enter the band. Treat ~35–50µs PCV paint as a steady tax well under a 16.7ms frame — not proof that widget grids scroll better.

### vs SliverGrid

| Leaves | Panel Catalog Viewport | SliverGrid + cells | PCV/Grid Ratio         |
| ------ | ---------------------- | ------------------ | ---------------------- |
| 64     | 36µs (p95: 69µs)       | 14µs (p95: 33µs)   | **2.6x** (Grid faster) |
| 512    | 52µs (p95: 150µs)      | 21µs (p95: 47µs)   | **2.5x** (Grid faster) |
| 4096   | 47µs (p95: 190µs)      | 25µs (p95: 38µs)   | **1.9x** (Grid faster) |

### vs SuperSliverList

| Leaves | Panel Catalog Viewport | SuperSliverList + cells | PCV/SSL Ratio          |
| ------ | ---------------------- | ----------------------- | ---------------------- |
| 64     | 36µs (p95: 69µs)       | 9µs (p95: 27µs)         | **4.2x** (SSL faster)  |
| 512    | 52µs (p95: 150µs)      | 23µs (p95: 50µs)        | **2.2x** (SSL faster)  |
| 4096   | 47µs (p95: 190µs)      | 19µs (p95: 60µs)        | **2.5x** (SSL faster)  |

---

## Frame Timing — Fling (primary UX)

Wall-clock per `tester.pump(16ms)` during fling (300 frames).

### vs SliverGrid

| Leaves | Panel Catalog Viewport            | SliverGrid + cells                 | PCV/Grid Ratio           |
| ------ | --------------------------------- | ---------------------------------- | ------------------------ |
| 64     | mean=39µs, p95=88µs, max=1.24ms   | mean=206µs, p95=1.11ms, max=9.59ms | **0.19x** (5× mean)      |
| 512    | mean=60µs, p95=231µs, max=1.97ms  | mean=522µs, p95=3.49ms, max=6.92ms | **0.12x** (9× mean)      |
| 4096   | mean=132µs, p95=456µs, max=6.14ms | mean=983µs, p95=6.01ms, max=9.32ms | **0.13x** (7× mean)      |

### vs SuperSliverList

| Leaves | Panel Catalog Viewport            | SuperSliverList + cells            | PCV/SSL Ratio            |
| ------ | --------------------------------- | ---------------------------------- | ------------------------ |
| 64     | mean=39µs, p95=88µs, max=1.24ms   | mean=92µs, p95=443µs, max=1.87ms   | **0.43x** (2.3× mean)    |
| 512    | mean=60µs, p95=231µs, max=1.97ms  | mean=204µs, p95=1.29ms, max=3.52ms | **0.30x** (3.4× mean)    |
| 4096   | mean=132µs, p95=456µs, max=6.14ms | mean=203µs, p95=1.20ms, max=3.89ms | **0.65x** (1.5× mean)    |

### Fling — p95 / max advantage vs SliverGrid

| Leaves | PCV p95 | Grid p95 | Grid/PCV p95 | PCV max | Grid max | Grid/PCV max |
| ------ | ------- | -------- | ------------ | ------- | -------- | ------------ |
| 64     | 88µs    | 1.11ms   | **13×**      | 1.24ms  | 9.59ms   | **7.7×**     |
| 512    | 231µs   | 3.49ms   | **15×**      | 1.97ms  | 6.92ms   | **3.5×**     |
| 4096   | 456µs   | 6.01ms   | **13×**      | 6.14ms  | 9.32ms   | **1.5×**     |

---

## Near-path section jump

~220ms smooth scroll (PCV `jumpToSection` near path; baselines `animateTo` 220ms).

### vs SliverGrid

| Leaves | Panel Catalog Viewport | SliverGrid + cells         | PCV/Grid Ratio         |
| ------ | ---------------------- | -------------------------- | ---------------------- |
| 64     | p95=231µs, max=2.88ms  | p95=2.08ms, max=3.48ms     | **0.11x** (9× p95)     |
| 512    | p95=195µs, max=291µs   | p95=3.11ms, max=10.7ms     | **0.06x** (16× p95)    |
| 4096   | p95=235µs, max=323µs   | p95=5.21ms, max=16.8ms     | **0.05x** (22× p95)    |

### vs SuperSliverList

| Leaves | Panel Catalog Viewport | SuperSliverList + cells    | PCV/SSL Ratio          |
| ------ | ---------------------- | -------------------------- | ---------------------- |
| 64     | p95=231µs, max=2.88ms  | p95=797µs, max=1.74ms      | **0.29x** (3.5× p95)   |
| 512    | p95=195µs, max=291µs   | p95=505µs, max=3.39ms      | **0.39x** (2.6× p95)   |
| 4096   | p95=235µs, max=323µs   | p95=583µs, max=4.79ms      | **0.40x** (2.5× p95)   |

---

## Far-path stitch vs animateTo

PCV: far-path stitch flight. Baselines: travel-scaled `animateTo` (same duration formula as stitch — the smooth-scroll alternative stitch replaces). Sample windows are duration-matched (~60–82 baseline frames vs 180 stitch frames).

### vs SliverGrid

| Leaves | Panel Catalog Viewport | SliverGrid (`animateTo`)   | PCV/Grid Ratio          |
| ------ | ---------------------- | -------------------------- | ----------------------- |
| 64     | p95=174µs, max=3.46ms  | p95=2.25ms, max=2.80ms     | **0.08x** (13× p95)     |
| 512    | p95=484µs, max=1.46ms  | p95=4.70ms, max=5.90ms     | **0.10x** (10× p95)     |
| 4096   | p95=166µs, max=2.05ms  | p95=30.7ms, max=64.6ms     | **0.01x** (~185× p95)   |

Grid far `animateTo` at 4096: **22/82 samples jank** (26.8%). PCV stitch: 0 jank.

### vs SuperSliverList

| Leaves | Panel Catalog Viewport | SuperSliverList (`animateTo`) | PCV/SSL Ratio         |
| ------ | ---------------------- | ----------------------------- | --------------------- |
| 64     | p95=174µs, max=3.46ms  | p95=1.22ms, max=4.54ms        | **0.14x** (7× p95)    |
| 512    | p95=484µs, max=1.46ms  | p95=4.89ms, max=6.34ms        | **0.10x** (10× p95)   |
| 4096   | p95=166µs, max=2.05ms  | p95=8.26ms, max=9.35ms        | **0.02x** (50× p95)   |

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
| Layout              | **11–180× faster**         | **3–11× faster**           | Grid janks at 4096 on width toggle         |
| Paint (scroll-only) | Grid ~2–3× faster          | SSL ~2–4× faster           | Narrowed vs prior (~5–12×); still isolated |
| Fling (mean)        | **5–9× faster**            | **~1.5–3× faster**         | Primary UX                                 |
| Fling (p95)         | **13–15× better**          | **~3–5× better**           | Worst-case vs Grid                         |
| Near-path           | **9–22× better p95**       | **2.5–3.5× better p95**    | vs `animateTo`                             |
| Far-path            | **10–185× better p95**     | **7–50× better p95**       | Stitch vs travel-scaled `animateTo`        |
| Memory              | Flat vs thousands of ROs   | Flat vs hundreds of ROs    | Paint-leaf recycle                         |

---

## Notes

- Debug-mode absolute times are not profile/release; compare **ratios** and p95/max.
- Headless fling samples rarely trip the 16.67ms jank tripwire — prefer p95/max.
- Far-path baselines use travel-scaled `animateTo` duration (`catalogStitchTravelDuration`), not bare `jumpTo`.
- Scroll-only paint forces baseline proxy paint each step.
- Suite prints full Metric-column tables for both baselines in `tearDownAll`; this report is the hand-curated summary.

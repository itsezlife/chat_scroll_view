# Panel Catalog Viewport — Benchmark and Acceptance Report

Two kinds of evidence, kept apart on purpose:

1. **On-device acceptance** (frame timing, raster cost, resident memory): the
   only evidence that says whether the catalogue feels smooth. Status:
   **pending reference-device run**. No on-device number is quoted below.
2. **Headless benchmark** (layout cost and object counts against two widget
   baselines): runs anywhere, says nothing about smoothness.

## What the headless benchmark can and cannot show

`test/benchmark/vs_supersliver_bench_test.dart` runs under `flutter test`: it
builds, lays out and records paint, but **does no rasterisation** and has no
GPU.

| It can show | It cannot show |
| ----------- | -------------- |
| Layout cost of a forced relayout, as a ratio against a widget grid | Whether a fling drops a frame on a phone |
| Build, layout and paint-recording time per pumped frame (ratios) | Raster time, glyph rasterisation, atlas upload, draw-call cost |
| Object counts: attached leaves and `RenderObject`s stay flat as the catalogue grows | The cost of the first sight of a colour glyph (the original jank) |
| That stitch and the near path stay cheap in the main isolate | Memory in bytes, GPU memory, resident atlas pages |
| That scroll cost does not grow with catalogue size | Anything about the baked-atlas pipeline: the benchmark's scope has no glyph source and draws glyphs as text (`TextGlyphProducer`), so it exercises the paragraph path (the web strategy) |

Consequence: a dropped frame caused by rasterising emoji is invisible here. The
previous version of this benchmark passed while the first pass over the
catalogue dropped 21 of 455 frames on the reference device (spec reference).
**Never quote this report for fling smoothness.** Absolute microseconds are
debug-mode numbers inflated by asserts; the ratios are the signal.

## On-device acceptance: pending reference-device run

Bar (binding): on the reference device, per scenario, **zero frames over one
vsync budget** (budget derived from the display's refresh rate) and **raster
p99 at most 2 ms**, three of three fresh launches; resident glyph pages at most
64 MiB while the panel is open. Only the reference device gates.

| Suite | Scenarios asserted | Status |
| ----- | ------------------ | ------ |
| `bare` | `panel_open`, `cold_first_pass` (diagnostics: `warm_pass2`, `reopen_pass4`) | pending reference-device run |
| `chat` | `chat_panel_open`, `chat_cold_first_pass` (diagnostic: `chat_warm_pass2`) | pending reference-device run |
| `first_run` | `first_run_no_cache`, `cold_start_valid_cache` (diagnostic: `os_update_stale_rebake`) | pending reference-device run |
| Resident bytes | `atlasResidentBytes` / `atlasResidentPages` in every report, judged against 64 MiB | pending reference-device run |

Commands (run from `example/`; device cool, on a charger, screen on, display at
its top refresh rate, profile build; each launch is a fresh process):

```shell
# bare panel: three launches, run labels <label>-bare-launch1..3
dart run tool/panel_perf.dart --suite bare <device-id> <label>-bare
# panel over the real chat screen
dart run tool/panel_perf.dart --suite chat <device-id> <label>-chat
# first run, cold start with a valid cache, simulated OS update
dart run tool/panel_perf.dart --suite first_run <device-id> <label>-first_run
# or all three suites in one go (runs are labelled <label>-bare, -chat, -first_run)
dart run tool/panel_perf.dart --suite all <device-id> <label>
```

Resident bytes are recorded by every one of those runs, no extra command: each
scenario report carries `meta.atlasResidentBytes` and `meta.atlasResidentPages`
(what the atlas holds resident at the end of the scenario, panel open), and the
scenario fails when the bytes exceed 64 MiB. Read them from
`example/perf/runs/<run-label>/*.json`.

Reports: `example/perf/runs/<run-label>/` (git-ignored, per-frame series and
summary). The kept comparison set is **[example/perf/baseline/](../../../../example/perf/baseline/)**,
empty until a device run exists. Promote one launch of each suite after a green
three of three:

```shell
dart run tool/panel_perf.dart --promote <label>-bare-launch1 <label>-chat-launch1 <label>-first_run-launch1
```

Per-ticket device checks, not part of the three-of-three rule (all take
`TARGET=<test> [DEFINES=...] tool/run_panel_perf.sh <device-id> <label>`):

| Question | Command |
| -------- | ------- |
| Real bake: about a second, no dropped frame; visual check of baked cells against the system rendering | `TARGET=integration_test/glyph_atlas_bake_test.dart DEFINES="--dart-define=GLYPH_ATLAS_ENFORCE=true" tool/run_panel_perf.sh <device-id> <label>` |
| Bake paused versus unpaused during the open animation and a fling | `TARGET=integration_test/glyph_atlas_paced_bake_test.dart DEFINES="--dart-define=PACED_BAKE_ENFORCE=true" tool/run_panel_perf.sh <device-id> <label>` |
| Skia against Impeller | add `--no-enable-impeller` to any run (no rebuild) |

The manual cache, OS-update and density checks are in
[qa-glyph-cache.md](../../../../docs/panel-catalog/qa-glyph-cache.md).

## Headless benchmark results

Re-run 2026-10-16: Flutter 3.41.7, Dart 3.11.5, macOS ARM64, headless debug,
one run. Viewport 400×600 logical px (span 8, cell 48, header 32); catalogue
presets of 64 / 512 / 4096 unicode leaves (8 leaves per section). Candidate:
Panel Catalog Viewport with an `AssetCacheScope` that draws glyphs as text
(paragraph path). Baselines:
**SliverGrid** (section headers plus a `SliverGrid` per section) and
**SuperSliverList** (frozen flat header-and-row list, the previous keyboard
panel body).

```shell
cd packages/panel_catalog
flutter test test/benchmark/vs_supersliver_bench_test.dart
```

The suite prints the full per-metric tables in `tearDownAll`; below is the
hand-curated summary. Ratio is PCV / baseline: below 1, the viewport is faster.
Ranges cover the 64 / 512 / 4096 presets.

| Probe | vs SliverGrid | vs SuperSliverList | Notes |
| ----- | ------------- | ------------------ | ----- |
| Forced relayout (mean) | 0.01–0.07x | 0.07–0.34x | Grid at 4096 janks 62 of 100 relayouts; PCV 0 |
| Scroll-only paint (mean) | 3.0–6.8x (Grid faster) | 4.3–7.9x (SSL faster) | Isolated paint recording; see below |
| Fling frame time (mean / p95) | 0.05–0.20x / 0.03–0.09x | 0.26–0.41x / 0.15–0.18x | 300 pumped frames |
| Near-path section jump (mean / p95) | 0.09–0.22x / 0.05–0.13x | 0.33–0.52x / 0.32–0.35x | against a 220 ms `animateTo` |
| Far-path stitch (mean / p95) | 0.00–0.08x / 0.01–0.11x | 0.01–0.19x / 0.02–0.24x | against a travel-scaled `animateTo` |

Object counts (flat, as the catalogue grows):

| Leaves | Attached leaves (PCV / Grid / SSL) | RenderObjects (PCV / Grid / SSL) |
| ------ | ----------------------------------- | --------------------------------- |
| 64 | 8 / 64 / 64 | 169 / 755 / 612 |
| 512 | 8 / 141 / 88 | 169 / 1763 / 771 |
| 4096 | 8 / 589 / 88 | 169 / 8483 / 771 |

Peak after a scroll-through at 4096 leaves: PCV 8 attached and 169
`RenderObject`s; SliverGrid 613 and 8675; SuperSliverList 120 and 975.

### Mixed layouts (per-section layout)

The same catalogue shape with per-section layouts: even sections use the
viewport defaults (8 columns of 48), odd ones a 5-column layout of 64
(`generateMixedLayoutSections`; same leaf and section counts as the uniform
preset). The baselines lay every section out at one span, so the comparison is
the candidate against itself: ratio is mixed / uniform at the same leaf count,
range over four runs and the 64 / 512 / 4096 presets.

| Probe | Mixed / uniform (median) | Mixed / uniform (mean) | Notes |
| ----- | ------------------------ | ---------------------- | ----- |
| Forced relayout | 0.62–1.10x | 0.68–1.39x | Per-section grid resolution is O(sections) on top of O(slots) |
| Scroll-only paint | 0.69–0.76x | 0.66–0.90x | Taller 5-column cells show fewer cells per screen |
| Near-path section jump | 1.00–1.33x | 0.54–1.16x | Medians sit at the floor of a sampled frame (about 16 µs) |
| Far-path stitch | 0.94–1.07x | 0.78–2.10x | The 2.1x mean is the 64-leaf preset, where one slow frame moves the mean |

Against the pre-change viewport (the integration branch before the per-section
seam, same machine, four alternating runs of the whole suite) the uniform
probes move within run-to-run noise: forced relayout median 53 → 61 µs at 64
leaves, 30 → 30 µs at 512, 75 → 77 µs at 4096; scroll-only paint median 46 →
42, 37 → 36, 36 → 37 µs; near-path jump and far-path stitch medians at the
floor (15–20 µs) before and after. The visible-window lookup is unchanged by
construction (one binary search over one ascending slot list); the added
guard is `scroll cost does not grow with catalogue size` and its per-section
variant in `panel_catalog_scroll_hardening_test.dart`.

**Reading the scroll-only paint row.** The viewport redraws the visible band on
a canvas every scroll (clip, then one draw per visible leaf); there is no
per-cell `RenderObject` or retained layer to slide. The widget baselines keep
cells as `RenderObject`s, and the probe forces a repaint on a timing proxy so
its samples are not stale, which still understates a full redraw. So the
baselines win this isolated probe, by a margin that moves between runs (about
2–4x in the 2026-08 run, 3–8x in this one, with the viewport's own time
unchanged at about 45–60 µs). It is a steady tax far below a frame, not
evidence that a widget grid scrolls better: end-to-end fling frames favour the
viewport. The probe also does not draw sprites, so it does not describe the
shipped baking path; the batched atlas draw is judged on the device.

### Asset binding (viewport attaches through the scope)

The viewport moved from the readiness-flag cache to `AssetCacheScope`
(`attach(key, spec, profile)`, paint the `AssetPaintable`), with the glyph
paragraph cache replaced by the scope's byte-budgeted LRU. Same machine, three
alternating whole-suite runs of the integration branch before and after;
median of the three per-run medians (mean in brackets), ratio is after / before
against SuperSliverList. The paragraph path is what the benchmark exercises, so
this is the cost of going through the binding for text glyphs; the baked sprite
path is not measured headless.

| Probe (64 / 512 / 4096 leaves) | Before (µs) | After (µs) | After / before |
| ------------------------------ | ----------- | ---------- | -------------- |
| Scroll-only paint, median | 41 / 37 / 37 | 33 / 28 / 29 | 0.80 / 0.76 / 0.78 |
| Scroll-only paint, mean | 49 / 49 / 57 | 42 / 35 / 35 | 0.86 / 0.72 / 0.62 |
| Forced relayout, median | 55 / 29 / 75 | 49 / 19 / 71 | 0.89 / 0.66 / 0.95 |
| Fling frame time, median | 22 / 15 / 15 | 23 / 15 / 15 | 1.05 / 1.00 / 1.00 |
| Near-path jump, median | 19 / 15 / 15 | 19 / 16 / 15 | 1.00 / 1.07 / 1.00 |

Scroll-only paint and the other rows are within run-to-run noise or better.
Two traps found while measuring, both fixed: a paragraph shared by every cell of
one glyph was laid out again at each cell, because a rectangle's width is
`right - left` and differs in the last bits between positions (paint 4x slower
until a layout tolerance was added), and a save and a clip per cell cost more
than the glyph (the clip now happens only for a glyph wider than its box).

### Direction, semantics, focus and cursor

Right-to-left cell placement, windowed semantics, roving focus and the click
cursor touch the render object, so the whole suite was run before and after
(same machine, three alternating whole-suite runs; median of the three per-run
medians; ratio is after / before). Semantic nodes are built only for the slot
range the viewport already binds (the visible band plus one cell of overscan, by
binary search), never read a binding or a sprite, and live in content space
under one container whose transform is the scroll offset, so a scroll that keeps
the same window moves one transform and rebuilds no node.

`flutter_test` turns semantics **on** for every widget test unless told
otherwise, so the suite's own numbers are a semantics-on preset; the same suite
was also run with semantics off (every probe forced off, before and after).

| Probe (64 / 512 / 4096 leaves) | Semantics off, after / before | Semantics on (suite default), after / before |
| ------------------------------ | ----------------------------- | -------------------------------------------- |
| Scroll-only paint, median | 1.09 / 1.04 / 1.00 | 1.03 / 1.04 / 1.03 |
| Forced relayout, median | 1.05 / 0.88 / 1.05 | 1.13 / 1.35 / 0.98 |
| Fling frame time, median | 0.96 / 0.94 / 1.00 | 1.05 / 1.00 / 1.00 |
| Near-path jump, median | 1.00 / 0.88 / 1.07 | 1.00 / 0.94 / 1.00 |
| Far-path stitch, median | 1.00 / 1.00 / 1.00 | 0.94 / 0.94 / 1.00 |

With semantics off nothing moves beyond run-to-run noise (the medians sit at the
floor of a sampled frame, 14-25 µs, except relayout and paint). With semantics
on the only probe that moves is forced relayout at 64 / 512 leaves, by 7-8 µs
absolute: a relayout marks the window's nodes stale, which costs something only
while a screen reader is running (the 4096-leaf row does not move).

A semantics probe of its own (`semantics on - scroll frames`) pumps 300 scrolled
frames, semantics flush included, with and without a screen reader on the same
catalogue:

| Leaves | Frame median, semantics off | Frame median, semantics on | Ratio | Semantic nodes |
| ------ | --------------------------- | -------------------------- | ----- | -------------- |
| 64 | 70-77 µs | 82-90 µs | about 1.2x | 74 |
| 512 | 65-71 µs | 136-160 µs | about 2.0-2.3x | 83 |
| 4096 | 65-67 µs | 129-134 µs | about 2.0x | 83 |

The node count is the window (about 16 rows of 8 cells here), not the catalogue:
it is the same at 512 and 4096 leaves, and the test asserts the bound and a
generous 5x tripwire on the median. Absolute microseconds are debug-mode;
the ratio is the signal. A device run with TalkBack or VoiceOver is not part of
this report.

## Accepted gaps

Evidence that does not exist yet, accepted by the spec ("only the reference
device gates; other devices and platforms are best effort"). Each is a risk
carried, not a pass.

**Devices and platforms**

- **Mid-range and low-end Android**: no measurement. The bake pace, the 64 MiB
  ceiling (about 48 MiB resident, 64 MiB with mip levels) and the page upload
  cost are unverified there. Escalation if the 72 px cap or the memory fails on
  a device class: windowed page residency, not a higher ceiling.
- **iOS**: no run. The iOS emoji font is unchecked against the 72 px cap and the
  family-sequence edge (below); the glyph probe has no iOS validation.
- **Web**: no atlas by design (the paragraph strategy stays, with a bounded and
  disposed paragraph cache). Web is not measured; evidence is limited to
  `flutter test` of the strategy switch.
- **Desktop**: macOS debug smoke only (non-gating). A macOS profile build fails
  in the authoring environment (`FlutterMacOS` architecture check in
  `profile_unpack_macos`), so no desktop profile number exists; Windows and
  Linux were never run.
- **Density 3.5 and above**: the baked cell is capped at 72 px, so sprites are
  upscaled about 1.6x at those densities. Unchecked by eye.
- **Impeller's own text atlas copy of baked glyphs**: unmeasured.

**Behaviour measured only off-device**

- Bake during the open animation and during a fling: the pause rules were
  checked on macOS debug only. The governor constants (cheap at 0.5 of the
  budget, halve at 0.85, rise by 2, resume after 2 quiet frames) are untuned
  guesses.
- Disk cache: writing and reading one page without a dropped frame, and the
  500 ms bound on circles after a cold start with a valid cache, are not
  measured. A 409 ms raster frame on a cold-start mount was seen on macOS debug
  and needs a look on the device (page upload against first-frame cost).
- Visual check of the 72 px bake with the Android emoji font: one faint dark
  edge on the family sequence at 3x zoom in the prototype; the rasteriser clips
  to the cell on purpose, so a wide glyph clipped there is the first suspect.
- On Skia the one-time bake and compose frames dropped a few frames in the
  prototype.
- Waiting for a far page: a visible glyph waits for its whole page (about 44
  frames at the default pace, 0.37 s at 120 Hz). Composing partial pages early
  is the lever if that proves too long; it gives up the rule that a composed
  page never changes.

**Design limits**

- Stale-while-rebake holds the old and the new set resident together for a few
  seconds after an art or catalogue change; stale images are outside the
  residency and memory pressure does not release them.
- A glyph the atlas did not plan (a skin tone chosen for the first time) shows
  a circle for under a second while the set re-plans.
- Disk pages are raw: 16 MiB each, 48 MiB for the full catalogue; there is no
  content hash (length and header only). The demo's cache lives in the
  platform's temporary directory, which the platform may clear (a miss). One
  atlas per cache directory at a time.
- Resident bytes are recorded and judged at the end of each scenario, not as a
  peak over the run.

**Glyph support (the unbuilt remainder of the glyph-probe work)**

The probe's logic, the fingerprint and the shared bake pass are built and
unit-tested; these are not:

- The `content_model` glyph-support seam and its fake and contract suite;
  `emoji_data` rewritten over the content-model seams; deletion of the native
  emoji-data plugin (platform folders, web variant, method channel,
  `shared_preferences` and web-plugin dependencies).
- Persisting the probe's result per art version in a host store and restoring
  it on a cache hit (a hit draws nothing, so the probe sees nothing).
- The host reloading the emoji data when the probe completes, so first-run
  filtering applies in-session; the demo is not wired to a probe.
- Probe-specific pacing: today it rides the bake's scheduler pace. Probe time
  and memory on a mid-range device, and zero dropped frames while it runs on the
  reference device, are unmeasured.
- The per-platform validation table (macOS, iOS simulator and web from
  research; Android, Windows and Linux to run) and the Android check of the
  pixel probe.
- A ZWJ sequence that falls back to several glyphs renders differently from the
  missing-glyph box and is not flagged.

**Architecture follow-through** (decided in
[ADR 006](../../../../docs/adr/006-panel-catalog-viewport.md), marked pending
there): scope-provided shared asset cache; per-section layout, snapshot data
source and attach-and-position controller are built; the paintable contract
that replaces the sprite capability now carried on `CatalogAssetBinding` is
built (see the asset-binding A/B below).

## Follow-on: animated media

Out of scope here, built on the same sprite and page abstraction: a second,
dynamic page pool for animation frames (static glyph pages are immutable and
never shared with it); vector animation through a worker-isolate renderer;
static images shown at once; video stickers and GIF as a static thumbnail with
play on tap; web showing static thumbnails; live rendering of visible leaves
with a small in-memory frame ring (a disk frame cache is deferred). Direction
and constraints: the "Animated media" section of the
[implementation spec](../../../../.scratch/panel-catalog-glyph-perf-impl/spec.md)
(a scratch document; the paragraph above is the summary that survives without
it).

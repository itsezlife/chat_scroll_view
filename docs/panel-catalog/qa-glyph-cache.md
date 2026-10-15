# QA: baked glyph cache flows

Three launches decide whether the emoji panel feels native after the first
run: the first run (no cache), a cold start with a valid cache, and the first
launch after an operating-system or emoji font update. Terms:
[glossary](CONTEXT.md) (Glyph cache key, Stale-while-rebake, Art version signal).

Only the reference device gates. Other devices and desktop runs are
indicative; label their numbers non-gating.

## Before you start

- Reference device: Android, display fixed at its top refresh rate, cool, on a
  charger, screen on, nothing else in the foreground.
- Profile build (`--profile`); debug timings say nothing about raster cost.
- The demo keeps its cache in `<temporary directory>/emoji_glyph_atlas_cache`.
  Clear it with *Settings > Apps > (the demo) > Storage > Clear cache*, or
  uninstall and install again. The art version is
  `--dart-define=EMOJI_ART_VERSION=<text>`; without it the demo uses the
  sentinel pixel fingerprint, which changes when the system's emoji art does.

## 1. First run, no cache (automated)

```shell
cd example
dart run tool/panel_perf.dart --suite first_run <device-id> <label>
```

Three fresh launches; each uses an empty cache directory it creates itself.
Asserted scenario `first_run_no_cache`: circles are allowed for as long as they
last, **zero frames over one vsync budget** and raster p99 at most 2 ms are
required. The report meta shows `cacheVerdict: miss`, and the scenario fails
unless every page was persisted by its end.

## 2. Cold start with a valid cache (automated, plus one manual run)

Scenario `cold_start_valid_cache` of the same suite mounts a new panel over the
pages the first scenario persisted. It fails unless `cacheVerdict` is `hit`,
circles lasted at most 500 ms (`cacheAllPagesMs`, measured from the atlas start)
and no frame was dropped while the panel opened. Same process, so the engine
is warm; for the strict case do the manual run:

1. Install the profile build, open the chat, open the emoji panel, wait until
   no circles remain, close the app from the task switcher (swipe away).
2. Launch again, open the panel at once. Circles should be gone by the time
   the open animation ends. Record a screen capture at the display refresh rate
   and count dropped frames over the open animation.

## 3. OS-update scenario (stale-while-rebake)

An OS or emoji font update changes the art version; the pages from before the
update must stay on screen while the new set bakes, then change in one step.
Simulate the update without touching the device OS by changing the art version
signal:

1. Build and run with `--dart-define=EMOJI_ART_VERSION=os-1`
   (`flutter run --profile -d <device-id> --dart-define=EMOJI_ART_VERSION=os-1`).
   Open the emoji panel, wait until no circles remain, close the app from the
   task switcher. The cache now holds the `os-1` pages.
2. Run again with `--dart-define=EMOJI_ART_VERSION=os-2` (the "updated" OS).
   Do not clear the cache. Open the panel as soon as the app is up.
3. Expect:
   - the emoji are on screen at once, from the old pages; no circles appear
     where the previous run had emoji (a glyph the old pages did not hold may
     show a circle until the swap);
   - scrolling through the catalogue while the new set bakes is as smooth as
     any other scroll; baking pauses during scrolling and the open animation;
   - after a few seconds the emoji change to the new art in one step: no cell
     is seen changing before the others;
   - closing the app and launching with `os-2` again is a plain cache hit
     (no circles, no baking).
4. Repeat from step 2 with `os-3` and with the panel already open when the
   app starts re-baking, then once with the device low on memory (open many
   apps first). Memory is about twice normal for the few seconds of the
   rebake (old and new pages resident); report anything worse.

The automated diagnostic `os_update_stale_rebake` in the first-run suite runs
the same flow in one process and records its frame statistics and the cache
meta (`cacheVerdict: stale`, `cacheSwapped: true`). It is not asserted yet:
decide the bar after the first reference-device numbers.

## 4. Density change

Change the display size (*Settings > Display > Display size*) or rotate to a
configuration with another density, then open the panel: the old pages are
discarded, circles show as on a first run, the bake fills them in, and the next
launch at that density is a hit.

## 5. Real OS update (reference device)

The simulated update above does not exercise the fingerprint. On a device whose
system emoji font really changes (an OS update, or a font swap on a test
device), launch without the `EMOJI_ART_VERSION` define before and after: the
second launch must report `cacheVerdict: stale` and re-bake behind the old
pages. This is not automated; the logic is covered by the fake-system tests
named in the package CHANGELOGs.

The glyph probe (hiding emoji the system cannot draw) is not wired into the
demo, so there is nothing to check for it on a device yet.

## What to report

For each run: device, build mode, refresh rate, the label of the run, frames
over budget and raster p99 from `example/perf/runs/<label>/`, the `cache*` and
`atlasResident*` meta keys (resident pages must stay within 64 MiB), and a
screen capture for the manual steps.

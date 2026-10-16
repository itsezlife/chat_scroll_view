# Benchmarks

Headless ratio benchmarks, tracked nightly. They report layout cost and object
counts. They say **nothing about fling smoothness**: nothing is rasterised and
there is no GPU. Frame timing, raster cost and the resident atlas ceiling are
the device acceptance (`example/integration_test/panel_perf/`, driven by
`example/tool/panel_perf.dart`), which needs a device, is run by hand and is
never part of the nightly job. Its thresholds are defined once, in
`acceptance.dart` and `acceptance_runner.dart` next to it; nothing here
restates them.

Not a gate. `scripts/check` does not run `scripts/bench`, the workflow has no
pull request trigger, and a regression opens an issue
([ADR 030](../docs/adr/030-testing-policy.md)). The benchmark test files do
run under `scripts/check` as ordinary tests, asserting only deterministic
facts (counts, budgets, hold balance), never a time.

## Suites

| Suite id | Test file | Measures |
| -------- | --------- | -------- |
| `panel_catalog.semantics-off` | `packages/panel_catalog/test/benchmark/vs_supersliver_bench_test.dart` | Viewport against a sectioned `SliverGrid` and a `SuperSliverList`: forced relayout, scroll-only paint, fling frames, near and far section jumps, mixed layouts against uniform, object counts. Semantics off. |
| `panel_catalog.semantics-on` | same file, `BENCH_SEMANTICS=on` | The same probes with a screen reader's semantics tree built. |
| `catalog_assets` | `packages/catalog_assets/test/benchmark/asset_cache_ratio_bench_test.dart` | Attach and detach churn with and without eviction, LRU hit rates at the default budgets, one clock tick fanned out to 10, 100 and 1000 animated bindings, glyph bindings holding pages of a real `GlyphPageResidency`, memory pressure with pinned pages. |

### The semantics preset

`flutter_test` builds a semantics tree for every widget test, charging each
probe for work that exists on a device only while TalkBack or VoiceOver runs.
Shipping default is off, so the headline suite runs **semantics off**; what a
screen reader adds has its own metric (`semantics.scroll_frame.on_over_off.*`,
the same frames with and without, in the same process) and the nightly job also
runs the whole suite **semantics on**, so a regression only a screen reader
pays still shows. Run one preset by hand with
`BENCH_SEMANTICS=on flutter test test/benchmark/vs_supersliver_bench_test.dart`
in `packages/panel_catalog`.

## Metrics

Each suite writes named numbers, never absolute times, so a slower machine does
not move them.

| Kind | Meaning | Regressed when |
| ---- | ------- | -------------- |
| `ratio` | A time over a time measured in the same process (candidate over a widget baseline, mixed over uniform, semantics on over off, a cache cycle over a bare LRU doing the same bookkeeping) | above baseline by more than 50% |
| `count` | An exact object, node or event count | above baseline by more than 5% |
| `rate` | A fraction where higher is better (LRU hit rate) | below baseline by more than 0.02 |

A metric in the baseline that a run no longer reports counts as a regression: a
probe must not leave the watch list unnoticed. A new metric is reported as
added and is not a failure. Improvements are listed and are not failures; they
are the prompt to re-baseline.

**Where 50% comes from.** Six whole-suite runs on one machine (macOS, Apple
silicon, headless debug) gave per-metric extremes up to 1.4-1.8x apart for the
worst ratios (those whose medians sit at the clock floor of a sampled frame,
about 15 microseconds), and the largest max over median was about 1.4x. The
nightly job compares the median of three runs with a baseline that is itself a
median of at least five, which narrows that further, so 1.5x separates a
change in kind (a doubling, or a probe that starts scaling with the catalogue)
from noise. It is deliberately a tripwire, not a meter: a 20% change is not
detectable here, and the device acceptance is where fine differences are
judged. Counts and rates are deterministic, so their tolerances are tight.

## Run it

```shell
scripts/bench                    # 3 runs per suite, compare, write build/bench/
scripts/bench --runs 5 --only catalog_assets
scripts/bench --compare-only     # re-judge the runs already in build/bench/runs
```

`build/bench/report.md` is the verdict, `build/bench/results/<suite>.json` the
median-merged numbers, `build/bench/runs/` each run. Exit code: 0 nothing
regressed, 1 a regression, 2 a benchmark did not run.

Closing other work first matters: the numbers are a ratio of two timings taken
seconds apart, and a busy machine moves them.

## Baselines

`benchmarks/baselines/<suite>.<os>.json`, one per suite and operating system,
because the same code is faster or slower on a CI runner than on a laptop by a
different amount in every probe. A platform with no file is **seeded, not
failed**: the run reports "no baseline yet" and the nightly artifact carries
the numbers.

Re-baselining is a human step (review the diff, it is the performance claim):

```shell
# On the machine class the baseline is for, otherwise idle:
scripts/bench --runs 5 --update-baselines
git diff benchmarks/baselines
```

For the CI runner class, take `results/<suite>.json` from the
`benchmark-results` artifact of a nightly run (or a manual one, see below) and
commit it as `benchmarks/baselines/<suite>.linux.json`. Until that file exists
the nightly job on the runner only seeds.

Re-baseline when a change moves a ratio on purpose (an improvement the report
lists, or a new probe), never to silence a regression. The headline numbers in
`packages/panel_catalog/test/benchmark/benchmark_report.md` are refreshed in
the same change.

## Nightly workflow

`.github/workflows/benchmarks.yml`: a schedule on the default branch plus
`workflow_dispatch`. It runs `scripts/bench`, uploads `build/bench` as the
`benchmark-results` artifact, writes the report to the job summary and:

- exit 1: opens an issue labelled `benchmark-regression` with the report, or
  comments on the open one (one issue at a time, not one per night);
- exit 2: the only case that turns the job red (a benchmark failed to run);
- anything else: green.

It is not a required check and cannot block a merge.

**Drill.** Dispatch the workflow with `force_regression` to make every
measured number 2x worse and compare it with the same run's own medians. It
proves the whole issue path on any runner, with or without a baseline, using
the label `benchmark-drill`, and closes the issue straight away. Locally:

```shell
scripts/bench --runs 1 --only catalog_assets --inject-regression 2   # exit 1
```

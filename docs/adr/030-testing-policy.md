# ADR 030: Testing, fakes and quality gates

Each package that defines a seam ships fakes and a contract suite behind a
separate `testing.dart` entry point. Tests move with the code. Pull requests
are gated by analysis, tests, the dependency lint and generator
reproducibility; performance benchmarks report nightly and never block a merge.

**Status**: Accepted  
**Date**: 2026-10-16  
**Amended**: 2026-10-16 — change notification is `package:listen`, which brings its own tests: there is no `Observable` fake or contract suite, and the seams' suites keep requiring an idempotent `dispose` of their owner ([ADR 023](023-data-layering-and-persistence.md) Amendment). A test that makes a listener throw sets `Listenable.onError` in `setUp` and restores it in `tearDown`; the packages never set it  
**Amended**: 2026-10-18 (chat-polish-3, ticket 10): the playback lifecycle source joins the table; process-wide binding state a contract run moves (the lifecycle) is restored by the run's own tear-down  
**Amended**: 2026-11-05 — golden baselines belong to one host, the CI runner (`linux_x64`): `golden_baseline`'s `useGoldenBaselines` compares them there only (a test on another host is reported skipped) and refuses to regenerate them anywhere else; `scripts/goldens` runs them in a `linux/amd64` container from any machine, and the Goldens workflow regenerates them on the runner. A scene that needs a platform's own fonts names its own baseline host. `GoldenBaselineLint` keeps every golden test on it  
**Amended**: 2026-11-06 — native decoders: a fake binding per native package, the frame renderer's contract suite, the alpha golden on both builds, and the fuzz rule (section *Amendment: native decoders*)  
**Relates to**: [ADR 020](020-package-topology.md), [ADR 022](022-asset-cache-and-media-pipeline.md), [ADR 023](023-data-layering-and-persistence.md)

## Decided

| Seam or area | Fake | Contract suite | Location |
| ------------ | ---- | -------------- | -------- |
| Asset fetcher, decoder, cache | `FakeFetcher`, `FakeDecoder`, manual clock | `AssetFetcherContract.run`, `DecoderContract.run`; cache invariants: pinned while attached, evict never touches live bindings, no visible failure plus retry on re-attach, connectivity-restored and `retry()`, dedupe, cancel on last detach, staged readiness, page hold counts | `catalog_assets` (`testing.dart`) |
| Native binding (`lottie_native`, `video_native`) | `FakeLottieBinding`, `FakeVideoBinding`: scripted parse results, frames and failures, no native library | `NativeBindingContract.run` (probe reports availability once; a failed parse returns an error and never throws; render writes the documented pixel format; disposed handles refuse) over the fake and, where a native library is present, the real binding | each `*_native` package (`testing.dart`) |
| Frame renderer seam | `FakeFrameRenderer` writing known pixels into slots (it can hold batches to model a late frame), `ListFramePageMemory` | `FrameRendererContract.run`: an empty batch, premultiplied output, writes inside the slot only, a later frame replaces the earlier, a batch across pages, a bad job left out and the others spared. Run over the fake and over every engine adapter | `catalog_assets` (`testing.dart`) |
| Dynamic frame pages (`FramePool`, `FramePageImages`, `FrameAtlas`) | The frame renderer fake and an injected uploader | None: they are concrete, like `PlaybackActivity`, and are tested by behaviour: pins and least-recently-used eviction, the full pool, memory pressure, one upload per changed page, an image that lives as long as its page, batches that run in order and pin what they name | `catalog_assets` |
| `KeyValueStore`, `RecentsStore`, `PreferenceStore`, `CollectionSource`, `SearchSource`, `KeywordSource`, `GlyphSupport`, `PackSource`, `ContentLibrary`, `LibraryStorage` ([ADR 044](044-content-library-packs-and-preview.md)) | In-memory fakes | One `...Contract.run` per seam | `content_model` (`testing.dart`) |
| Playback tick source, lifecycle source | `ManualPlaybackTickSource`, `ManualPlaybackLifecycleSource` (with `ManualRetentionTimers` for grace periods) | `PlaybackTickSourceContract.run`, `PlaybackLifecycleSourceContract.run` (each distinct change notifies once, a repeated state nothing, a disposed source says nothing, dispose is idempotent) over the production adapter and the fake; `PlaybackActivity` is concrete and tested by behaviour over the fakes and a real clock | `catalog_assets` (`testing.dart`) |
| Presentation policy and strategies | Fake IME input port, manual clock | `PresentationPolicyContract.run`; IME hand-off state-machine tests | `panel_presentation` (`testing.dart`) |
| Shell, pages, composer | Fake page, fake `CollectionSource` | Widget tests; the `PanelPage` contract | Owning package |

- Fakes and contracts live in each seam's package behind `testing.dart`. Production entry points never export fakes and production code never downcasts to a fake. Adapter authors and hosts run the same suites against their implementations.
- Tests move with the code. The demo app keeps host-integration tests only.
- Layers: pure-Dart unit tests (no Flutter), widget tests (shell, pages, composer), selective goldens, and device integration tests in `integration_test/` (IME hand-off, hover timing on desktop and web).
- Goldens live in the owning package and cover deterministic token-driven visuals: composer slots per mode, panel shell and bottom bar, placeholder styles at a fixed clock, skeleton sections, light and dark palettes. They run on one pinned platform (the CI runner, through `golden_baseline`) with a documented tolerance, on the glass flat path. Glass is verified by `GlassQuality` x capabilities x route motion to strategy unit tests and a per-platform device checklist that also produces the fallback matrix.
- First tests close known gaps: evict with a live binding, data-source swap, skin-tone capability agreement, locale and catalog integrity from the generator, empty-tab and post-dispose cases.
- Required gates per pull request, for the changed package and its dependents: `dart analyze --fatal-infos`; package tests including contract suites; the dependency-direction check (no cycles, leaves stay leaves, no cross-package re-exports, no fakes in production); emoji generator reproducibility (pinned inputs regenerate the committed assets byte for byte, licence notices present).
- Performance: viewport and asset-cache benchmarks run nightly or on demand as ratio reports against stored baselines with a documented tolerance. A regression opens an issue and does not block merges, because headless debug timings are noisy. IME hand-off, glass fallback and hover timing are manual release checklists.
- Tooling: a pub workspace at the repo root (root package, every `packages/*`, `example/`, `scripts/`), one resolution and one committed lockfile, the shared `flutter_md` override at the workspace root, and `resolution: workspace` in members. One `scripts/check` runs analysis, tests and the lints in dependency order, and CI calls it ([scripts/README.md](../../scripts/README.md)).
- A migrated package is done when analysis is clean, ported tests pass, contract suites exist, goldens exist for its listed surfaces, its README has a Host contract table with ADR links, and nothing downcasts.

## Why

- No seam had a contract test. Panel, page and inset tests lived in the demo app. Goldens did not cover glass or the panel. CI ran only an LLM review, and nine lockfiles drifted.
- Benchmark ratios are the signal; absolute headless timings vary run to run.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| One shared testing package; private per-package fakes without contracts | A shared package couples every seam; private fakes drift from the real adapters |
| Goldens that include glass; no goldens | Glass output is device-dependent; visual regressions would go unseen |
| Benchmarks as merge gates; local discipline only | Noisy gates train people to ignore them; discipline does not scale |
| Per-package resolution and lockfiles; deferring tooling | Drift; every package would repeat the setup |

## Related

- Lint rules, fake and adapter naming conventions: [scripts/README.md](../../scripts/README.md)

## Amendment: native decoders

[ADR 042](042-native-media-decoding.md) adds native engines. Their tests keep
the shape of this ADR: contracts over fakes, with the real binding as one more
implementation of the same suite. Rows that name a package or a build not in
the repository yet apply when that adapter lands; they are the plan, not
present facts.

| Area | Decision |
| ---- | -------- |
| Adapters | When the adapter lands, `lottie_decoder` and `video_decoder` run `DecoderContract.run` against their fake binding, so no test of an adapter needs a native library. |
| Alpha | When the adapter lands, one golden with a semi-transparent sticker (premultiplied output, no fringing) runs against the native build and the WebAssembly build on the `golden_baseline` host; both must match the same baseline within the documented tolerance. |
| Fuzzing | The wrapper's crate replays a seeded corpus (prefix truncations, zero bytes, byte mutations) through `chat_lottie_load` in its own tests today; when the adapter lands, a fixed corpus of malformed files (including the known 269-byte file and truncated and mutated TGS, JSON and WebM) replays against the wrapper's input checks on every pull request and must finish in under a minute. A longer fuzz runs on demand (manual dispatch; no schedule, to spare CI minutes) and opens an issue on a finding; like the benchmarks it never blocks a merge. |
| Load failure | When the adapter lands, a test per decoder proves that a failed probe leaves the form unregistered and the placeholder in place. |
| Benchmark | A scroll benchmark with animated stickers extends `scroll_trace` and reports nightly as ratios, per the performance rule above. |

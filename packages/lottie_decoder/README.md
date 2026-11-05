# lottie_decoder

The Lottie adapter for the frame pool
([ADR 042](../../docs/adr/042-native-media-decoding.md), ADR 022 "dynamic frame
pages"): an async engine seam over a `lottie_native` binding, native page
memory a render isolate can write, and a `FrameRenderer` that draws into it.

## Types

| Type | Role |
| --- | --- |
| `LottieEngine` | The async face of a `LottieBinding`: `load`, `renderBatch` (of `LottieEngineJob`), `dispose`, `close` (idempotent; later calls throw `StateError`). |
| `LottieEngineJob` | A render job whose target is an `int` address, so it crosses isolates. |
| `InProcessLottieEngine` | Runs a binding on the calling isolate. With `FakeLottieBinding` it is the engine fake. |
| `NativeFramePageMemory` | `FramePageMemory` in `calloc`ed memory (a Dart-heap list cannot be written from another isolate). `addressOf(page)`, `drop`, `dispose`. |
| `LottieFrameRenderer` | `FrameRenderer` over an engine and one memory; a job's `source` is a `LottieHandle`. |

## Host contract

| The host provides | The host must not |
| --- | --- |
| An engine over an available binding, and the one `NativeFramePageMemory` the renderer and the pool share | Pass the renderer another memory (`StateError`) or a job whose `source` is not a `LottieHandle` (`ArgumentError`) |
| `dispose` for each loaded handle and `close` for the engine | Use a view from `page` after `drop` or `dispose` |

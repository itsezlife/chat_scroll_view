# lottie_decoder

The Lottie adapter for the frame pool
([ADR 042](../../docs/adr/042-native-media-decoding.md), ADR 022 "dynamic frame
pages"): an async engine seam over a `lottie_native` binding, native page
memory a render isolate can write, and a `FrameRenderer` that draws into it.

## Types

| Type | Role |
| --- | --- |
| `LottieEngine` | The async face of a `LottieBinding`: `load`, `renderBatch` (of `LottieEngineJob`), `dispose`, `close` (idempotent; requests already made run to completion first; later calls throw `LottieEngineClosed`, a `StateError`). |
| `LottieEngineJob` | A render job whose target is an `int` address, so it crosses isolates. |
| `InProcessLottieEngine` | Runs a binding on the calling isolate. With `FakeLottieBinding` it is the engine fake. |
| `IsolateLottieEngine` | One long-lived render isolate that owns the binding and every handle. `spawn({bindingFactory})` throws a `LottieUnavailable` (a `StateError`) carrying the `LottieAvailability` when the binding is unavailable; any other start-up failure surfaces as it happened, and the isolate and ports are released. One request failing throws a `RemoteError` and spares the engine; the isolate ending fails every pending request with `LottieEngineClosed` and closes the engine. Requests run in arrival order. A native fault ends the process and cannot be caught. |
| `LottieEngineContract` (`testing.dart`) | The behaviour every engine shares, run over the in-process engine and over the isolate engine on the fake and on the real binding. |
| `NativeFramePageMemory` | `FramePageMemory` in `calloc`ed memory (a Dart-heap list cannot be written from another isolate). `addressOf(page)`, `drop`, `dispose`. |
| `LottieFrameScheduler` | The one owner of the host's `FrameAtlas`: follows `PlaybackClock` while a lease exists, renders the wanted frames as one batch per tick, and frees a slot after one to two idle periods (default 1 s) by a single sweep timer. The sweep uses a real `Timer` by design: it keeps counting while the clock is paused, and a repaint after a long pause reacquires the entry and draws the last rendered frame, not the still. |
| `LottieFrameSize` | The one render size (`fitting(info, edge)`) the decoder and the paintable share. |
| `LottieAnimationPaintable` / `LottieStillPaintable` | The animation (pull-driven, one scheduler key per animation, `onDispose` frees its handle) and a decoded still. |
| `LottieDecoder` | The `Decoder` for `MediaForm.vectorAnimation`, built from an engine, the scheduler and two injectable image steps (`decodeImage`, `uploadPixels`). |
| `LottieFrameRenderer` | `FrameRenderer` over an engine and one memory; a job's `source` is a `LottieHandle`. |

## Host contract

| The host provides | The host must not |
| --- | --- |
| An engine over an available binding, and the one `NativeFramePageMemory` the renderer and the pool share | Pass the renderer another memory (`StateError`) or a job whose `source` is not a `LottieHandle` (`ArgumentError`) |
| `dispose` for each loaded handle and `close` for the engine | Use a view from `page` after `drop` or `dispose` |

## The decoder

| Request | Reports |
| --- | --- |
| thumbnail (an ordinary image) | `placeholder`, a still |
| content, first frame only | `firstFrame`, a still; the handle is freed |
| content, full | `firstFrame` (a still), then `full` (animated tier) |
| content, spec above 512 px | `firstFrame`, then the same still as `full`; the render is capped at 512 and the handle freed |

Frame 0 is drawn into a temporary native buffer, not an atlas slot (the pool may
be full) and uploaded as premultiplied RGBA. The `full` stage costs the frame
(`w * h * 4`) plus `4 *` the encoded size for the parsed model, as the web client
estimates. A rejected file, an engine error or a frame that does not render ends
in `fail(..., AssetFailureKind.permanent)`; `cancel` stops reporting and frees
whatever the decode already holds. Files with image or text layers still decode;
`LottieInfo.features` is the host's to read.

## Host recipe

The host probes by spawning, and registers only on success:

```dart
try {
  final engine = await IsolateLottieEngine.spawn(); // throws when unavailable
  final scheduler = LottieFrameScheduler(atlas: atlas, clock: clock);
  decoders.register(
    MediaForm.vectorAnimation,
    LottieDecoder(engine: engine, scheduler: scheduler),
  );
} on Object catch (reason) {
  // No decoder (a LottieUnavailable names why): vector animations keep their
  // placeholder. Log it once.
}
```

`atlas` is a `FrameAtlas` over a `LottieFrameRenderer` and the one
`NativeFramePageMemory`. Close the engine and dispose the scheduler at shutdown.

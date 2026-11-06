# video_decoder

The video decoder adapter, part 1: the `VideoEngine` seam over a
`video_native` binding, an in-process engine and a pool of worker isolates.

- `VideoEngine` (web-neutral): `open`, `nextFrame` into a `Uint8List`,
  `rewind`, `close`, `dispose`. Frames of a clip come in order; looping is
  `rewind`. Premultiplied BGRA, tightly packed.
- `InProcessVideoEngine`: runs the binding on the calling isolate.
- `IsolateVideoEngine.spawn(workers: 2)`: workers own their clips; a clip is
  pinned to one worker, requests for it run in the order made.
- `testing.dart`: `FakeVideoEngine` and `VideoEngineContract`.

The native tests need the `video_native` library (see its README); without it
they are skipped with a reason.

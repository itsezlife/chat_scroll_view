# lottie_native

The binding interface to the native Lottie renderer (tlottie behind a batch C
API, [ADR 042](../../docs/adr/042-native-media-decoding.md)): load a file,
render frames into page memory, dispose. A leaf of the workspace
([ADR 020](../../docs/adr/020-package-topology.md), rule 8): it depends on no
workspace package and is reached through its decoder only.

This package holds the interface, the fake and the contract. The native
library and its build hook arrive with the wrapper crate.

## Types

| Type | Role |
| --- | --- |
| `LottieBinding` | The interface: `isAvailable`, `load`, `renderBatch`, `dispose`. A native binding, a fake and a web binding satisfy it. |
| `LottieLoadResult` | Sealed: `LottieLoaded(handle, info)` or `LottieRejected(reason)`. A bad file is a value, never an exception. |
| `LottieRejection` | `tooLarge`, `malformed`, `limitExceeded`, `unsupported`, mirroring the wrapper's load statuses. |
| `LottieInfo` | Size, frame count, frame rate and `LottieFeatures` of a loaded file. |
| `LottieFeatures` | Bitmask of what the file uses and the renderer does not draw: effects, expressions, image layers, text layers. Informational. |
| `LottieRenderJob` / `LottieRenderStatus` | One frame into a slot of page memory (premultiplied RGBA, rows `strideBytes` apart); `ok`, `badArgument`, `badSize`, `failed`. |

## Host contract

| The host provides | The host must not |
| --- | --- |
| A binding it registers only when `isAvailable` is true | Call `load` or `renderBatch` on one that is not (they throw `StateError`) |
| Page memory it owns, with the slot's top-left pixel as `target` and the page's row distance as `strideBytes` | Expect a render to touch a byte outside the slot's `width * 4` bytes of each of its rows |
| `dispose` for every `LottieLoaded` handle it is done with | Render a disposed handle (it answers `badArgument`) or share a binding across isolates |

## Testing

`package:lottie_native/testing.dart` (opt-in) exports `FakeLottieBinding`
(scripted files, a frame-derived colour per job, `available:`) and
`NativeBindingContract.run` over a `NativeBindingHarness`. An implementation
runs the contract against itself:

```dart
NativeBindingContract.run(() => NativeBindingHarness(
      binding: binding,
      validBytes: validBytes,
      expectedInfo: expectedInfo,
      malformedBytes: malformedBytes,
    ));
```

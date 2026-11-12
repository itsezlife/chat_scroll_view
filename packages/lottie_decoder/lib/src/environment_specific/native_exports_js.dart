// What the barrel exports where there is no `dart:ffi`: nothing. The slot
// engines and the zero-copy renderer write to native memory by address, which
// the web does not have; its engine returns pixels and `PixelCopyFrameRenderer`
// copies them.

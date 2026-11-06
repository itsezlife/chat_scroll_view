// What the barrel exports where `dart:ffi` is missing: nothing. The binding
// writes frames into memory behind a `Pointer`, which the web does not have;
// its binding arrives with its own types.

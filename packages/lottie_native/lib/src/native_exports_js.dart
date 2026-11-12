// What the barrel exports where `dart:ffi` is missing: nothing. The bindings
// and the codec work on page memory behind a `Pointer`, which the web does not
// have; its binding arrives with its own types.

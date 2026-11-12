/// Whether a binding can be used, and if not, why.
enum VideoAvailability {
  /// The library loaded and speaks the expected ABI version.
  available,

  /// The library, or a symbol of it, could not be found.
  missingLibrary,

  /// The library loaded but speaks another ABI version.
  abiMismatch,
}

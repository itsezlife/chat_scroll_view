/// Which native build renders: part of every frame-cache key, so frames an
/// older build drew are never replayed for a newer one.
abstract final class LottieNativeVersion {
  /// The `chat_lottie` crate version and the pinned tlottie revision, as one
  /// token a file name can carry.
  ///
  /// Bump it with `native/Cargo.toml` (the crate's `version`, or the `rev` of
  /// `tlottie`): a pixel-changing update that kept the old token would serve
  /// stale frames from disk. A test compares it with the manifest, so a
  /// manifest change that forgets this fails there.
  static const String engine = 'chat-lottie-0.1.0-tlottie-92df98dc20';
}

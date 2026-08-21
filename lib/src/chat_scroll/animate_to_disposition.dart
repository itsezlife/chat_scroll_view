/// How [ChatScrollController.animateTo] treated a call relative to an
/// in-flight animate.
enum AnimateToDisposition {
  /// A new animate (or instant jump / already-there settle) was accepted.
  accepted,

  /// Dropped: another animate was in flight and [AnimateToBusyPolicy.ignore]
  /// applied. Hosts that advance selection on tap must **not** commit that
  /// step — otherwise UI state races ahead of the viewport.
  ignored,

  /// Same id+alignment as the in-flight animate; attached to that future.
  coalesced,
}

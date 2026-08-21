/// How [ChatScrollController.animateTo] treats a new request while another
/// animate is already in flight.
enum AnimateToBusyPolicy {
  /// Keep the in-flight motion; drop different-target calls.
  /// Same id+alignment still coalesces onto the in-flight future.
  ///
  /// Returns [AnimateToDisposition.ignored]. Hosts that keep a selection
  /// index (search next/prev) must only advance that index when disposition
  /// is not [AnimateToDisposition.ignored], or the UI races ahead of the
  /// viewport and bound-gated controls go dead mid-flight.
  ignore,

  /// Cancel the in-flight animate and start the new one immediately.
  /// Use when the latest request must win (e.g. sequential search next/prev).
  replace,
}

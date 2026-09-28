/// The path one [ChatScrollController.animateTo] flight took to its target,
/// reported on [ChatAnimateEnd.path].
///
/// Reporting only: the value never feeds back into path choice. After the
/// navigation load-gate, a **built** target takes the close path and a
/// target that is **not built** stitches ([AnimateToLoadPolicy]).
///
/// The path is fixed when the flight enters it. A flight cancelled later —
/// by a drag, [ChatScrollController.scrollBy], another navigation, target
/// deletion, or teardown — still reports the path it entered, because the
/// viewport already moved along it (a stitch has already teleported and
/// laid out the destination band).
enum AnimateToPath {
  /// The target was a built row: the viewport scrolled continuously through
  /// the rows in between. Includes a zero-travel settle and a target
  /// already painted at its aligned seat.
  close,

  /// The target was not built: the viewport teleported the anchor to it and
  /// dual-translated the outgoing and incoming strips. The rows between
  /// origin and target were never built.
  stitch,

  /// `duration <= 0`: the target was placed by an instant
  /// [ChatScrollController.jumpTo] without choosing close or stitch; whether
  /// it was built beforehand is not reported.
  instant,

  /// No path was entered: the flight was cancelled while the navigation
  /// load-gate waited for the destination.
  none,
}

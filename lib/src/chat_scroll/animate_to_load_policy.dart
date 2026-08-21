/// How [ChatScrollController.animateTo] behaves when the target row is not
/// yet built (unfetched chunk / not in the fan-out range).
enum AnimateToLoadPolicy {
  /// Wait one layout for the target to build, then close-path if near,
  /// else stitch. Use for self-insert / follow-tail where newest is usually
  /// one frame away.
  preferBuilt,

  /// Choose close vs stitch immediately (default). Unloaded slots may appear
  /// as shimmers in the incoming stitch strip — no idle wait before jump.
  immediate,
}

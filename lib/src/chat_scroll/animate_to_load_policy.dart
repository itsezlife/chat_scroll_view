/// How [ChatScrollController.animateTo] behaves when the target is not yet a
/// ready destination row (unfetched chunk / unresolved shimmer).
///
/// Both policies honor the **navigation load-gate**: stitch never runs over
/// unresolved shimmers, and neither policy times out into force-stitch. After
/// readiness: **built → close-path**; **not built → stitch**.
enum AnimateToLoadPolicy {
  /// Prefer close-path when a ready row is already entering the build range
  /// (self-insert / follow-tail). Still waits for readiness; never falls back
  /// to shimmer-stitch.
  preferBuilt,

  /// Enter the load-gate as soon as needed, then choose close vs stitch
  /// (default). Ready-but-unbuilt targets may stitch immediately; unready
  /// targets wait until loaded.
  immediate,
}

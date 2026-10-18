/// Where one binding's playback stands, as `AssetBinding.playback` reports it.
enum AssetPlayback {
  /// Nothing is advancing: the profile does not animate and no replay asked
  /// it to, the asset has no animation (yet), the surface is hidden, or the
  /// binding is detached. The surface shows one frame.
  idle,

  /// A pass is advancing with the playback clock (or waiting for a pause
  /// layer to clear), or the profile loops and so always is.
  playing,

  /// A pass of a profile that does not loop is over and the binding holds its
  /// rest frame. It costs no ticks; `AssetBinding.replay` plays another pass.
  ended,
}

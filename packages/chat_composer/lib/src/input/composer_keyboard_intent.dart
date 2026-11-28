/// What a surface over the composer asks of the soft keyboard, published by
/// `ComposerController.keyboardIntent` for the host to carry out.
///
/// The composer knows no panel and no occupancy, so it only states the
/// intent; the host carries it out through its panel presentation, where
/// the keyboard's space at the bottom of the window is kept.
enum ComposerKeyboardIntent {
  /// The keyboard follows the field, and the host holds nothing for it. The
  /// default, and what a surface that draws above the keyboard asks.
  keep,

  /// The keyboard goes down and the space it took stays occupied at its
  /// height, with no motion, so the composer does not drop under the
  /// surface. The host lowers the keyboard (leaving focus on the field)
  /// and holds the occupancy until the intent changes; keyboard requests do
  /// nothing meanwhile, until `ComposerController.reopenKeyboard`.
  hold,

  /// The keyboard stays down and the held space is let go: the slot shrinks
  /// with its usual motion. A surface that removed what the user was typing
  /// about closes with it.
  hide,
}

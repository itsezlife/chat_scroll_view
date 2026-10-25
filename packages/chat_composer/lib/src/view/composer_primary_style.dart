/// How the composer draws its primary action (the send).
///
/// The reference clients draw a filled disc with the glyph on it; some hosts
/// draw the bare glyph in the accent instead. Either way the action is the
/// primary one: the submit shortcut invokes it and a busy spec disables it.
enum ComposerPrimaryStyle {
  /// A filled disc in the send colour, the glyph on it in the on-send colour.
  disc,

  /// The bare glyph in the send colour, with no fill, like an active action.
  glyph,
}

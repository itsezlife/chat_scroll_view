/// A formatting item the selection menu can offer, named by what it does to
/// the selection.
///
/// The host chooses the set in `ComposerSpec.formatting`; the menu decides
/// per selection which of them can be chosen (an item whose command cannot
/// apply is drawn disabled, and Quote is left out over a selection that is
/// quoted already). The order here is the More page's order: the inline styles,
/// then the line kinds, then the link, the lists and clear formatting.
enum ComposerFormattingOption {
  /// Bold.
  bold,

  /// Italic.
  italic,

  /// Underline.
  underline,

  /// Strikethrough.
  strikethrough,

  /// Monospace (inline code).
  mono,

  /// Hides the selection behind a spoiler.
  spoiler,

  /// Turns the selected lines into a quote. Left out when the selection is
  /// quoted already.
  quote,

  /// A fenced code block over the selected lines.
  codeBlock,

  /// One Link item, to create the link or, while the selection touches one, to
  /// edit it, and Remove link while it does. Needs `ComposerSpec.linkPrompt`.
  link,

  /// The selected lines as bullet list items. Offered only while lists are on.
  bulletList,

  /// The selected lines as numbered list items. Offered only while lists are
  /// on.
  numberedList,

  /// Takes every style, link, quote, code block and list item off the
  /// selection.
  clearFormatting;

  /// Everything the composer offers without a switch: the list items wait for
  /// the lists to be on.
  static const Set<ComposerFormattingOption> standard = {
    bold,
    italic,
    underline,
    strikethrough,
    mono,
    spoiler,
    quote,
    codeBlock,
    link,
    clearFormatting,
  };

  /// Every option, the list items included. They still show only while lists
  /// are on.
  static const Set<ComposerFormattingOption> all = {
    bold,
    italic,
    underline,
    strikethrough,
    mono,
    spoiler,
    quote,
    codeBlock,
    link,
    bulletList,
    numberedList,
    clearFormatting,
  };
}

/// A formatting item the selection menu can offer, named by what it does to
/// the selection.
///
/// The host chooses the set in `ComposerSpec.formatting`; the menu decides
/// per selection which of them show (an item whose command cannot apply is
/// left out, as the reference client's floating toolbar leaves out a disabled
/// item). The order here is the menu's order: the reference client's own, then
/// the additions it has no item for, then the link, then clear formatting.
enum ComposerFormattingOption {
  /// Turns the selected lines into a quote. Left out when the selection is
  /// quoted already.
  quote,

  /// Hides the selection behind a spoiler.
  spoiler,

  /// Bold.
  bold,

  /// Italic.
  italic,

  /// Monospace (inline code).
  mono,

  /// Strikethrough.
  strikethrough,

  /// Underline.
  underline,

  /// A fenced code block over the selected lines.
  codeBlock,

  /// The selected lines as bullet list items. Offered only while lists are on.
  bulletList,

  /// The selected lines as numbered list items. Offered only while lists are
  /// on.
  numberedList,

  /// Create link, or Edit link and Remove link while the selection touches
  /// one. Needs `ComposerSpec.linkPrompt`.
  link,

  /// Takes every style, link, quote, code block and list item off the
  /// selection (the reference client's "Regular").
  clearFormatting;

  /// Everything the composer offers without a switch: the list items wait for
  /// the lists to be on.
  static const Set<ComposerFormattingOption> standard = {
    quote,
    spoiler,
    bold,
    italic,
    mono,
    strikethrough,
    underline,
    codeBlock,
    link,
    clearFormatting,
  };

  /// Every option, the list items included. They still show only while lists
  /// are on.
  static const Set<ComposerFormattingOption> all = {
    quote,
    spoiler,
    bold,
    italic,
    mono,
    strikethrough,
    underline,
    codeBlock,
    bulletList,
    numberedList,
    link,
    clearFormatting,
  };
}

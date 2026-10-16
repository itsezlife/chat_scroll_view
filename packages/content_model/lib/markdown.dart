/// Opt-in conversion between `RichText` and markdown.
///
/// A separate library so that hosts that keep rich text as data never import
/// it, and so that this package needs no markdown dependency. See
/// `RichTextMarkdown` for the mapping, the escape rules and the limits.
library;

export 'src/rich_text/markdown/rich_text_markdown.dart';

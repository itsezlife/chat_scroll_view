import 'package:content_model/src/rich_text/markdown/markdown_decoder.dart';
import 'package:content_model/src/rich_text/markdown/markdown_encoder.dart';
import 'package:content_model/src/rich_text/rich_text.dart';

/// The conversion between [RichText] and markdown, for hosts.
///
/// The host calls it where a message body is made or read: [encode] when it
/// sends a composer's text, saves a draft as text or materialises a body it
/// received; [decode] when it loads a body back into the composer for
/// editing. Nothing in a scroll or paint path calls it, and it depends on no
/// markdown package: the dialect is the one the viewport's markdown library
/// reads.
///
/// ## Mapping
///
/// | Entity | Markdown |
/// | --- | --- |
/// | bold, italic, underline | `**x**`, `*x*`, `__x__` |
/// | strike, spoiler | `~~x~~`, `\|\|x\|\|` |
/// | code | `` `x` ``, a longer fence when `x` holds backticks |
/// | quote | `> ` before each line, then a blank line when text follows |
/// | link | `[x](url)`; a target with whitespace goes in `<...>` |
/// | mention | `[@alice](mention:alice)` |
/// | inline content | `![alt](unicode:1F44D)`, `document:` or `external:` |
///
/// The target of inline content is [ContentKey.encoded], so a key round-trips
/// through `unicode:`, `document:` and `external:`, and the alternative text
/// is the label. An image whose target is not a content key keeps its label as
/// plain text.
///
/// ## Behaviour to rely on
///
/// - **Bare text stays text** (ADR 017). [encode] never turns a URL or an
///   `@name` into a link or mention, and [decode] never detects one. Making
///   one is the host's linkify step, done before the entity is built.
/// - **Round trip.** `decode(encode(x)) == x` for every [RichText]. The
///   converse does not hold: markdown has many spellings, and [decode] gives
///   the canonical value, which [encode] writes in one canonical spelling.
/// - **Escapes.** Text is escaped so that it reads back as text: `\`, `*`,
///   `` ` ``, `[` and `]` always; `_` unless it sits between two word
///   characters; a run of two or more `~`, `|` or `=` unless whitespace walls
///   it in; a block marker (`#`, `-`, `+`, `>`, `|`, `1.`, `~~~`) at the start
///   of a line; a `!` before a link. [decode] reads a backslash before any
///   ASCII punctuation as that character.
/// - **Styles are toggles.** A style marker switches the style on or off, and
///   styles that overlap partially are written as they are, with no markers
///   split or reopened. A link cannot hold markers, so a link under a style
///   boundary is written as several links to one target, which [decode] merges
///   back.
/// - **Lines.** Styles, links and code never cross a line break; [decode]
///   reads each line on its own. A quote is whole lines.
/// - **Never throws.** [decode] accepts any string: markers it cannot pair
///   stay text.
///
/// ## Limits of the dialect
///
/// The dialect is that of the viewport's markdown library, which is narrower
/// than CommonMark, and the helper writes what the model holds even where
/// that library cannot show it:
///
/// - Underline next to a word character (including emoji and non-Latin
///   letters) is not rendered by the library, because it does not let `__`
///   open or close inside a word. [decode] reads it back correctly.
/// - The library has no escape for `~`, `|` and `=`, and shows the backslash.
/// - Inline content under a link is written inside the link label, which the
///   library does not read.
/// - Renderers that nest markers (CommonMark) read partially overlapping
///   styles differently.
abstract final class RichTextMarkdown {
  /// The markdown for [text].
  static String encode(RichText text) => MarkdownEncoder.encode(text);

  /// The rich text [markdown] describes.
  ///
  /// Never throws: markup that does not form a style, link or quote is kept as
  /// text.
  static RichText decode(String markdown) => MarkdownDecoder.decode(markdown);
}

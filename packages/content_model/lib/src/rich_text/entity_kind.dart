import 'package:content_model/src/identity/content_key.dart';
import 'package:meta/meta.dart';

/// The formatting styles an [Entity] can apply to a span of text.
enum EntityStyle {
  /// Heavier weight.
  bold,

  /// Slanted.
  italic,

  /// Underlined.
  underline,

  /// Struck through.
  strike,

  /// Hidden until revealed.
  spoiler,

  /// Monospaced, inline. Holds no other entity.
  code,

  /// A block quotation, always whole lines.
  quote,
}

/// Whether a [EntityKind.list] item is a bullet or a numbered one.
enum EntityListKind {
  /// A bullet item: `- ` in markdown.
  bullet,

  /// A numbered item: `1. ` in markdown. The number is not stored; it is
  /// derived from the item's place among its siblings when written.
  ordered,
}

/// What an [Entity] says about the span it covers.
///
/// The set of kinds is closed:
///
/// - a **style** ([EntityKind.bold], [EntityKind.italic],
///   [EntityKind.underline], [EntityKind.strike], [EntityKind.spoiler],
///   [EntityKind.code], [EntityKind.quote]) carries no payload;
/// - [EntityKind.link] carries the target `url`;
/// - [EntityKind.mention] carries the opaque `id` of the mentioned party;
/// - [EntityKind.inlineContent] carries the [ContentKey] of content embedded in
///   the text. The span is its plain-text alternative;
/// - [EntityKind.codeBlock] carries the code's optional `language`;
/// - [EntityKind.username] and [EntityKind.hashtag] carry the `name` and `tag`
///   of text a detector found;
/// - [EntityKind.list] carries the [EntityListKind] and nesting `depth` of one
///   list item.
///
/// Mentions and inline content are **atomic**: the span stands for one thing,
/// so editing inside it removes the entity rather than splitting it.
/// Usernames and hashtags are not: they are text, and edit as text.
@immutable
sealed class EntityKind {
  /// A kind that applies [style].
  const factory EntityKind.style(EntityStyle style) = EntityKind$Style;

  /// A link to [url], which must not be empty or contain a line break, and
  /// must not use the `mention:`, `username:` or `hashtag:` scheme: markdown
  /// spells those kinds with them (see [EntityKind.mention],
  /// [EntityKind.username], [EntityKind.hashtag]).
  const factory EntityKind.link(String url) = EntityKind$Link;

  /// A mention of the party with the opaque [id], which must not be empty or
  /// contain a line break.
  const factory EntityKind.mention(String id) = EntityKind$Mention;

  /// Content embedded in the text, identified by [key].
  const factory EntityKind.inlineContent(ContentKey key) =
      EntityKind$InlineContent;

  /// A block of code: whole lines, holding no other entity and overlapping
  /// no quote. [language] names the code (`dart`, `c++`); when given it is
  /// letters, digits and `+ # . _ -`.
  const factory EntityKind.codeBlock({String? language}) = EntityKind$CodeBlock;

  /// A `@name` a detector found: plain text with no id, which the host
  /// resolves when it is tapped. [name] must not be empty or contain a line
  /// break.
  ///
  /// It is never made for a resolved user: that stays [EntityKind.mention],
  /// which is atomic and whose id the host verifies before sending (ADR 032).
  ///
  /// Overlap rule: a username is _detected_, so it yields. It never overlaps
  /// a link, a mention, inline content, code or a code block, and the
  /// canonical form drops it where it would; of two overlapping usernames or
  /// hashtags the one that starts later is dropped. It may carry styles, and
  /// lies within one line. Equal usernames that touch are one entity, as links
  /// are.
  const factory EntityKind.username(String name) = EntityKind$Username;

  /// A `#tag` a detector found: plain text with the same rules as
  /// [EntityKind.username]. [tag] must not be empty or contain a line break.
  const factory EntityKind.hashtag(String tag) = EntityKind$Hashtag;

  /// One item of a list, [depth] levels in (0 to [EntityKind$List.maxDepth]).
  ///
  /// Like a quote it covers whole lines, but one entity is one item: items
  /// never merge with a neighbour, because where one ends and the next begins
  /// is the information. A soft break inside an item is a line break its
  /// entity covers. The marker and the number are not in the text: they are
  /// derived when written.
  ///
  /// An item shares no line with a quote or a code block; where one does, the
  /// item is dropped, and of two items that share a line the one that starts
  /// first stays. Styles, links, mentions and code inside an item are fine.
  const factory EntityKind.list({required EntityListKind listKind, int depth}) =
      EntityKind$List;

  const EntityKind._();

  /// [EntityStyle.bold].
  static const EntityKind$Style bold = EntityKind$Style(EntityStyle.bold);

  /// [EntityStyle.italic].
  static const EntityKind$Style italic = EntityKind$Style(EntityStyle.italic);

  /// [EntityStyle.underline].
  static const EntityKind$Style underline = EntityKind$Style(
    EntityStyle.underline,
  );

  /// [EntityStyle.strike].
  static const EntityKind$Style strike = EntityKind$Style(EntityStyle.strike);

  /// [EntityStyle.spoiler].
  static const EntityKind$Style spoiler = EntityKind$Style(EntityStyle.spoiler);

  /// [EntityStyle.code].
  static const EntityKind$Style code = EntityKind$Style(EntityStyle.code);

  /// [EntityStyle.quote].
  static const EntityKind$Style quote = EntityKind$Style(EntityStyle.quote);

  /// Whether editing inside a span of this kind removes the entity instead of
  /// resizing it.
  bool get isAtomic => switch (this) {
    EntityKind$Mention() || EntityKind$InlineContent() => true,
    EntityKind$Style() ||
    EntityKind$Link() ||
    EntityKind$CodeBlock() ||
    EntityKind$Username() ||
    EntityKind$Hashtag() ||
    EntityKind$List() => false,
  };
}

/// An [EntityKind] that applies an [EntityStyle]; see [EntityKind.style].
final class EntityKind$Style extends EntityKind {
  /// Creates the kind that applies [style].
  const EntityKind$Style(this.style) : super._();

  /// The style applied.
  final EntityStyle style;

  @override
  bool operator ==(Object other) =>
      other is EntityKind$Style && other.style == style;

  @override
  int get hashCode => Object.hash(EntityKind$Style, style);

  @override
  String toString() => 'EntityKind.${style.name}';
}

/// An [EntityKind] for a link; see [EntityKind.link].
final class EntityKind$Link extends EntityKind {
  /// Creates a link kind to [url].
  const EntityKind$Link(this.url) : super._();

  /// The link target, opaque to this package.
  final String url;

  @override
  bool operator ==(Object other) =>
      other is EntityKind$Link && other.url == url;

  @override
  int get hashCode => Object.hash(EntityKind$Link, url);

  @override
  String toString() => 'EntityKind.link($url)';
}

/// An [EntityKind] for a mention; see [EntityKind.mention].
final class EntityKind$Mention extends EntityKind {
  /// Creates a mention kind for [id].
  const EntityKind$Mention(this.id) : super._();

  /// The opaque id of the mentioned party.
  final String id;

  @override
  bool operator ==(Object other) =>
      other is EntityKind$Mention && other.id == id;

  @override
  int get hashCode => Object.hash(EntityKind$Mention, id);

  @override
  String toString() => 'EntityKind.mention($id)';
}

/// An [EntityKind] for embedded content; see [EntityKind.inlineContent].
final class EntityKind$InlineContent extends EntityKind {
  /// Creates an inline content kind for [key].
  const EntityKind$InlineContent(this.key) : super._();

  /// The embedded content.
  final ContentKey key;

  @override
  bool operator ==(Object other) =>
      other is EntityKind$InlineContent && other.key == key;

  @override
  int get hashCode => Object.hash(EntityKind$InlineContent, key);

  @override
  String toString() => 'EntityKind.inlineContent($key)';
}

/// An [EntityKind] for a block of code; see [EntityKind.codeBlock].
final class EntityKind$CodeBlock extends EntityKind {
  /// Creates a code block kind, in [language] when given.
  const EntityKind$CodeBlock({this.language}) : super._();

  /// The language of the code, or null when it names none.
  final String? language;

  @override
  bool operator ==(Object other) =>
      other is EntityKind$CodeBlock && other.language == language;

  @override
  int get hashCode => Object.hash(EntityKind$CodeBlock, language);

  @override
  String toString() => 'EntityKind.codeBlock(${language ?? ''})';
}

/// An [EntityKind] for a detected `@name`; see [EntityKind.username].
final class EntityKind$Username extends EntityKind {
  /// Creates a username kind for [name].
  const EntityKind$Username(this.name) : super._();

  /// The name after the `@`, which the host resolves.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is EntityKind$Username && other.name == name;

  @override
  int get hashCode => Object.hash(EntityKind$Username, name);

  @override
  String toString() => 'EntityKind.username($name)';
}

/// An [EntityKind] for a detected `#tag`; see [EntityKind.hashtag].
final class EntityKind$Hashtag extends EntityKind {
  /// Creates a hashtag kind for [tag].
  const EntityKind$Hashtag(this.tag) : super._();

  /// The tag after the `#`.
  final String tag;

  @override
  bool operator ==(Object other) =>
      other is EntityKind$Hashtag && other.tag == tag;

  @override
  int get hashCode => Object.hash(EntityKind$Hashtag, tag);

  @override
  String toString() => 'EntityKind.hashtag($tag)';
}

/// An [EntityKind] for one list item; see [EntityKind.list].
final class EntityKind$List extends EntityKind {
  /// Creates a list item kind of [listKind], [depth] levels in.
  const EntityKind$List({required this.listKind, this.depth = 0})
    : assert(
        depth >= 0 && depth <= maxDepth,
        'A list item is nested 0 to $maxDepth levels.',
      ),
      super._();

  /// The deepest nesting an item has.
  static const int maxDepth = 3;

  /// Whether the item is a bullet or a numbered one.
  final EntityListKind listKind;

  /// How many levels the item is nested; 0 is the outermost.
  final int depth;

  @override
  bool operator ==(Object other) =>
      other is EntityKind$List &&
      other.listKind == listKind &&
      other.depth == depth;

  @override
  int get hashCode => Object.hash(EntityKind$List, listKind, depth);

  @override
  String toString() => 'EntityKind.list(${listKind.name}, depth: $depth)';
}

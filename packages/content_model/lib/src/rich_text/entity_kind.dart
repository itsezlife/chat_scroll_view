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
/// - [EntityKind.codeBlock] carries the code's optional `language`.
///
/// Mentions and inline content are **atomic**: the span stands for one thing,
/// so editing inside it removes the entity rather than splitting it.
@immutable
sealed class EntityKind {
  /// A kind that applies [style].
  const factory EntityKind.style(EntityStyle style) = EntityKind$Style;

  /// A link to [url], which must not be empty or contain a line break, and
  /// must not use the `mention:` scheme (see [EntityKind.mention]).
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
    EntityKind$Style() || EntityKind$Link() || EntityKind$CodeBlock() => false,
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

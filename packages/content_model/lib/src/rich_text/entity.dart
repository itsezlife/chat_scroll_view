import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/rich_text/entity_kind.dart';
import 'package:meta/meta.dart';

/// A span of a [RichText] and what it means.
///
/// [offset] and [length] count UTF-16 code units of the text, the unit of
/// Dart's `String` and of Flutter's text positions, so an entity maps onto a
/// selection or a `TextSpan` without conversion. A value is only meaningful
/// against the text it was made for; [RichText] checks that on construction.
@immutable
final class Entity {
  /// Creates an entity over the [length] code units from [offset].
  const Entity(this.offset, this.length, this.kind)
    : assert(offset >= 0, 'An entity cannot start before the text.'),
      assert(length > 0, 'An entity must cover at least one code unit.');

  /// The code unit index where the span starts.
  final int offset;

  /// The number of code units in the span; always positive.
  final int length;

  /// What the span means.
  final EntityKind kind;

  /// The code unit index just after the span.
  int get end => offset + length;

  /// This entity as JSON-encodable data; [fromJson] reads it back.
  ///
  /// The keys are `offset`, `length` and `kind`, plus the payload key of the
  /// kind: `url` (link), `id` (mention), `key` (inline content, the
  /// [ContentKey.encoded] string), `language` (a code block that names
  /// one), `name` (username), `tag` (hashtag) or `listKind` (`bullet` or
  /// `ordered`) with `depth` (list item). Styles use their enum name as
  /// `kind`; the other kinds use `link`, `mention`, `inlineContent`,
  /// `codeBlock`, `username`, `hashtag` and `list`.
  Map<String, Object?> toJson() => {
    'offset': offset,
    'length': length,
    ...switch (kind) {
      EntityKind$Style(:final style) => {'kind': style.name},
      EntityKind$Link(:final url) => {'kind': _link, 'url': url},
      EntityKind$Mention(:final id) => {'kind': _mention, 'id': id},
      EntityKind$InlineContent(:final key) => {
        'kind': _inlineContent,
        'key': key.encoded,
      },
      EntityKind$CodeBlock(:final language) => {
        'kind': _codeBlock,
        'language': ?language,
      },
      EntityKind$Username(:final name) => {'kind': _username, 'name': name},
      EntityKind$Hashtag(:final tag) => {'kind': _hashtag, 'tag': tag},
      EntityKind$List(:final listKind, :final depth) => {
        'kind': _list,
        'listKind': listKind.name,
        'depth': depth,
      },
    },
  };

  /// The entity [json] describes, or null when its `kind` is not one this
  /// version knows, so data written by a newer version still loads without
  /// the formatting that cannot be read.
  ///
  /// Throws a [FormatException] when [json] is not shaped like [toJson]'s
  /// output for a known kind.
  static Entity? fromJson(Object? json) {
    final object = switch (json) {
      final Map<Object?, Object?> map => map,
      _ => throw FormatException('An entity must be a JSON object.', json),
    };
    if (_kindFromJson(object) case final kind?) {
      if (object case {
        'offset': final int offset,
        'length': final int length,
      } when offset >= 0 && length > 0) {
        return Entity(offset, length, kind);
      }
      throw FormatException('An entity needs a valid offset and length.', json);
    }
    return null;
  }

  static const String _link = 'link';
  static const String _mention = 'mention';
  static const String _inlineContent = 'inlineContent';
  static const String _codeBlock = 'codeBlock';
  static const String _username = 'username';
  static const String _hashtag = 'hashtag';
  static const String _list = 'list';

  static EntityKind? _kindFromJson(Map<Object?, Object?> json) {
    final name = switch (json['kind']) {
      final String kind => kind,
      _ => throw FormatException('An entity needs a kind.', json),
    };
    switch (name) {
      case _link:
        return EntityKind.link(_requireString(json, 'url'));
      case _mention:
        return EntityKind.mention(_requireString(json, 'id'));
      case _inlineContent:
        final key = ContentKey.tryParse(_requireString(json, 'key'));
        if (key == null) {
          throw FormatException('Not an encoded ContentKey.', json['key']);
        }
        return EntityKind.inlineContent(key);
      case _codeBlock:
        return switch (json['language']) {
          null => const EntityKind.codeBlock(),
          final String language => EntityKind.codeBlock(language: language),
          final other => throw FormatException(
            'A code block language must be a string.',
            other,
          ),
        };
      case _username:
        return EntityKind.username(_requireString(json, 'name'));
      case _hashtag:
        return EntityKind.hashtag(_requireString(json, 'tag'));
      case _list:
        final listKind = switch (json['listKind']) {
          'bullet' => EntityListKind.bullet,
          'ordered' => EntityListKind.ordered,
          final other => throw FormatException(
            'A list item is "bullet" or "ordered".',
            other,
          ),
        };
        return switch (json['depth']) {
          final int depth
              when depth >= 0 && depth <= EntityKind$List.maxDepth =>
            EntityKind.list(listKind: listKind, depth: depth),
          final other => throw FormatException(
            'A list item is nested 0 to ${EntityKind$List.maxDepth} levels.',
            other,
          ),
        };
    }
    for (final style in EntityStyle.values) {
      if (style.name == name) return EntityKind.style(style);
    }
    return null;
  }

  static String _requireString(Map<Object?, Object?> json, String field) {
    if (json[field] case final String value when value.isNotEmpty) return value;
    throw FormatException('An entity needs a non-empty "$field".', json);
  }

  @override
  bool operator ==(Object other) =>
      other is Entity &&
      other.offset == offset &&
      other.length == length &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(offset, length, kind);

  @override
  String toString() => 'Entity($offset, $length, $kind)';
}

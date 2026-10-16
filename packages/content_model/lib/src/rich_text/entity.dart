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
  /// kind: `url` (link), `id` (mention) or `key` (inline content, the
  /// [ContentKey.encoded] string). Styles use their enum name as `kind`;
  /// the other kinds use `link`, `mention` and `inlineContent`.
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
    },
  };

  /// The entity [json] describes, or null when its `kind` is not one this
  /// version knows, so data written by a newer version still loads without
  /// the formatting that cannot be read.
  ///
  /// Throws a [FormatException] when [json] is not shaped like [toJson]'s
  /// output for a known kind.
  static Entity? fromJson(Object? json) {
    if (json is! Map<Object?, Object?>) {
      throw FormatException('An entity must be a JSON object.', json);
    }
    final kind = _kindFromJson(json);
    if (kind == null) return null;
    final offset = json['offset'];
    final length = json['length'];
    if (offset is! int || length is! int || offset < 0 || length <= 0) {
      throw FormatException('An entity needs a valid offset and length.', json);
    }
    return Entity(offset, length, kind);
  }

  static const String _link = 'link';
  static const String _mention = 'mention';
  static const String _inlineContent = 'inlineContent';

  static EntityKind? _kindFromJson(Map<Object?, Object?> json) {
    final name = json['kind'];
    if (name is! String) {
      throw FormatException('An entity needs a kind.', json);
    }
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
    }
    for (final style in EntityStyle.values) {
      if (style.name == name) return EntityKind.style(style);
    }
    return null;
  }

  static String _requireString(Map<Object?, Object?> json, String field) {
    final value = json[field];
    if (value is! String || value.isEmpty) {
      throw FormatException('An entity needs a non-empty "$field".', json);
    }
    return value;
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

import 'package:content_model/content_model.dart'
    as model
    show Entity, EntityKind$InlineContent, RichText;
import 'package:content_model/content_model.dart' show ContentKey$Unicode;
import 'package:content_model/markdown.dart';

/// The host's conversion between the composer's `RichText` and a message's
/// markdown body (ADR 017: bodies stay markdown; there are no parallel entity
/// offsets).
///
/// Only the two moments a body crosses it are named: [encode] when a message
/// is sent or an edit saved, [decode] when a message is loaded back into the
/// composer to be edited. Neither detects bare URLs or names; body linkify is
/// the host's separate, explicit step (`ChatBodyLinkifyUtil`).
abstract final class ChatBodyMarkdown {
  /// The markdown body to send for [text], without surrounding blanks.
  ///
  /// A unicode emoji travels as its own characters: the viewport paints no
  /// inline embed yet, and every viewer draws the characters. Any other
  /// inline content keeps its `![alt](scheme:id)` form, with the alt text as
  /// the label.
  static String encode(model.RichText text) {
    final kept = [
      for (final entity in text.entities)
        if (!_isUnicodeEmoji(entity)) entity,
    ];
    return RichTextMarkdown.encode(model.RichText(text.plain, kept)).trim();
  }

  /// The `RichText` for editing the message whose body is [markdown].
  ///
  /// An emoji sent as characters is plain text again; an inline reference
  /// written by another client comes back as an inline content entity.
  static model.RichText decode(String markdown) =>
      RichTextMarkdown.decode(markdown);

  static bool _isUnicodeEmoji(model.Entity entity) => switch (entity.kind) {
    model.EntityKind$InlineContent(:final key) => key is ContentKey$Unicode,
    _ => false,
  };
}

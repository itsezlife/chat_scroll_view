import 'package:content_model/content_model.dart'
    as model
    show
        Entity,
        EntityKind$Hashtag,
        EntityKind$InlineContent,
        EntityKind$Link,
        EntityKind$Mention,
        EntityKind$Username,
        RichText;
import 'package:content_model/content_model.dart'
    show
        ContentKey$Unicode,
        DetectionPolicy,
        EmojiOnlyText,
        EntityDetection,
        TypedMarkdown;
import 'package:content_model/markdown.dart';
import 'package:meta/meta.dart';

/// The host's conversion between the composer's `RichText` and a message's
/// markdown body (ADR 017: bodies stay markdown; there are no parallel entity
/// offsets), and the three moments detection runs in.
///
/// | Moment | Step | Detects |
/// | --- | --- | --- |
/// | a message is sent or an edit saved | [send] | converts typed markers, then detects, then encodes |
/// | a message is materialised from a stored body | [received] | once, only for a body with no link-class entity |
/// | a message is loaded into the composer to edit | [decodeForEdit] | no: it strips what detection made |
/// | a draft is stored or restored | [encodeDraft], [decodeDraft] | no: the composer's text as it is |
///
/// Detection never runs on paint, a keystroke or a mount (ADR 017): [send]
/// runs it once per send, and [received] once when the message model is made;
/// the model keeps the result.
abstract final class ChatBodyMarkdown {
  /// What this host detects: web URLs and emails, `@name` and `#tag`.
  ///
  /// One constant for [send], [received] and [decodeForEdit], because
  /// `EntityDetection.strip` must be given the policy that detected what it
  /// removes.
  static const DetectionPolicy policy = DetectionPolicy();

  /// How many times [received] has run the detector. A test counts it to show
  /// detection happens once per message and not per mount.
  @visibleForTesting
  static int detectionRuns = 0;

  /// The markdown body to send for [text] (which the composer already
  /// downgraded for unresolved mentions): typed markers (`` `code` ``,
  /// `**bold**`, ...) made into entities, then bare URLs, `@name` and `#tag`
  /// under [policy], then [encode]. Markers go first so a URL typed inside
  /// code is seen as code.
  static String send(model.RichText text) =>
      encode(EntityDetection.apply(TypedMarkdown.apply(text), policy));

  /// The markdown body to send for [text], without surrounding blanks (unless
  /// it is nothing but emoji) and without detecting anything ([send] detects
  /// first).
  ///
  /// A unicode emoji travels as its own characters: every viewer draws the
  /// characters, and a receiver finds an emoji-only message from them
  /// (`EmojiOnlyText.of`, which allows only document-keyed inline content). Any
  /// other inline content keeps its `![alt](scheme:id)` form, with the alt text
  /// as the label.
  ///
  /// An emoji-only text is not trimmed, as in the reference client: the blank lines and spaces around its emoji are an
  /// arrangement the sender chose, and the receiver's layout honours them.
  static String encode(model.RichText text) {
    final kept = model.RichText(text.plain, [
      for (final entity in text.entities)
        if (!_isUnicodeEmoji(entity)) entity,
    ]);
    final body = RichTextMarkdown.encode(kept);
    return EmojiOnlyText.of(kept) == null ? body.trim() : body;
  }

  /// The body to materialise a message from, given the [body] a source
  /// stored or delivered.
  ///
  /// A body that already carries a link, a mention, a username or a hashtag
  /// was made by a client that knew what it linked, and is trusted as it is:
  /// a second bare URL in it stays text. A body with none (an older message,
  /// another client, an imported one) goes through the detector once, here,
  /// and the caller keeps the result with the message. A body detection finds
  /// nothing in comes back as it was, not re-encoded.
  static String received(String body) {
    if (body.isEmpty) return body;
    final decoded = RichTextMarkdown.decode(body);
    if (decoded.entities.any(_isLinkClass)) return body;
    detectionRuns++;
    final detected = EntityDetection.apply(decoded, policy);
    // `apply` hands back its argument when it adds nothing.
    return identical(detected, decoded)
        ? body
        : RichTextMarkdown.encode(detected);
  }

  /// The `RichText` as stored: every entity the body spells, detected or not.
  ///
  /// An emoji sent as characters is plain text again; an inline reference
  /// written by another client comes back as an inline content entity.
  static model.RichText decode(String markdown) =>
      RichTextMarkdown.decode(markdown);

  /// The `RichText` for editing the message whose body is [markdown]: [decode]
  /// without the entities detection made.
  ///
  /// A link whose text is its own URL, a username and a hashtag are plain text
  /// in the composer, as when they were typed; [send] makes them again on
  /// save. A link the user made (its text is not its URL), a mention and the
  /// styles stay.
  static model.RichText decodeForEdit(String markdown) =>
      EntityDetection.strip(decode(markdown), policy);

  /// The markdown a draft is stored as: the composer's text exactly, with no
  /// detection, no trim, and every inline reference (a unicode emoji too)
  /// kept as a reference. [decodeDraft] is its inverse, so a draft restores
  /// to what the composer held.
  static String encodeDraft(model.RichText text) =>
      RichTextMarkdown.encode(text);

  /// The `RichText` a stored draft restores to the composer.
  static model.RichText decodeDraft(String markdown) =>
      RichTextMarkdown.decode(markdown);

  static bool _isUnicodeEmoji(model.Entity entity) => switch (entity.kind) {
    model.EntityKind$InlineContent(:final key) => key is ContentKey$Unicode,
    _ => false,
  };

  static bool _isLinkClass(model.Entity entity) => switch (entity.kind) {
    model.EntityKind$Link() ||
    model.EntityKind$Mention() ||
    model.EntityKind$Username() ||
    model.EntityKind$Hashtag() => true,
    _ => false,
  };
}

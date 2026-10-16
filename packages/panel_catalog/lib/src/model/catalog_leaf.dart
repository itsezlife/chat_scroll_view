import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';
import 'package:panel_catalog/src/model/catalog_glyph_box.dart';

/// How a cell stands in for its content until the content can be drawn.
///
/// Derived from the descriptor facts of a leaf ([CatalogLeaf.placeholderStyle]);
/// a leaf never stores it, and a paint mode never lives on the leaf at all.
enum CatalogPlaceholderStyle {
  /// A filled circle in the glyph box: a glyph that is not drawable yet.
  circle,

  /// A silhouette of the content's thumbnail: animated or custom media.
  thumbFirst,

  /// A shaped wash: a sticker.
  shapedWash,
}

/// One cell of a [CatalogSection], as a value.
///
/// A leaf is the identity of the content ([key]), the descriptor facts the
/// viewport needs to ask the asset cache for it and to paint a stand-in before
/// it arrives ([semanticKind], [mediaForm], [animated], [tintable], [sizeHint]),
/// the name a screen reader speaks for it ([spokenName]), and an opaque host
/// [tag]. It carries no readiness, no paint mode and no atlas or sprite state:
/// those are projected at paint time from the asset binding, and storing them
/// here would make a second write model that goes stale when readiness flips.
///
/// Equality covers [key], the facts and the [spokenName] (a republished
/// snapshot in another language is a different catalog). The [tag] is excluded from equality and
/// is never painted: it lets the host that built a leaf recognise it again in a
/// hit ([CatalogLeafHit.leaf]) without a side map keyed by leaf instance, and a
/// republished snapshot whose leaves differ only by tag is the same catalog.
///
/// The same [key] may appear in several sections, or twice in one. A leaf says
/// _what_ is shown; _which cell_ was hit is [CatalogLeafHit.sectionId] and
/// [CatalogLeafHit.index].
@immutable
final class CatalogLeaf {
  /// Creates a leaf for [key] with the descriptor facts the host has.
  ///
  /// Facts left at their defaults make the stand-in the thumbnail silhouette
  /// ([CatalogPlaceholderStyle.thumbFirst]).
  const CatalogLeaf({
    required this.key,
    this.semanticKind = SemanticKind.unknown,
    this.mediaForm = MediaForm.unknown,
    this.animated = false,
    this.tintable = false,
    this.sizeHint,
    this.spokenName,
    this.tag,
  });

  /// Creates a unicode emoji leaf for the exact [glyph] sequence.
  ///
  /// [glyph] is one or more code points (ZWJ sequences allowed) and must not be
  /// empty. The leaf is a [MediaForm.glyph] of kind
  /// [SemanticKind.unicodeEmoji]: its stand-in is a circle. [spokenName] is the
  /// name in the active language, when the host has one.
  CatalogLeaf.unicode(String glyph, {this.spokenName, this.tag})
    : key = ContentKey.unicode(glyph),
      semanticKind = SemanticKind.unicodeEmoji,
      mediaForm = MediaForm.glyph,
      animated = false,
      tintable = false,
      sizeHint = null;

  /// Creates a document-backed leaf (custom emoji, sticker, GIF) for the
  /// opaque [documentId], which must not be empty.
  CatalogLeaf.document(
    String documentId, {
    this.semanticKind = SemanticKind.unknown,
    this.mediaForm = MediaForm.unknown,
    this.animated = false,
    this.tintable = false,
    this.sizeHint,
    this.spokenName,
    this.tag,
  }) : key = ContentKey.document(documentId);

  /// Creates the leaf of [descriptor]: its key, paint facts and spoken name.
  /// The rest of the descriptor (thumbnail, flags) is the host's to use
  /// elsewhere.
  CatalogLeaf.fromDescriptor(ContentDescriptor descriptor, {this.tag})
    : key = descriptor.key,
      semanticKind = descriptor.semanticKind,
      mediaForm = descriptor.mediaForm,
      animated = descriptor.animated,
      tintable = descriptor.tintable,
      sizeHint = descriptor.size,
      spokenName = descriptor.spokenName;

  /// The identity of the content.
  final ContentKey key;

  /// What the content is; picks the stand-in for non-glyph content.
  final SemanticKind semanticKind;

  /// How the content is drawn once it arrives.
  final MediaForm mediaForm;

  /// Whether the content animates.
  final bool animated;

  /// Whether the content is a template the surface tints: the viewport asks
  /// the cache for its alpha only (`AssetDecodeMode.template`), so one decode
  /// serves every colour.
  final bool tintable;

  /// Intrinsic size of the content, when the host knows it.
  final ContentSize? sizeHint;

  /// The name read aloud for this content in the active language, or null when
  /// the data has none (see [semanticLabel] for what is read then).
  final String? spokenName;

  /// Opaque host data, excluded from equality and never painted.
  final Object? tag;

  /// What a screen reader says for this leaf: the [spokenName]; failing that
  /// the glyph itself for a unicode emoji (the plain-text alternative, which the
  /// platform reads in its own language); failing that nothing. Never a guessed
  /// name.
  String? get semanticLabel =>
      spokenName ??
      switch (key) {
        ContentKey$Unicode(:final sequence) => sequence,
        _ => null,
      };

  /// The box this leaf's content is drawn in unless its section says
  /// otherwise: a sticker, mask or GIF fills its cell, everything else (a glyph,
  /// custom or animated emoji) is drawn in the glyph box.
  CatalogContentBox get contentBox => switch (semanticKind) {
    SemanticKind.sticker ||
    SemanticKind.mask ||
    SemanticKind.gif => CatalogContentBox.cell,
    _ => CatalogContentBox.glyph,
  };

  /// The stand-in for this leaf's content, from [mediaForm] and
  /// [semanticKind]: a glyph is a circle, a sticker a shaped wash, anything
  /// else the thumbnail silhouette. A unicode [key] is a glyph whatever the
  /// facts say.
  CatalogPlaceholderStyle get placeholderStyle {
    if (mediaForm == MediaForm.glyph) return CatalogPlaceholderStyle.circle;
    if (key case ContentKey$Unicode()) return CatalogPlaceholderStyle.circle;
    return switch (semanticKind) {
      SemanticKind.sticker ||
      SemanticKind.mask => CatalogPlaceholderStyle.shapedWash,
      _ => CatalogPlaceholderStyle.thumbFirst,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is CatalogLeaf &&
      other.key == key &&
      other.semanticKind == semanticKind &&
      other.mediaForm == mediaForm &&
      other.animated == animated &&
      other.tintable == tintable &&
      other.sizeHint == sizeHint &&
      other.spokenName == spokenName;

  @override
  int get hashCode => Object.hash(
    key,
    semanticKind,
    mediaForm,
    animated,
    tintable,
    sizeHint,
    spokenName,
  );

  @override
  String toString() => 'CatalogLeaf($key)';
}

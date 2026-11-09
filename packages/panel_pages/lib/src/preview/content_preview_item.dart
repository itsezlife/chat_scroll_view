import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:panel_catalog/panel_catalog.dart';

/// What a content preview shows, which decides its size, its gestures and
/// its menu.
///
/// A unicode emoji is never previewed: it has no kind here
/// ([ContentPreviewKind.of] answers null), as the reference client previews
/// only an emoji cell that holds a custom emoji.
enum ContentPreviewKind {
  /// A sticker or a mask: drawn at a fraction of the screen, switched by
  /// sliding over other cells, with the sticker menu.
  sticker,

  /// A GIF: drawn nearly as wide as the screen with rounded corners; sliding
  /// up opens its menu instead of switching cells.
  gif,

  /// A custom emoji: drawn like a sticker, with the emoji menu.
  customEmoji;

  /// The kind content of [kind] is previewed as, or null for content that
  /// never is.
  static ContentPreviewKind? of(SemanticKind kind) => switch (kind) {
    SemanticKind.sticker || SemanticKind.mask => ContentPreviewKind.sticker,
    SemanticKind.gif => ContentPreviewKind.gif,
    SemanticKind.customEmoji => ContentPreviewKind.customEmoji,
    SemanticKind.unicodeEmoji || SemanticKind.unknown => null,
  };
}

/// One piece of content as a content preview shows it: what it is, and what
/// the place it was opened from knows of it.
///
/// A value: two items of one cell are equal, so a finger that slides back
/// onto the cell it came from switches nothing.
@immutable
final class ContentPreviewItem {
  /// An item of [key], content of [semanticKind].
  ///
  /// [semanticKind] must be one [ContentPreviewKind.of] answers for.
  const ContentPreviewItem({
    required this.key,
    required this.semanticKind,
    this.pack,
    this.inRecents = false,
    this.emoji,
    this.size,
    this.spokenName,
  });

  /// The item of a catalogue cell, or null for a cell that is not previewed
  /// (a unicode emoji).
  ///
  /// The cell does not carry the content's pack: the caller passes the pack
  /// it knows ([pack]), and whether the cell is in a recents list
  /// ([inRecents]).
  static ContentPreviewItem? ofLeaf(
    CatalogLeaf leaf, {
    PackId? pack,
    bool inRecents = false,
  }) {
    if (ContentPreviewKind.of(leaf.semanticKind) == null) return null;
    return ContentPreviewItem(
      key: leaf.key,
      semanticKind: leaf.semanticKind,
      pack: pack,
      inRecents: inRecents,
      emoji: leaf.shortcode,
      size: leaf.sizeHint,
      spokenName: leaf.spokenName,
    );
  }

  /// The item of a described piece of content, or null for content that is
  /// not previewed.
  static ContentPreviewItem? ofDescriptor(
    ContentDescriptor descriptor, {
    bool inRecents = false,
  }) {
    if (ContentPreviewKind.of(descriptor.semanticKind) == null) return null;
    return ContentPreviewItem(
      key: descriptor.key,
      semanticKind: descriptor.semanticKind,
      pack: descriptor.pack,
      inRecents: inRecents,
      emoji: descriptor.shortcode,
      size: descriptor.size,
      spokenName: descriptor.spokenName,
    );
  }

  /// Identity of the content.
  final ContentKey key;

  /// What the content is.
  final SemanticKind semanticKind;

  /// The pack the content belongs to, or null: no pack to view, and no
  /// sticker menu at all while the finger is down (the reference opens it
  /// only for a sticker of a set).
  final PackId? pack;

  /// Whether the item was opened from a recents list, which offers to take
  /// it out of there.
  final bool inRecents;

  /// The emoji the content stands for, drawn above it; null for none.
  final String? emoji;

  /// The content's pixel size, which a GIF is fitted by; null for square.
  final ContentSize? size;

  /// What a screen reader says for the content.
  final String? spokenName;

  /// How the content is previewed.
  ContentPreviewKind get kind => ContentPreviewKind.of(semanticKind)!;

  @override
  bool operator ==(Object other) =>
      other is ContentPreviewItem &&
      other.key == key &&
      other.semanticKind == semanticKind &&
      other.pack == pack &&
      other.inRecents == inRecents &&
      other.emoji == emoji &&
      other.size == size &&
      other.spokenName == spokenName;

  @override
  int get hashCode =>
      Object.hash(key, semanticKind, pack, inRecents, emoji, size, spokenName);

  @override
  String toString() =>
      'ContentPreviewItem($key, ${semanticKind.value}, pack: ${pack?.value}'
      '${inRecents ? ', in recents' : ''})';
}

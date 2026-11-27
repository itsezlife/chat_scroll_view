import 'dart:ui';

import 'package:flutter/foundation.dart';

/// How wide a link preview card is (the `cardWidth` rule).
enum LinkPreviewCardWidth {
  /// A card with large media takes the whole budget; any other card its
  /// widest line plus the insets, within it.
  fillBudget,

  /// The media's natural width caps the card; text lines and the button
  /// widen it up to the bubble's constraint.
  fitMedia,

  /// The widest of site name, title, description, media and button, plus
  /// the thumbnail and the padding, capped by the bubble's max width.
  fitContent,
}

/// How a card's media is drawn.
enum LinkPreviewMediaSize {
  /// A fixed thumbnail at the card's top trailing corner, beside the text.
  small,

  /// One box at the card's width, under the text.
  large,
}

/// How a card shows when its page arrives.
enum LinkPreviewAppearForm {
  /// The bubble jumps to its new height: no transition.
  jump,

  /// The card fades in while the bubble grows.
  fade,

  /// The bubble is laid out again, at once.
  relayout,
}

/// A piece of a card's text.
enum LinkPreviewCardPart {
  /// The site's name (part of the card's `body` zone).
  siteName,

  /// The page's title.
  title,

  /// The page's author.
  author,

  /// The page's description, whose links are text links.
  description,
}

/// One piece of a card's text, laid out: where it is drawn, wrapped at the
/// rect's width within [maxLines].
@immutable
final class LinkPreviewCardPiece {
  /// [part] in [rect], at most [maxLines] lines.
  const LinkPreviewCardPiece({
    required this.part,
    required this.rect,
    required this.maxLines,
  });

  /// Which piece.
  final LinkPreviewCardPart part;

  /// Where, in layout coordinates.
  final Rect rect;

  /// Its line limit.
  final int maxLines;

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewCardPiece &&
      other.part == part &&
      other.rect == rect &&
      other.maxLines == maxLines;

  @override
  int get hashCode => Object.hash(part, rect, maxLines);

  @override
  String toString() => 'LinkPreviewCardPiece(${part.name}, $rect)';
}

/// A card's action button: the host's [label] in [rect].
@immutable
final class LinkPreviewCardButton {
  /// The button at [rect] reading [label].
  const LinkPreviewCardButton({required this.rect, required this.label});

  /// Where, in layout coordinates.
  final Rect rect;

  /// The host's label (the button's action is the host's).
  final String label;

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewCardButton &&
      other.rect == rect &&
      other.label == label;

  @override
  int get hashCode => Object.hash(rect, label);
}

/// A link preview card laid out: the tinted block, its text, its media's
/// size, its button, the enlarge button and the time's slot, every rect in
/// layout coordinates.
///
/// The card's media is an ordinary cell of the block
/// (`MediaBlock$LinkPreview.media`), drawn and hit like any other item.
@immutable
final class LinkPreviewCard {
  /// A card in [rect].
  LinkPreviewCard({
    required this.rect,
    required List<LinkPreviewCardPiece> texts,
    this.mediaSize,
    this.button,
    this.enlarge,
    this.timeSlot,
    this.rtl = false,
    this.width = LinkPreviewCardWidth.fillBudget,
    this.appear = LinkPreviewAppearForm.jump,
  }) : texts = List.unmodifiable(texts);

  /// The card [t] of the way from [a] to [b]: rects interpolate by
  /// position in the text and [b]'s pieces, button and slots are kept
  /// where [a] has none.
  factory LinkPreviewCard.lerp(LinkPreviewCard a, LinkPreviewCard b, double t) {
    Rect move(Rect? from, Rect to) =>
        from == null ? to : Rect.lerp(from, to, t)!;
    return LinkPreviewCard(
      rect: move(a.rect, b.rect),
      texts: [
        for (final piece in b.texts)
          LinkPreviewCardPiece(
            part: piece.part,
            rect: move(a.pieceOf(piece.part)?.rect, piece.rect),
            maxLines: piece.maxLines,
          ),
      ],
      mediaSize: b.mediaSize,
      button: switch (b.button) {
        final to? => LinkPreviewCardButton(
          rect: move(a.button?.rect, to.rect),
          label: to.label,
        ),
        null => null,
      },
      enlarge: switch (b.enlarge) {
        final to? => move(a.enlarge, to),
        null => null,
      },
      timeSlot: switch (b.timeSlot) {
        final to? => move(a.timeSlot, to),
        null => null,
      },
      rtl: b.rtl,
      width: b.width,
      appear: b.appear,
    );
  }

  /// The tinted block.
  final Rect rect;

  /// The text pieces, top to bottom.
  final List<LinkPreviewCardPiece> texts;

  /// How the media is drawn; null when the card has none.
  final LinkPreviewMediaSize? mediaSize;

  /// The action button, when the host gives one.
  final LinkPreviewCardButton? button;

  /// The enlarge button over a large photo (desktop), which opens the
  /// viewer; null when there is none.
  final Rect? enlarge;

  /// Where the time goes when the card ends the bubble: its own line under
  /// the card, or inside the card's bottom inset; null when the card does
  /// not end the bubble.
  final Rect? timeSlot;

  /// Whether the chat is right to left: the bar is on the right.
  final bool rtl;

  /// The width rule the card was laid out by (named in diagnostics).
  final LinkPreviewCardWidth width;

  /// How the card shows when its page arrives (named in diagnostics).
  final LinkPreviewAppearForm appear;

  /// Whether the card shows any text.
  bool get hasText => texts.isNotEmpty;

  /// The piece [part], or null.
  LinkPreviewCardPiece? pieceOf(LinkPreviewCardPart part) {
    for (final piece in texts) {
      if (piece.part == part) return piece;
    }
    return null;
  }

  /// This card moved by [offset].
  LinkPreviewCard shift(Offset offset) => LinkPreviewCard(
    rect: rect.shift(offset),
    texts: [
      for (final piece in texts)
        LinkPreviewCardPiece(
          part: piece.part,
          rect: piece.rect.shift(offset),
          maxLines: piece.maxLines,
        ),
    ],
    mediaSize: mediaSize,
    button: switch (button) {
      final b? => LinkPreviewCardButton(
        rect: b.rect.shift(offset),
        label: b.label,
      ),
      null => null,
    },
    enlarge: enlarge?.shift(offset),
    timeSlot: timeSlot?.shift(offset),
    rtl: rtl,
    width: width,
    appear: appear,
  );

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewCard &&
      other.rect == rect &&
      listEquals(other.texts, texts) &&
      other.mediaSize == mediaSize &&
      other.button == button &&
      other.enlarge == enlarge &&
      other.timeSlot == timeSlot &&
      other.rtl == rtl &&
      other.width == width &&
      other.appear == appear;

  @override
  int get hashCode => Object.hash(
    rect,
    Object.hashAll(texts),
    mediaSize,
    button,
    enlarge,
    timeSlot,
    rtl,
    width,
    appear,
  );

  @override
  String toString() => 'LinkPreviewCard($rect, ${mediaSize?.name})';
}

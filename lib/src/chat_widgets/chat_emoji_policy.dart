import 'dart:math' as math;
import 'dart:ui' show Size, TextDirection;

import 'package:catalog_assets/catalog_assets.dart' show AssetPresets;
import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_sizes.dart';
import 'package:content_model/content_model.dart'
    show ContentKey$Document, EmojiOnly;
import 'package:flutter/foundation.dart';

/// Which of the two layouts of `ChatEmojiBody` a message gets.
enum ChatEmojiLayoutKind {
  /// One emoji shown as a sticker, with the reply header beside it where the
  /// platform's policy says so.
  sticker,

  /// Emoji set as enlarged text.
  text,
}

/// Where a reply or forward header goes relative to an emoji-only body.
enum ChatEmojiHeaderPlacement {
  /// In the row above the body.
  above,

  /// In the free column beside the body.
  beside,

  /// Beside the body when the row is wide enough to hold both, else above.
  besideWhenFits,
}

/// What a header takes off the width an emoji-only text wraps at.
///
/// A cap and a reduction, because the platforms differ in kind: one caps the
/// wrap at a share of the screen, another subtracts a fixed width.
@immutable
final class ChatEmojiWrapLimit {
  /// A limit of [cap] and [reduction].
  const ChatEmojiWrapLimit({this.cap = double.infinity, this.reduction = 0});

  /// No limit: the wrap is the row's own width.
  static const ChatEmojiWrapLimit none = ChatEmojiWrapLimit();

  /// The widest a line may be, whatever the row.
  final double cap;

  /// What is taken off the row's width.
  final double reduction;

  /// The width a line wraps at in a row [rowMax] wide.
  ///
  /// An infinite row stays infinite: an intrinsic width measures the items
  /// unwrapped, and the cap applies when the real, finite row is laid out.
  double of(double rowMax) =>
      rowMax.isFinite ? math.min(rowMax - reduction, cap) : rowMax;

  @override
  bool operator ==(Object other) =>
      other is ChatEmojiWrapLimit &&
      other.cap == cap &&
      other.reduction == reduction;

  @override
  int get hashCode => Object.hash(cap, reduction);
}

/// The **emoji-only policy** of a platform family: the sizes, the inset, the
/// cap, the wrap under a header and the direction rule of an emoji-only body,
/// chosen once by the host from the platform it runs as.
///
/// The three families differ almost completely, not only as mobile against
/// desktop, so each is a strategy of its own, like the selection policy:
///
/// - [$Android]: font steps by count, a sticker of a share of the screen's
///   short side, no inset, the header above the text and beside the sticker,
///   the header capping the wrap at a share of the screen, and the chat's
///   sticker permission gating the whole feature;
/// - [$Ios]: a font table by the longer of the longest line and the line count,
///   a fixed sticker in an inset, the header beside both layouts and taking a
///   fixed width off the wrap;
/// - [$Desktop]: fixed image boxes, at most three regular emoji (more is an
///   ordinary bubble), a fixed sticker, the header beside when it fits, and a
///   layout that mirrors in a right-to-left chat.
///
/// Web follows desktop. The policy is pure Dart: it holds the numbers the
/// body lays out with and the host's chrome reads; it paints nothing. Hosts
/// replace nothing on a live body: pass another policy to change it.
@immutable
sealed class ChatEmojiPolicy {
  /// Base constructor for policy variants.
  const ChatEmojiPolicy();

  /// The Android family's policy; [sizes] and [headerWrapFraction] are its
  /// overridable tables.
  const factory ChatEmojiPolicy.android({
    ChatEmojiSizes sizes,
    double headerWrapFraction,
  }) = ChatEmojiPolicy$Android;

  /// The iOS family's policy.
  const factory ChatEmojiPolicy.ios() = ChatEmojiPolicy$Ios;

  /// The desktop family's policy (also the web's).
  const factory ChatEmojiPolicy.desktop() = ChatEmojiPolicy$Desktop;

  /// The policy of the platform the app runs on. Pass [platform] / [isWeb]
  /// to pin it in tests.
  factory ChatEmojiPolicy.forPlatform({TargetPlatform? platform, bool? isWeb}) {
    if (isWeb ?? kIsWeb) return const ChatEmojiPolicy.desktop();
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.fuchsia => const ChatEmojiPolicy.android(),
      TargetPlatform.iOS => const ChatEmojiPolicy.ios(),
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => const ChatEmojiPolicy.desktop(),
    };
  }

  /// The font size, in logical pixels, of the text layout of [emojiOnly].
  double fontSizeFor(EmojiOnly emojiOnly);

  /// The side of one item's square in the text layout: the font size plus
  /// what the asset presets add to it.
  double itemBoxFor(EmojiOnly emojiOnly) =>
      fontSizeFor(emojiOnly) + AssetPresets.emojiOnlyBoxPadding;

  /// The gap between two items of one line in the text layout.
  double itemSkipFor(EmojiOnly emojiOnly) => 0;

  /// The side of the sticker for a [viewport] of that size, without its
  /// [stickerInset].
  double stickerExtentFor(Size viewport);

  /// The margin around a sticker, logical pixels: part of the sticker layout's
  /// box on a platform that draws one, zero on one that does not.
  double get stickerInset;

  /// Whether the platform shows [emojiOnly] as an emoji-only body at all. A
  /// host that sees false shows an ordinary bubble.
  bool admits(EmojiOnly emojiOnly);

  /// Whether the chat's permission to send stickers gates the feature: when it
  /// does, a chat that bans stickers (for a user who is no admin) shows every
  /// emoji-only message as an ordinary bubble.
  bool get gatesOnStickerPermission;

  /// What a header above the text takes off the wrap, for a screen (or chat
  /// column) of [parentWidth].
  ChatEmojiWrapLimit wrapLimitUnderHeader(double parentWidth);

  /// Where a header goes next to a body of [kind].
  ChatEmojiHeaderPlacement headerPlacementFor(ChatEmojiLayoutKind kind);

  /// Whether the layout mirrors in a right-to-left chat. A platform that does
  /// not keeps every side as in a left-to-right chat: an outgoing message
  /// stays at the right, text lines start at the left.
  bool get mirrorsInRtl;

  /// The direction the items flow in, given the surrounding [ambient].
  TextDirection textDirectionFor(TextDirection ambient) =>
      mirrorsInRtl ? ambient : TextDirection.ltr;
}

/// The Android family's [ChatEmojiPolicy].
final class ChatEmojiPolicy$Android extends ChatEmojiPolicy {
  /// Creates the policy over [sizes], wrapping at [headerWrapFraction] of the
  /// parent's width under a header.
  const ChatEmojiPolicy$Android({
    this.sizes = const ChatEmojiSizes(),
    this.headerWrapFraction = 0.65,
  }) : assert(
         headerWrapFraction > 0 && headerWrapFraction <= 1,
         'The wrap fraction is within (0, 1].',
       );

  /// The font steps and the sticker rule.
  final ChatEmojiSizes sizes;

  /// The share of the parent's width the text wraps at under a header.
  final double headerWrapFraction;

  @override
  double fontSizeFor(EmojiOnly emojiOnly) => sizes.fontSizeFor(
    emojiOnly.items.length,
    allCustom: emojiOnly.isAllCustom,
  );

  @override
  double stickerExtentFor(Size viewport) => sizes.stickerExtentFor(viewport);

  @override
  double get stickerInset => 0;

  @override
  bool admits(EmojiOnly emojiOnly) => true;

  @override
  bool get gatesOnStickerPermission => true;

  @override
  ChatEmojiWrapLimit wrapLimitUnderHeader(double parentWidth) =>
      ChatEmojiWrapLimit(cap: parentWidth * headerWrapFraction);

  @override
  ChatEmojiHeaderPlacement headerPlacementFor(ChatEmojiLayoutKind kind) =>
      switch (kind) {
        ChatEmojiLayoutKind.sticker => ChatEmojiHeaderPlacement.beside,
        ChatEmojiLayoutKind.text => ChatEmojiHeaderPlacement.above,
      };

  @override
  bool get mirrorsInRtl => false;

  @override
  bool operator ==(Object other) =>
      other is ChatEmojiPolicy$Android &&
      other.sizes == sizes &&
      other.headerWrapFraction == headerWrapFraction;

  @override
  int get hashCode => Object.hash(sizes, headerWrapFraction);
}

/// The iOS family's [ChatEmojiPolicy].
final class ChatEmojiPolicy$Ios extends ChatEmojiPolicy {
  /// Creates the policy.
  const ChatEmojiPolicy$Ios();

  // 94 pt scaled by 1, .84, .69, .53, .46, .38, .32, .27, .24, .21 and
  // floored, indexed by min(longest line or line count, 10) - 1.
  static const List<double> _fonts = [94, 78, 64, 49, 43, 35, 30, 25, 22, 19];

  /// The sticker's side: `floor(180 * 0.625)`.
  static const double stickerExtent = 112;

  /// The margin around the sticker, on each side.
  static const double inset = 10;

  /// What a header takes off the wrap width.
  static const double headerReduction = 45;

  @override
  double fontSizeFor(EmojiOnly emojiOnly) =>
      _fonts[math.min(emojiOnly.dimension, _fonts.length) - 1];

  @override
  double stickerExtentFor(Size viewport) => stickerExtent;

  @override
  double get stickerInset => inset;

  @override
  bool admits(EmojiOnly emojiOnly) => true;

  @override
  bool get gatesOnStickerPermission => false;

  @override
  ChatEmojiWrapLimit wrapLimitUnderHeader(double parentWidth) =>
      const ChatEmojiWrapLimit(reduction: headerReduction);

  @override
  ChatEmojiHeaderPlacement headerPlacementFor(ChatEmojiLayoutKind kind) =>
      ChatEmojiHeaderPlacement.beside;

  @override
  bool get mirrorsInRtl => false;

  @override
  bool operator ==(Object other) => other is ChatEmojiPolicy$Ios;

  @override
  int get hashCode => (ChatEmojiPolicy$Ios).hashCode;
}

/// The desktop family's [ChatEmojiPolicy].
final class ChatEmojiPolicy$Desktop extends ChatEmojiPolicy {
  /// Creates the policy.
  const ChatEmojiPolicy$Desktop();

  /// A regular emoji's image: 36 px and a 1 px outline on each side.
  static const double imageBox = 38;

  /// The gap between two images of a line.
  static const double imageSkip = 2;

  /// The most regular emoji an emoji-only message holds.
  static const int regularLimit = 3;

  /// The sticker's side.
  static const double stickerExtent = 112;

  // `0.7 * 112` and `0.52 * 112`, rounded as the reference rounds them.
  static const List<double> _customBoxByDimension = [112, 78, 58, 38, 38];

  /// The box of a custom emoji in a message of 6 or 7 along its larger side.
  ///
  /// Unverified: the reference takes it from an emoji-size table that is not
  /// in the checkout. It is not larger than the box a message of 4 or 5 has,
  /// so the isolated value is used.
  static const double unverifiedLargeCustomBox = 38;

  /// The box of a custom emoji in a message of 8 or more along its larger side.
  ///
  /// Unverified (the same table). The smallest box another platform verifies
  /// (Android's smallest font step plus its padding) stands in.
  static const double unverifiedNormalCustomBox = 26.8;

  @override
  double fontSizeFor(EmojiOnly emojiOnly) =>
      itemBoxFor(emojiOnly) - AssetPresets.emojiOnlyBoxPadding;

  @override
  double itemBoxFor(EmojiOnly emojiOnly) {
    if (!emojiOnly.isAllCustom) return imageBox;
    final dimension = emojiOnly.dimension;
    return switch (dimension) {
      <= 5 => _customBoxByDimension[dimension - 1],
      <= 7 => unverifiedLargeCustomBox,
      _ => unverifiedNormalCustomBox,
    };
  }

  @override
  double itemSkipFor(EmojiOnly emojiOnly) =>
      emojiOnly.isAllCustom ? 0 : imageSkip;

  @override
  double stickerExtentFor(Size viewport) => stickerExtent;

  @override
  double get stickerInset => 0;

  @override
  bool admits(EmojiOnly emojiOnly) =>
      emojiOnly.isAllCustom || emojiOnly.items.length <= regularLimit;

  @override
  bool get gatesOnStickerPermission => false;

  @override
  ChatEmojiWrapLimit wrapLimitUnderHeader(double parentWidth) =>
      ChatEmojiWrapLimit.none;

  @override
  ChatEmojiHeaderPlacement headerPlacementFor(ChatEmojiLayoutKind kind) =>
      ChatEmojiHeaderPlacement.besideWhenFits;

  @override
  bool get mirrorsInRtl => true;

  @override
  bool operator ==(Object other) => other is ChatEmojiPolicy$Desktop;

  @override
  int get hashCode => (ChatEmojiPolicy$Desktop).hashCode;
}

/// What the policies read from an emoji-only message.
extension on EmojiOnly {
  /// Whether every item is a custom emoji (a document).
  bool get isAllCustom =>
      items.every((item) => item.key is ContentKey$Document);

  /// The larger of the longest line and the number of lines.
  int get dimension {
    var lines = 1;
    var longest = 0;
    var current = 0;
    for (var i = 0; i < items.length; i++) {
      final breaks = items[i].lineBreaksBefore;
      if (i > 0 && breaks > 0) {
        lines += breaks;
        current = 0;
      }
      longest = math.max(longest, ++current);
    }
    return math.max(lines, longest);
  }
}

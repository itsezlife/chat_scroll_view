import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:catalog_assets/catalog_assets.dart' show AssetPresets;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:meta/meta.dart';

/// The Android family's sizes of an emoji-only body, as a value the host may
/// override through `ChatEmojiPolicy.android`.
///
/// ## Text layout
///
/// A font step is chosen by how many items the message has and by whether
/// every one of them is a custom emoji: a
/// custom emoji is drawn from an image, so a message of them takes one step
/// larger than one that holds a unicode glyph. The default tables are
/// the reference client's (its size percentages of 120 dp):
///
/// | Items | All custom | Otherwise |
/// | --- | --- | --- |
/// | 1-2 | 81.6 | 40.8 |
/// | 3 | 55.2 | 33.6 |
/// | 4 | 40.8 | 26.4 |
/// | 5 | 33.6 | 22.8 |
/// | 6 | 26.4 | 22.8 |
/// | 7 and more | 22.8 | 22.8 |
///
/// An item takes a square of its font size plus [boxPadding] (4 dp). The
/// steps do not depend on the text scale: a reader who enlarged the text
/// still sees the emoji at the reference size.
///
/// ## Sticker layout
///
/// A lone emoji is a sticker of `min(viewport width, height) ×
/// [stickerViewportFraction] × [stickerZoom]` (112.5 dp on a 360 dp phone;
/// the zoom is the server's animated-emoji zoom). The reference client's phone
/// rule is kept as it is: on a wide window the same rule gives a larger
/// sticker, and a host that wants a cap passes its own fractions.
///
/// The margin around a sticker and the wrap under a header are not sizes but
/// the platform's policy (`ChatEmojiPolicy`): they differ by platform, where
/// these tables are one platform's.
@immutable
final class ChatEmojiSizes {
  /// Creates the sizes; the defaults are the reference client's.
  ///
  /// [allCustomSteps] and [mixedSteps] hold, for the counts 1 to 6 and then
  /// 7 and more, an index into [fontSteps].
  const ChatEmojiSizes({
    this.fontSteps = androidFontSteps,
    this.allCustomSteps = _androidAllCustomSteps,
    this.mixedSteps = _androidMixedSteps,
    this.stickerViewportFraction = 0.5,
    this.stickerZoom = 0.625,
  }) : assert(stickerViewportFraction > 0 && stickerZoom > 0, 'The sticker rule takes positive fractions.');

  /// The reference client's six font steps in dp, largest first.
  static const List<double> androidFontSteps = [81.6, 55.2, 40.8, 33.6, 26.4, 22.8];

  // Indexed by min(count, 7) - 1, into [androidFontSteps].
  static const List<int> _androidAllCustomSteps = [0, 0, 1, 2, 3, 4, 5];
  static const List<int> _androidMixedSteps = [2, 2, 3, 4, 5, 5, 5];
  static const int _countClasses = 7;

  /// The font sizes, in logical pixels.
  final List<double> fontSteps;

  /// Per count (1 to 6, then 7 and more), the index in [fontSteps] of a
  /// message whose every item is a custom emoji.
  final List<int> allCustomSteps;

  /// The same for a message with at least one unicode emoji.
  final List<int> mixedSteps;

  /// The share of the viewport's short side a sticker starts from.
  final double stickerViewportFraction;

  /// The factor applied to that share.
  final double stickerZoom;

  /// What an item's box adds to its font size.
  double get boxPadding => AssetPresets.emojiOnlyBoxPadding;

  /// The font size of the text layout for [count] items.
  double fontSizeFor(int count, {required bool allCustom}) {
    assert(count > 0, 'A message has at least one item.');
    assert(
      allCustomSteps.length == _countClasses && mixedSteps.length == _countClasses,
      'A step table has one entry for each of the counts 1 to 6 and 7+.',
    );
    final table = allCustom ? allCustomSteps : mixedSteps;
    return fontSteps[table[math.min(count, _countClasses) - 1]];
  }

  /// The side of one item's square in the text layout.
  double itemBoxFor(int count, {required bool allCustom}) => fontSizeFor(count, allCustom: allCustom) + boxPadding;

  /// The side of the sticker for a [viewport] of that size.
  double stickerExtentFor(Size viewport) => viewport.shortestSide * stickerViewportFraction * stickerZoom;

  @override
  bool operator ==(Object other) =>
      other is ChatEmojiSizes &&
      listEquals(other.fontSteps, fontSteps) &&
      listEquals(other.allCustomSteps, allCustomSteps) &&
      listEquals(other.mixedSteps, mixedSteps) &&
      other.stickerViewportFraction == stickerViewportFraction &&
      other.stickerZoom == stickerZoom;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(fontSteps),
    Object.hashAll(allCustomSteps),
    Object.hashAll(mixedSteps),
    stickerViewportFraction,
    stickerZoom,
  );
}

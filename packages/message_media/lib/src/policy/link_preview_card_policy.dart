import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart'
    show ChromeInkBounce, ChromeInkInset, ChromeInkKind, ChromeInkScale;
import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart';
import 'package:message_media/src/diagnostics/media_trace.dart';
import 'package:message_media/src/layout/link_preview_card.dart';
import 'package:message_media/src/layout/media_corner_radii.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:message_media/src/layout/media_layout_text.dart';
import 'package:message_media/src/policy/media_box_sizing.dart';
import 'package:meta/meta.dart';

// --- Choices ---

/// Where the message's time goes when the card ends the bubble.
enum LinkPreviewTimePlacement {
  /// A line of its own under the card.
  ownLine,

  /// Inside the card's bottom inset.
  insideCard,
}

// --- Values ---

/// The tinted block the card is drawn as: the quote and reply block's
/// values (a bar on the leading edge, an accent fill, rounded corners).
@immutable
final class LinkPreviewBlockStyle {
  /// A block with a [barWidth] bar, filled at [fillOpacity] of the accent,
  /// with [radius] corners.
  const LinkPreviewBlockStyle({
    required this.barWidth,
    required this.fillOpacity,
    required this.radius,
    double? fillOpacityOutgoingDark,
  }) : fillOpacityOutgoingDark = fillOpacityOutgoingDark ?? fillOpacity;

  /// Android: bar 3, fill 0.10 (0.12 for an outgoing message in a dark
  /// theme), radius 5.
  static const android = LinkPreviewBlockStyle(
    barWidth: 3,
    fillOpacity: 0.10,
    fillOpacityOutgoingDark: 0.12,
    radius: 5,
  );

  /// iOS: bar 3, fill 0.1, radius 4.
  static const ios = LinkPreviewBlockStyle(
    barWidth: 3,
    fillOpacity: 0.1,
    radius: 4,
  );

  /// Desktop: bar 3, fill 0.12, radius 5.
  static const desktop = LinkPreviewBlockStyle(
    barWidth: 3,
    fillOpacity: 0.12,
    radius: 5,
  );

  /// The bar's width, on the leading edge.
  final double barWidth;

  /// The fill's share of the accent.
  final double fillOpacity;

  /// The fill's share for an outgoing message in a dark theme.
  final double fillOpacityOutgoingDark;

  /// The block's corner radius.
  final double radius;

  /// The fill's share for a message [outgoing] in a [dark] theme or not.
  double fillOpacityFor({required bool outgoing, required bool dark}) =>
      outgoing && dark ? fillOpacityOutgoingDark : fillOpacity;

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewBlockStyle &&
      other.barWidth == barWidth &&
      other.fillOpacity == fillOpacity &&
      other.fillOpacityOutgoingDark == fillOpacityOutgoingDark &&
      other.radius == radius;

  @override
  int get hashCode =>
      Object.hash(barWidth, fillOpacity, fillOpacityOutgoingDark, radius);
}

/// The type of a card's text and button and each piece's line limit.
@immutable
final class LinkPreviewCardText {
  /// Type of the given sizes, weights and limits.
  const LinkPreviewCardText({
    required this.size,
    required this.siteWeight,
    required this.titleWeight,
    required this.siteLines,
    required this.titleLines,
    required this.descriptionLines,
    this.authorLines = 1,
    this.descriptionLinesCompact,
    this.lineBudget,
    this.buttonSize,
    this.buttonWeight = FontWeight.w600,
  });

  /// Android: 14 at the default size, site name and title bold; site name 1
  /// line, title 4, description 6 (3 in compact mode).
  static const android = LinkPreviewCardText(
    size: 14,
    siteWeight: FontWeight.bold,
    titleWeight: FontWeight.bold,
    siteLines: 1,
    titleLines: 4,
    descriptionLines: 6,
    descriptionLinesCompact: 3,
  );

  /// iOS: 14 at base 17, semibold site name and title; site name 2 lines,
  /// title 5, description 12; the button semibold 14.
  static const ios = LinkPreviewCardText(
    size: 14,
    siteWeight: FontWeight.w600,
    titleWeight: FontWeight.w600,
    siteLines: 2,
    titleLines: 5,
    descriptionLines: 12,
    buttonSize: 14,
  );

  /// Desktop: semibold site name and title, normal text; site name 1 line,
  /// title up to 2, the description the rest of a 5-line budget.
  static const desktop = LinkPreviewCardText(
    size: 13,
    siteWeight: FontWeight.w600,
    titleWeight: FontWeight.w600,
    siteLines: 1,
    titleLines: 2,
    descriptionLines: 5,
    lineBudget: 5,
  );

  /// The font size of every piece.
  final double size;

  /// The site name's weight.
  final FontWeight siteWeight;

  /// The title's weight.
  final FontWeight titleWeight;

  /// The site name's line limit.
  final int siteLines;

  /// The title's line limit.
  final int titleLines;

  /// The author's line limit.
  final int authorLines;

  /// The description's line limit.
  final int descriptionLines;

  /// The description's limit in compact mode; null is [descriptionLines].
  final int? descriptionLinesCompact;

  /// The lines every piece shares; null is no shared budget.
  final int? lineBudget;

  /// The action button's size; null is [size].
  final double? buttonSize;

  /// The action button's weight.
  final FontWeight buttonWeight;

  /// The style of a piece of [weight] over [base].
  TextStyle over(TextStyle base, {FontWeight weight = FontWeight.normal}) =>
      base.copyWith(fontSize: size, fontWeight: weight);

  /// The button's style over [base].
  TextStyle buttonOver(TextStyle base) =>
      base.copyWith(fontSize: buttonSize ?? size, fontWeight: buttonWeight);

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewCardText &&
      other.size == size &&
      other.siteWeight == siteWeight &&
      other.titleWeight == titleWeight &&
      other.siteLines == siteLines &&
      other.titleLines == titleLines &&
      other.authorLines == authorLines &&
      other.descriptionLines == descriptionLines &&
      other.descriptionLinesCompact == descriptionLinesCompact &&
      other.lineBudget == lineBudget &&
      other.buttonSize == buttonSize &&
      other.buttonWeight == buttonWeight;

  @override
  int get hashCode => Object.hash(
    size,
    siteWeight,
    titleWeight,
    siteLines,
    titleLines,
    authorLines,
    descriptionLines,
    descriptionLinesCompact,
    lineBudget,
    buttonSize,
    buttonWeight,
  );
}

/// A card's geometry: where it sits in the bubble, its insets and gaps,
/// its thumbnail, its large media, its button.
@immutable
final class LinkPreviewCardMetrics {
  /// Metrics of the given values.
  const LinkPreviewCardMetrics({
    required this.outerLeft,
    required this.outerRight,
    required this.outerTop,
    required this.outerTopFirst,
    required this.textInset,
    required this.largeMediaInset,
    required this.siteToTitle,
    required this.titleToAuthor,
    required this.toDescription,
    required this.textToMedia,
    required this.mediaToButton,
    required this.bottomPadding,
    required this.thumbnailGap,
    required this.thumbnailTrailingInset,
    required this.thumbnailTopInset,
    required this.thumbnailRadius,
    required this.mediaRadius,
    required this.buttonHeight,
    double? outerLeftIncomingText,
    this.outerRightOutgoingText = 0,
    this.outerBottom = 0,
    this.bottomExtraWithMediaAndText = 0,
    this.thumbnailSize,
    this.descriptionNarrowExtra = 0,
    this.minHeightWithThumbnail = 0,
    this.largeMediaHeightShare,
    this.largeMediaHeightShareDocument,
    this.largeMediaMinHeight = 0,
    this.largeMediaZeroSide = 150,
    this.buttonGap = 0,
    this.buttonDividerWidth = 0,
    this.buttonDividerOpacity = 0,
    this.buttonPadding = EdgeInsets.zero,
    this.maxWidth,
  }) : outerLeftIncomingText = outerLeftIncomingText ?? outerLeft;

  /// Android: the card at bubble left + 12 (+ 18 in an incoming text
  /// bubble) − 1.33 and bubble right − 10 (− 6 more in an outgoing text
  /// bubble with a tail), 6 above its first line; text at x + 10, large
  /// media at x + 10 and card − 17 wide; site → title 4, → author and
  /// description 2, → media 2; bottom 6 (+ 2.66 with media and text); a
  /// 48 thumbnail 6 from the right with a 10 margin (the description 20),
  /// a 50 minimum height; large media at most a third of the display
  /// (half for documents), at least 60, 150 without a size; media corners
  /// 4; the button under a 0.66 hairline at 18 %, 42 more height.
  static const android = LinkPreviewCardMetrics(
    outerLeft: 12 - 1.33,
    outerLeftIncomingText: 18 - 1.33,
    outerRight: 10,
    outerRightOutgoingText: 6,
    outerTop: 4,
    outerTopFirst: 4,
    textInset: EdgeInsets.fromLTRB(10, 6, 7, 0),
    largeMediaInset: EdgeInsets.fromLTRB(10, 0, 7, 0),
    siteToTitle: 4,
    titleToAuthor: 2,
    toDescription: 2,
    textToMedia: 2,
    mediaToButton: 6,
    bottomPadding: 6,
    bottomExtraWithMediaAndText: 2.66,
    thumbnailSize: 48,
    thumbnailGap: 10,
    thumbnailTrailingInset: 6,
    thumbnailTopInset: 6,
    thumbnailRadius: 4,
    descriptionNarrowExtra: 10,
    minHeightWithThumbnail: 50,
    largeMediaHeightShare: 1 / 3,
    largeMediaHeightShareDocument: 1 / 2,
    largeMediaMinHeight: 60,
    mediaRadius: 4,
    buttonHeight: 42,
    buttonDividerWidth: 0.66,
    buttonDividerOpacity: 0.18,
  );

  /// iOS: text inset 11 a side (10 on a regular width class) in the node,
  /// 11 above when the card is first; inside, left 20 and right 17 with the
  /// bar, text top and bottom 3, text ↔ media 6, media top and bottom 6,
  /// → button 7; a 54 thumbnail 6 from the top and trailing edge, corner
  /// 4, a 66 minimum; media corners 4; the button 36 high.
  static const ios = LinkPreviewCardMetrics(
    outerLeft: 11,
    outerRight: 11,
    outerTop: 0,
    outerTopFirst: 11,
    textInset: EdgeInsets.fromLTRB(20, 3, 17, 3),
    largeMediaInset: EdgeInsets.fromLTRB(20, 6, 17, 6),
    siteToTitle: 0,
    titleToAuthor: 0,
    toDescription: 0,
    textToMedia: 6,
    mediaToButton: 7,
    bottomPadding: 3,
    thumbnailSize: 54,
    thumbnailGap: 6,
    thumbnailTrailingInset: 6,
    thumbnailTopInset: 6,
    thumbnailRadius: 4,
    minHeightWithThumbnail: 6 + 54 + 6,
    mediaRadius: 4,
    buttonGap: 7,
    buttonHeight: 36,
  );

  /// Desktop: the message padding (11, 8, 11, 8), 11 above only when
  /// first; block padding (10, 5, 7, 7); 5 before the media; a thumbnail as
  /// tall as the text up to the line budget, gap 8, small rounding (3);
  /// media corners 3; the button 36 high, padding (13, 8, 13, 8), a 1 px
  /// line at 30 % of the accent; capped at 430.
  static const desktop = LinkPreviewCardMetrics(
    outerLeft: 11,
    outerRight: 11,
    outerTop: 0,
    outerTopFirst: 11,
    outerBottom: 8,
    textInset: EdgeInsets.fromLTRB(10, 5, 7, 0),
    largeMediaInset: EdgeInsets.fromLTRB(10, 0, 7, 0),
    siteToTitle: 0,
    titleToAuthor: 0,
    toDescription: 0,
    textToMedia: 5,
    mediaToButton: 0,
    bottomPadding: 7,
    thumbnailGap: 8,
    thumbnailTrailingInset: 7,
    thumbnailTopInset: 5,
    thumbnailRadius: 3,
    mediaRadius: 3,
    buttonHeight: 36,
    buttonDividerWidth: 1,
    buttonDividerOpacity: 0.3,
    buttonPadding: EdgeInsets.fromLTRB(13, 8, 13, 8),
    maxWidth: 430,
  );

  /// The card's left offset in the bubble's content box.
  final double outerLeft;

  /// The left offset in an incoming text bubble with a tail.
  final double outerLeftIncomingText;

  /// The card's right offset.
  final double outerRight;

  /// What an outgoing text bubble with a tail adds on the right.
  final double outerRightOutgoingText;

  /// The space above the card under text.
  final double outerTop;

  /// The space above the card when it is the bubble's first element.
  final double outerTopFirst;

  /// The space under the card.
  final double outerBottom;

  /// The text's inset in the block; `top` is the space above the first
  /// line, `bottom` the space under the last when nothing follows.
  final EdgeInsets textInset;

  /// Large media's left and right inset in the block; `top` and `bottom`
  /// are the space around it.
  final EdgeInsets largeMediaInset;

  /// The gap from the site name to the title.
  final double siteToTitle;

  /// The gap from the title to the author.
  final double titleToAuthor;

  /// The gap to the description.
  final double toDescription;

  /// The gap from the text to large media.
  final double textToMedia;

  /// The gap from large media to the button.
  final double mediaToButton;

  /// The block's bottom padding.
  final double bottomPadding;

  /// What the bottom padding adds with media and text.
  final double bottomExtraWithMediaAndText;

  /// The small thumbnail's side; null sizes it from the text (desktop).
  final double? thumbnailSize;

  /// The gap between the text and the thumbnail.
  final double thumbnailGap;

  /// The thumbnail's inset from the block's trailing edge.
  final double thumbnailTrailingInset;

  /// The thumbnail's inset from the block's top.
  final double thumbnailTopInset;

  /// The thumbnail's corner radius.
  final double thumbnailRadius;

  /// What the description beside the thumbnail narrows by beyond the gap.
  final double descriptionNarrowExtra;

  /// The block's least height with a thumbnail.
  final double minHeightWithThumbnail;

  /// Large media's height cap as a share of the display's height; null is
  /// the media box rules.
  final double? largeMediaHeightShare;

  /// The cap for a document page; null is [largeMediaHeightShare].
  final double? largeMediaHeightShareDocument;

  /// Large media's least height.
  final double largeMediaMinHeight;

  /// The height of large media without a size.
  final double largeMediaZeroSide;

  /// The corner radius of large media in the card.
  final double mediaRadius;

  /// The button's height (with its divider).
  final double buttonHeight;

  /// The gap above the button.
  final double buttonGap;

  /// The divider over the button; 0 is none.
  final double buttonDividerWidth;

  /// The divider's share of the accent (Android: of the text colour).
  final double buttonDividerOpacity;

  /// The button label's padding.
  final EdgeInsets buttonPadding;

  /// The card's max width with its offsets; null is the bubble's.
  final double? maxWidth;

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewCardMetrics &&
      other.outerLeft == outerLeft &&
      other.outerLeftIncomingText == outerLeftIncomingText &&
      other.outerRight == outerRight &&
      other.outerRightOutgoingText == outerRightOutgoingText &&
      other.outerTop == outerTop &&
      other.outerTopFirst == outerTopFirst &&
      other.outerBottom == outerBottom &&
      other.textInset == textInset &&
      other.largeMediaInset == largeMediaInset &&
      other.siteToTitle == siteToTitle &&
      other.titleToAuthor == titleToAuthor &&
      other.toDescription == toDescription &&
      other.textToMedia == textToMedia &&
      other.mediaToButton == mediaToButton &&
      other.bottomPadding == bottomPadding &&
      other.bottomExtraWithMediaAndText == bottomExtraWithMediaAndText &&
      other.thumbnailSize == thumbnailSize &&
      other.thumbnailGap == thumbnailGap &&
      other.thumbnailTrailingInset == thumbnailTrailingInset &&
      other.thumbnailTopInset == thumbnailTopInset &&
      other.thumbnailRadius == thumbnailRadius &&
      other.descriptionNarrowExtra == descriptionNarrowExtra &&
      other.minHeightWithThumbnail == minHeightWithThumbnail &&
      other.largeMediaHeightShare == largeMediaHeightShare &&
      other.largeMediaHeightShareDocument == largeMediaHeightShareDocument &&
      other.largeMediaMinHeight == largeMediaMinHeight &&
      other.largeMediaZeroSide == largeMediaZeroSide &&
      other.mediaRadius == mediaRadius &&
      other.buttonHeight == buttonHeight &&
      other.buttonGap == buttonGap &&
      other.buttonDividerWidth == buttonDividerWidth &&
      other.buttonDividerOpacity == buttonDividerOpacity &&
      other.buttonPadding == buttonPadding &&
      other.maxWidth == maxWidth;

  @override
  int get hashCode => Object.hashAll([
    outerLeft,
    outerLeftIncomingText,
    outerRight,
    outerRightOutgoingText,
    outerTop,
    outerTopFirst,
    outerBottom,
    textInset,
    largeMediaInset,
    siteToTitle,
    titleToAuthor,
    toDescription,
    textToMedia,
    mediaToButton,
    bottomPadding,
    bottomExtraWithMediaAndText,
    thumbnailSize,
    thumbnailGap,
    thumbnailTrailingInset,
    thumbnailTopInset,
    thumbnailRadius,
    descriptionNarrowExtra,
    minHeightWithThumbnail,
    largeMediaHeightShare,
    largeMediaHeightShareDocument,
    largeMediaMinHeight,
    largeMediaZeroSide,
    mediaRadius,
    buttonHeight,
    buttonGap,
    buttonDividerWidth,
    buttonDividerOpacity,
    buttonPadding,
    maxWidth,
  ]);
}

/// Which pages show their media small, by the platform's `auto` default,
/// and the overrides every platform applies.
///
/// | | `auto` |
/// | --- | --- |
/// | Android | small when the type is in [smallMediaTypes] and the page has no `media`; compact mode makes a photo small |
/// | iOS | large unless `hasLargeMedia` is false or the type is in [smallMediaTypes] |
/// | Desktop | small when there is a photo, no `media`, the type is not in [largeMediaTypes] and the card has text; [alwaysSmallTypes] always |
///
/// `small` / `large` options win, except that media is never small
/// without a title or a description, nor (Android) for a video, GIF or file.
@immutable
final class LinkPreviewMediaSizeRule {
  /// The rule of [family] with the host's [smallMediaTypes].
  const LinkPreviewMediaSizeRule({
    required this.family,
    this.smallMediaTypes = defaultSmallMediaTypes,
    this.largeMediaTypes = const {'photo', 'document', 'story', 'video'},
    this.alwaysSmallTypes = const {'profile'},
  });

  /// The default small page types: app, profile, article, bot, user,
  /// channel and group pages, call and stream pages.
  static const defaultSmallMediaTypes = {
    'app',
    'profile',
    'article',
    'bot',
    'user',
    'channel',
    'group',
    'call',
    'stream',
  };

  /// Whose `auto` default applies.
  final LinkPreviewRuleFamily family;

  /// The page types shown small by default (Android, iOS).
  final Set<String> smallMediaTypes;

  /// The page types never small by default (desktop).
  final Set<String> largeMediaTypes;

  /// The page types always small by default (desktop).
  final Set<String> alwaysSmallTypes;

  /// The page's media as the card shows it: [page]'s `media` when it is a
  /// box (video, GIF), else its photo; null when it has neither.
  static ({ContentDescriptor descriptor, LinkPreviewMediaSlot slot})? mediaOf(
    LinkPreview page,
  ) {
    if (page.media case final media?
        when MediaItemKind.fromDescriptor(media).isPicture) {
      return (descriptor: media, slot: LinkPreviewMediaSlot.media);
    }
    if (page.photo case final photo?) {
      return (descriptor: photo, slot: LinkPreviewMediaSlot.photo);
    }
    return null;
  }

  static bool _hasText(LinkPreview page) =>
      (page.title?.isNotEmpty ?? false) || page.description.plain.isNotEmpty;

  /// Whether the small / large switch is offered for [page]: it has a
  /// photo or a video that can shrink and, on iOS and desktop, its media is
  /// large by default (`hasLargeMedia`; a page that does not say is not).
  bool offersSwitch(LinkPreview page) =>
      _hasText(page) &&
      switch (family) {
        LinkPreviewRuleFamily.android => page.photo != null,
        LinkPreviewRuleFamily.ios || LinkPreviewRuleFamily.desktop =>
          page.hasLargeMedia == true &&
              (page.photo != null ||
                  (page.media != null && mediaOf(page) != null)),
      };

  /// The size [page]'s media shows at under [options]; null when the page
  /// has no media to show. [compact] is the host's compact layout.
  LinkPreviewMediaSize? resolve(
    LinkPreview page, {
    LinkPreviewOptions? options,
    bool compact = false,
  }) {
    final shown = mediaOf(page);
    if (shown == null) return null;
    final wanted = switch (options?.media ?? LinkPreviewMedia.auto) {
      LinkPreviewMedia.small => LinkPreviewMediaSize.small,
      LinkPreviewMedia.large => LinkPreviewMediaSize.large,
      LinkPreviewMedia.auto => _auto(page, compact: compact),
    };
    if (wanted == LinkPreviewMediaSize.large) return wanted;
    if (!_hasText(page)) return LinkPreviewMediaSize.large;
    if (family == LinkPreviewRuleFamily.android &&
        shown.slot == LinkPreviewMediaSlot.media) {
      return LinkPreviewMediaSize.large;
    }
    return LinkPreviewMediaSize.small;
  }

  LinkPreviewMediaSize _auto(LinkPreview page, {required bool compact}) {
    final type = page.type;
    final small = switch (family) {
      LinkPreviewRuleFamily.android =>
        page.media == null &&
            ((type != null && smallMediaTypes.contains(type)) || compact),
      LinkPreviewRuleFamily.ios =>
        page.hasLargeMedia == false ||
            (type != null && smallMediaTypes.contains(type)),
      LinkPreviewRuleFamily.desktop =>
        (type != null && alwaysSmallTypes.contains(type)) ||
            (page.photo != null &&
                page.media == null &&
                !(type != null && largeMediaTypes.contains(type)) &&
                _hasText(page)),
    };
    return small ? LinkPreviewMediaSize.small : LinkPreviewMediaSize.large;
  }

  /// A copy with the given sets replaced.
  LinkPreviewMediaSizeRule copyWith({
    Set<String>? smallMediaTypes,
    Set<String>? largeMediaTypes,
    Set<String>? alwaysSmallTypes,
  }) => LinkPreviewMediaSizeRule(
    family: family,
    smallMediaTypes: smallMediaTypes ?? this.smallMediaTypes,
    largeMediaTypes: largeMediaTypes ?? this.largeMediaTypes,
    alwaysSmallTypes: alwaysSmallTypes ?? this.alwaysSmallTypes,
  );

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewMediaSizeRule &&
      other.family == family &&
      _setEquals(other.smallMediaTypes, smallMediaTypes) &&
      _setEquals(other.largeMediaTypes, largeMediaTypes) &&
      _setEquals(other.alwaysSmallTypes, alwaysSmallTypes);

  @override
  int get hashCode => Object.hash(
    family,
    Object.hashAllUnordered(smallMediaTypes),
    Object.hashAllUnordered(largeMediaTypes),
    Object.hashAllUnordered(alwaysSmallTypes),
  );
}

/// Whose `auto` media size default a [LinkPreviewMediaSizeRule] applies.
enum LinkPreviewRuleFamily {
  /// Small for the small types without media.
  android,

  /// Large unless the backend says otherwise or the type is small.
  ios,

  /// Small for a photo-only page with text of a non-media type.
  desktop,
}

/// The press feedback of a card and its button (over `ChromeInk`), never
/// on a link or on the button for the card.
///
/// | | Card | Button |
/// | --- | --- | --- |
/// | Android | ripple at accent 0.10 in radii 3/6/6/3, bounce to 0.99 | bounce to 0.98 |
/// | iOS | scale to `(w − 5) / w` | scale to `(w − 10) / w` |
/// | Desktop | ripple in a radius-5 rect, the block's fill colour | the same ripple |
@immutable
final class LinkPreviewCardPress {
  /// Feedback of [kind] at [rippleOpacity] of the accent inside
  /// [rippleRadius], scaling the card by [cardScale] and the button by
  /// [buttonScale].
  const LinkPreviewCardPress({
    required this.kind,
    required this.rippleOpacity,
    required this.rippleRadius,
    this.cardScale,
    this.buttonScale,
  });

  /// Android.
  static const android = LinkPreviewCardPress(
    kind: ChromeInkKind.ripple,
    rippleOpacity: 0.10,
    rippleRadius: BorderRadius.only(
      topLeft: Radius.circular(3),
      topRight: Radius.circular(6),
      bottomRight: Radius.circular(6),
      bottomLeft: Radius.circular(3),
    ),
    cardScale: ChromeInkBounce.card,
    buttonScale: ChromeInkBounce.button,
  );

  /// iOS: the scale only.
  static const ios = LinkPreviewCardPress(
    kind: ChromeInkKind.highlight,
    rippleOpacity: 0,
    rippleRadius: BorderRadius.all(Radius.circular(4)),
    cardScale: ChromeInkInset.card,
    buttonScale: ChromeInkInset.button,
  );

  /// Desktop: the ripple only.
  static const desktop = LinkPreviewCardPress(
    kind: ChromeInkKind.pointer,
    rippleOpacity: 0.12,
    rippleRadius: BorderRadius.all(Radius.circular(5)),
  );

  /// The feedback's kind.
  final ChromeInkKind kind;

  /// The ripple's share of the accent; 0 draws none.
  final double rippleOpacity;

  /// The ripple's mask.
  final BorderRadius rippleRadius;

  /// The card's press scale, or null.
  final ChromeInkScale? cardScale;

  /// The button's press scale, or null.
  final ChromeInkScale? buttonScale;

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewCardPress &&
      other.kind == kind &&
      other.rippleOpacity == rippleOpacity &&
      other.rippleRadius == rippleRadius &&
      other.cardScale == cardScale &&
      other.buttonScale == buttonScale;

  @override
  int get hashCode =>
      Object.hash(kind, rippleOpacity, rippleRadius, cardScale, buttonScale);
}

/// The desktop enlarge button over a card's large photo: the only part that
/// opens the viewer when the card has text.
@immutable
final class LinkPreviewEnlargeButton {
  /// A button [size] square with [radius] corners, [inset] from the media's
  /// top-right corner.
  const LinkPreviewEnlargeButton({
    this.size = 36,
    this.radius = 8,
    this.inset = 4,
  });

  /// The side.
  final double size;

  /// The corner radius.
  final double radius;

  /// The inset from the media's top and right edges.
  final double inset;

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewEnlargeButton &&
      other.size == size &&
      other.radius == radius &&
      other.inset == inset;

  @override
  int get hashCode => Object.hash(size, radius, inset);
}

// --- The policy ---

/// How a message's link preview card is laid out and drawn, per platform.
///
/// | Part | Role |
/// | --- | --- |
/// | [style] | The block: bar, fill, radius (the quote block's values) |
/// | [metrics] | Offsets, insets, gaps, thumbnail, large media, button |
/// | [text] | Sizes, weights, line limits |
/// | [width] | The `cardWidth` rule |
/// | [mediaSize] | Small or large media (`auto` per platform) |
/// | [appear] / [appearDuration] | How the card shows when its page arrives |
/// | [press] | The press feedback over `ChromeInk` |
/// | [photoTapOpensPage] / [enlarge] | What a tap on the photo of a card with text does |
/// | [time] / [timeLineHeight] / [timeSpacing] | The time when the card ends the bubble |
/// | [mirrorsInRtl] | Whether the thumbnail moves to the trailing side in a right-to-left chat |
///
/// [layout] turns a page into the `linkPreview` block: nothing for a
/// removed or empty page, else the card's geometry and its media as an
/// ordinary cell, keyed by `MediaItemId.linkPreviewOf`.
@immutable
final class LinkPreviewCardPolicy {
  /// A policy of the given parts.
  const LinkPreviewCardPolicy({
    required this.style,
    required this.metrics,
    required this.text,
    required this.width,
    required this.mediaSize,
    required this.appear,
    required this.press,
    required this.time,
    this.appearDuration = Duration.zero,
    this.photoTapOpensPage = false,
    this.enlarge,
    this.timeLineHeight = 14,
    this.timeSpacing = 0,
    this.defaultTimeHeight = 14,
    this.mirrorsInRtl = false,
  });

  /// Android: fill the budget, jump on appear, ripple and bounce, the
  /// photo opens the viewer, the time on its own line (+ 14).
  const LinkPreviewCardPolicy.android()
    : this(
        style: LinkPreviewBlockStyle.android,
        metrics: LinkPreviewCardMetrics.android,
        text: LinkPreviewCardText.android,
        width: LinkPreviewCardWidth.fillBudget,
        mediaSize: const LinkPreviewMediaSizeRule(
          family: LinkPreviewRuleFamily.android,
        ),
        appear: LinkPreviewAppearForm.jump,
        press: LinkPreviewCardPress.android,
        time: LinkPreviewTimePlacement.ownLine,
      );

  /// iOS: fit the media, fade in over 250 ms, the inset scale, the photo
  /// opens the page, the time inside the card (spacing 9).
  const LinkPreviewCardPolicy.ios()
    : this(
        style: LinkPreviewBlockStyle.ios,
        metrics: LinkPreviewCardMetrics.ios,
        text: LinkPreviewCardText.ios,
        width: LinkPreviewCardWidth.fitMedia,
        mediaSize: const LinkPreviewMediaSizeRule(
          family: LinkPreviewRuleFamily.ios,
        ),
        appear: LinkPreviewAppearForm.fade,
        appearDuration: const Duration(milliseconds: 250),
        press: LinkPreviewCardPress.ios,
        photoTapOpensPage: true,
        time: LinkPreviewTimePlacement.insideCard,
        timeSpacing: 9,
      );

  /// Desktop: fit the content, relayout on appear, the ripple, the photo
  /// opens the page and the enlarge button the viewer, the time inside the
  /// card, the thumbnail mirrored in right-to-left chats.
  const LinkPreviewCardPolicy.desktop()
    : this(
        style: LinkPreviewBlockStyle.desktop,
        metrics: LinkPreviewCardMetrics.desktop,
        text: LinkPreviewCardText.desktop,
        width: LinkPreviewCardWidth.fitContent,
        mediaSize: const LinkPreviewMediaSizeRule(
          family: LinkPreviewRuleFamily.desktop,
        ),
        appear: LinkPreviewAppearForm.relayout,
        press: LinkPreviewCardPress.desktop,
        photoTapOpensPage: true,
        enlarge: const LinkPreviewEnlargeButton(),
        time: LinkPreviewTimePlacement.insideCard,
        timeSpacing: 1,
        defaultTimeHeight: 17,
        mirrorsInRtl: true,
      );

  /// The block style.
  final LinkPreviewBlockStyle style;

  /// The geometry.
  final LinkPreviewCardMetrics metrics;

  /// The type.
  final LinkPreviewCardText text;

  /// The width rule.
  final LinkPreviewCardWidth width;

  /// Small or large media.
  final LinkPreviewMediaSizeRule mediaSize;

  /// How the card shows when its page arrives.
  final LinkPreviewAppearForm appear;

  /// The fade's length under [LinkPreviewAppearForm.fade].
  final Duration appearDuration;

  /// The press feedback.
  final LinkPreviewCardPress press;

  /// Whether a tap on the photo of a card with text opens the page rather
  /// than the viewer.
  final bool photoTapOpensPage;

  /// The enlarge button over a large photo of a card with text, which
  /// opens the viewer; null is none.
  final LinkPreviewEnlargeButton? enlarge;

  /// Where the time goes when the card ends the bubble.
  final LinkPreviewTimePlacement time;

  /// The time's own line under the card ([LinkPreviewTimePlacement.ownLine]).
  final double timeLineHeight;

  /// The space the time adds to the card's bottom inset beyond its height
  /// ([LinkPreviewTimePlacement.insideCard]).
  final double timeSpacing;

  /// The time's height when the host measured none.
  final double defaultTimeHeight;

  /// Whether the thumbnail moves to the trailing side (left) in a
  /// right-to-left chat; the bar is on the leading edge either way.
  final bool mirrorsInRtl;

  /// The card of [input]'s link preview at [top], with [box] the layout's
  /// box sizing (iOS large media follows the box rules); null when there is
  /// no card to draw (no preview, a removed or an empty page).
  MediaBlock$LinkPreview? layout(
    MediaLayoutInput input, {
    required double top,
    required MediaBoxSizing box,
  }) {
    final preview = input.linkPreview;
    if (preview == null) return null;
    final page = preview.page;
    if ((preview.options?.removed ?? false) || isEmpty(page)) return null;
    MediaTrace.begin(MediaTrace.cardLayout);
    final block = _layout(input, preview, top: top, box: box);
    MediaTrace.end(MediaTrace.cardLayout);
    return block;
  }

  /// The span of a card's description: its text with bold, italic and
  /// strike styles, links in [linkColor].
  ///
  /// The layout measures and the card paints the same span, so the lines
  /// the layout counts are the lines drawn.
  static TextSpan descriptionSpan(
    RichText description,
    TextStyle style, {
    Color? linkColor,
  }) {
    final text = description.plain;
    if (description.entities.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    // Cut points at every entity edge, then each run's style from the
    // entities covering it.
    final cuts = <int>{0, text.length};
    for (final entity in description.entities) {
      cuts
        ..add(entity.offset.clamp(0, text.length))
        ..add(entity.end.clamp(0, text.length));
    }
    final points = cuts.toList()..sort();
    final children = <TextSpan>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final start = points[i];
      final end = points[i + 1];
      if (start == end) continue;
      var run = style;
      for (final entity in description.entities) {
        if (entity.offset > start || entity.end < end) continue;
        run = switch (entity.kind) {
          EntityKind$Style(style: EntityStyle.bold) => run.copyWith(
            fontWeight: FontWeight.w600,
          ),
          EntityKind$Style(style: EntityStyle.italic) => run.copyWith(
            fontStyle: FontStyle.italic,
          ),
          EntityKind$Style(style: EntityStyle.strike) => run.copyWith(
            decoration: TextDecoration.lineThrough,
          ),
          EntityKind$Link() when linkColor != null => run.copyWith(
            color: linkColor,
          ),
          _ => run,
        };
      }
      children.add(TextSpan(text: text.substring(start, end), style: run));
    }
    return TextSpan(style: style, children: children);
  }

  /// Whether [page] has nothing to show: no card is drawn for it.
  static bool isEmpty(LinkPreview page) =>
      (page.siteName?.isEmpty ?? true) &&
      (page.title?.isEmpty ?? true) &&
      (page.author?.isEmpty ?? true) &&
      page.description.plain.isEmpty &&
      page.photo == null &&
      page.media == null;

  MediaBlock$LinkPreview _layout(
    MediaLayoutInput input,
    MediaLinkPreviewInput preview, {
    required double top,
    required MediaBoxSizing box,
  }) {
    final page = preview.page;
    final m = metrics;
    final shown = LinkPreviewMediaSizeRule.mediaOf(page);
    final item = switch (shown) {
      (:final descriptor, :final slot) => MediaItem(
        id: MediaItemId.linkPreviewOf(preview.messageId, slot: slot),
        descriptor: descriptor,
        kind: slot == LinkPreviewMediaSlot.photo ? MediaItemKind.photo : null,
      ),
      null => null,
    };
    final size = mediaSize.resolve(
      page,
      options: preview.options,
      compact: preview.compact,
    );
    final small = item != null && size == LinkPreviewMediaSize.small;
    final large = item != null && size == LinkPreviewMediaSize.large;
    final tailed = input.hasText && !input.joinedBelow;
    final outerLeft = !input.isOutgoing && tailed
        ? m.outerLeftIncomingText
        : m.outerLeft;
    final outerRight =
        m.outerRight +
        (input.isOutgoing && tailed ? m.outerRightOutgoingText : 0);
    final first =
        input.captionPosition != MediaCaptionPosition.above &&
        !input.headerAbove;
    final outerTop = first ? m.outerTopFirst : m.outerTop;
    final cardMax = math.max<double>(
      0,
      _maxCardWidth(input) - outerLeft - outerRight,
    );

    // The pieces of text, in order.
    final type = input.text;
    final base = type.style;
    final pieces = <(LinkPreviewCardPart, InlineSpan, int)>[
      if (page.siteName case final site? when site.isNotEmpty)
        (
          LinkPreviewCardPart.siteName,
          TextSpan(
            text: site,
            style: text.over(base, weight: text.siteWeight),
          ),
          text.siteLines,
        ),
      if (page.title case final title? when title.isNotEmpty)
        (
          LinkPreviewCardPart.title,
          TextSpan(
            text: title,
            style: text.over(base, weight: text.titleWeight),
          ),
          text.titleLines,
        ),
      if (page.author case final author? when author.isNotEmpty)
        (
          LinkPreviewCardPart.author,
          TextSpan(text: author, style: text.over(base)),
          text.authorLines,
        ),
      if (page.description.plain.isNotEmpty)
        (
          LinkPreviewCardPart.description,
          descriptionSpan(page.description, text.over(base)),
          preview.compact
              ? text.descriptionLinesCompact ?? text.descriptionLines
              : text.descriptionLines,
        ),
    ];
    final hasText = pieces.isNotEmpty;
    final lineHeight = type
        .measureOf(TextSpan(text: 'M', style: text.over(base)), ellipsis: true)
        .height;
    final thumb = small
        ? m.thumbnailSize ??
              (lineHeight * (text.lineBudget ?? 3)).clamp(
                lineHeight * 2,
                lineHeight * (text.lineBudget ?? 3),
              )
        : 0.0;
    final button = switch (preview.buttonLabel) {
      final label? when label.isNotEmpty => type.measureOf(
        TextSpan(text: label, style: text.buttonOver(base)),
        ellipsis: true,
      ),
      _ => null,
    };

    // Large media's natural width, which the fitting rules read.
    final mediaNatural = switch (item) {
      final item? when large => switch (width) {
        LinkPreviewCardWidth.fitMedia =>
          box.linkPreviewMedia(item, input).size.width,
        _ => item.descriptor.size?.width ?? cardMax,
      },
      _ => 0.0,
    };
    final textMax = cardMax - m.textInset.horizontal;
    final beside = thumb > 0 ? thumb + m.thumbnailGap : 0.0;
    final widest = _layoutText(
      input.text,
      pieces,
      textMax,
      beside,
      thumb,
    ).widest;
    final contentWidth = hasText
        ? widest + beside + m.textInset.horizontal
        : 0.0;
    final buttonWidth = switch (button) {
      final b? => b.width + m.buttonPadding.horizontal + m.textInset.horizontal,
      null => 0.0,
    };
    final cardWidth = switch (width) {
      LinkPreviewCardWidth.fillBudget =>
        large
            ? cardMax
            : math.min(cardMax, math.max(contentWidth, buttonWidth)),
      LinkPreviewCardWidth.fitMedia => math.min(
        cardMax,
        math.max(
          large ? mediaNatural + m.largeMediaInset.horizontal : 0.0,
          math.max(contentWidth, buttonWidth),
        ),
      ),
      LinkPreviewCardWidth.fitContent => math.min(
        cardMax,
        [
          contentWidth,
          buttonWidth,
          if (large) mediaNatural + m.largeMediaInset.horizontal,
        ].fold<double>(0, math.max),
      ),
    };

    // The text at the card's width.
    final rtl = preview.textDirection == TextDirection.rtl && mirrorsInRtl;
    final cardLeft = outerLeft;
    final cardTop = top + outerTop;
    final textLeft = cardLeft + m.textInset.left;
    final textWidth = cardWidth - m.textInset.horizontal;
    final laid = _layoutText(input.text, pieces, textWidth, beside, thumb);
    final texts = <LinkPreviewCardPiece>[];
    var y = cardTop + m.textInset.top;
    for (final (index, piece) in laid.pieces.indexed) {
      y += index == 0 ? 0 : _gapBefore(piece.part);
      final shift = rtl && piece.narrowed ? beside : 0.0;
      texts.add(
        LinkPreviewCardPiece(
          part: piece.part,
          rect: Rect.fromLTWH(
            textLeft + shift,
            y,
            piece.maxWidth,
            piece.height,
          ),
          maxLines: piece.maxLines,
        ),
      );
      y += piece.height;
    }
    var bottom = hasText ? y : cardTop + m.textInset.top;

    // The media: a thumbnail at the top trailing corner or a box under the
    // text.
    MediaCell? cell;
    Rect? enlargeRect;
    if (item != null && small) {
      final thumbTop = cardTop + m.thumbnailTopInset;
      final thumbLeft = rtl
          ? cardLeft + m.thumbnailTrailingInset + style.barWidth
          : cardLeft + cardWidth - m.thumbnailTrailingInset - thumb;
      cell = _cell(
        item,
        Rect.fromLTWH(thumbLeft, thumbTop, thumb, thumb),
        MediaCornerRadii.all(m.thumbnailRadius),
      );
      bottom = math.max(bottom, thumbTop + thumb);
    } else if (item != null && large) {
      final mediaWidth = math.max<double>(
        0,
        cardWidth - m.largeMediaInset.horizontal,
      );
      final mediaHeight = _largeHeight(item, page, mediaWidth, input, box);
      final mediaTop = (hasText
          ? bottom + m.textToMedia
          : cardTop + m.largeMediaInset.top);
      final rect = Rect.fromLTWH(
        cardLeft + m.largeMediaInset.left,
        mediaTop,
        mediaWidth,
        mediaHeight,
      );
      final nearRadius = math.min<double>(3, input.chrome.bubbleRadius - 2);
      final radii =
          !input.isOutgoing &&
              tailed &&
              width == LinkPreviewCardWidth.fillBudget
          ? MediaCornerRadii(
              topLeft: m.mediaRadius,
              topRight: m.mediaRadius,
              bottomLeft: math.max<double>(0, nearRadius),
              bottomRight: m.mediaRadius,
            )
          : MediaCornerRadii.all(m.mediaRadius);
      cell = _cell(item, rect, radii);
      if (enlarge case final e?
          when hasText && item.kind == MediaItemKind.photo) {
        enlargeRect = Rect.fromLTWH(
          rect.right - e.inset - e.size,
          rect.top + e.inset,
          e.size,
          e.size,
        );
      }
      bottom = rect.bottom + (button == null ? m.largeMediaInset.bottom : 0);
    }

    // The button.
    Rect? buttonRect;
    if (button != null) {
      final gap = large ? m.mediaToButton : m.buttonGap;
      buttonRect = Rect.fromLTWH(
        textLeft,
        bottom + gap,
        textWidth,
        m.buttonHeight,
      );
      bottom = buttonRect.bottom;
    } else {
      bottom +=
          m.bottomPadding +
          (item != null && large && hasText
              ? m.bottomExtraWithMediaAndText
              : 0);
    }
    if (small) {
      bottom = math.max(bottom, cardTop + m.minHeightWithThumbnail);
    }

    // The time, when the card ends the bubble.
    Rect? timeSlot;
    var after = m.outerBottom;
    final timeHeight = input.chrome.timeHeight > 0
        ? input.chrome.timeHeight
        : defaultTimeHeight;
    if (input.cardIsLast) {
      switch (time) {
        case LinkPreviewTimePlacement.insideCard:
          bottom += timeSpacing + timeHeight;
          timeSlot = Rect.fromLTRB(
            cardLeft + m.textInset.left,
            bottom - timeHeight,
            cardLeft + cardWidth - m.textInset.right,
            bottom,
          );
        case LinkPreviewTimePlacement.ownLine:
          timeSlot = Rect.fromLTWH(
            cardLeft,
            bottom + after,
            cardWidth,
            timeLineHeight,
          );
          after += timeLineHeight;
      }
    }
    final card = Rect.fromLTRB(cardLeft, cardTop, cardLeft + cardWidth, bottom);
    return MediaBlock$LinkPreview(
      rect: Rect.fromLTRB(0, top, card.right + outerRight, bottom + after),
      page: page,
      options: preview.options,
      item: item,
      media: cell,
      card: LinkPreviewCard(
        rect: card,
        mediaSize: item == null ? null : size,
        texts: texts,
        button: switch (buttonRect) {
          final rect? => LinkPreviewCardButton(
            rect: rect,
            label: preview.buttonLabel ?? '',
          ),
          null => null,
        },
        enlarge: enlargeRect,
        timeSlot: timeSlot,
        rtl: preview.textDirection == TextDirection.rtl,
        width: width,
        appear: appear,
      ),
    );
  }

  double _maxCardWidth(MediaLayoutInput input) {
    final bubble = math.min(input.contentWidth, input.availableWidth);
    return switch (width) {
      LinkPreviewCardWidth.fillBudget =>
        input.availableWidth -
            80 -
            (input.showsAvatar ? 52 : 0) -
            (input.hasSideButton ? 20 : 0) +
            metrics.outerLeft +
            metrics.outerRight,
      LinkPreviewCardWidth.fitMedia => bubble,
      LinkPreviewCardWidth.fitContent => math.min(
        bubble,
        metrics.maxWidth ?? bubble,
      ),
    };
  }

  double _gapBefore(LinkPreviewCardPart part) => switch (part) {
    LinkPreviewCardPart.title => metrics.siteToTitle,
    LinkPreviewCardPart.author => metrics.titleToAuthor,
    LinkPreviewCardPart.description => metrics.toDescription,
    LinkPreviewCardPart.siteName => 0,
  };

  /// Lays the pieces out at [maxWidth], narrowing those that start beside a
  /// thumbnail [thumb] high by [beside] (the description by its extra too),
  /// within the shared line budget.
  ({
    double widest,
    List<
      ({
        LinkPreviewCardPart part,
        double maxWidth,
        double height,
        int maxLines,
        bool narrowed,
      })
    >
    pieces,
  })
  _layoutText(
    MediaLayoutText type,
    List<(LinkPreviewCardPart, InlineSpan, int)> pieces,
    double maxWidth,
    double beside,
    double thumb,
  ) {
    final laid =
        <
          ({
            LinkPreviewCardPart part,
            double maxWidth,
            double height,
            int maxLines,
            bool narrowed,
          })
        >[];
    var widest = 0.0;
    var y = 0.0;
    var budget = text.lineBudget;
    final thumbBottom = thumb > 0 ? metrics.thumbnailTopInset + thumb : 0.0;
    for (final (index, (part, span, lines)) in pieces.indexed) {
      y += index == 0 ? 0 : _gapBefore(part);
      final narrowed = beside > 0 && y < thumbBottom;
      final extra = narrowed && part == LinkPreviewCardPart.description
          ? metrics.descriptionNarrowExtra
          : 0.0;
      final width = math.max<double>(
        0,
        maxWidth - (narrowed ? beside + extra : 0),
      );
      var maxLines = lines;
      if (budget != null) maxLines = math.max(1, math.min(maxLines, budget));
      final measured = type.measureOf(
        span,
        maxWidth: width,
        maxLines: maxLines,
        ellipsis: true,
      );
      if (budget != null) budget = math.max(1, budget - measured.lines);
      widest = math.max(widest, measured.width);
      laid.add((
        part: part,
        maxWidth: width,
        height: measured.height,
        maxLines: maxLines,
        narrowed: narrowed,
      ));
      y += measured.height;
    }
    return (widest: widest, pieces: laid);
  }

  double _largeHeight(
    MediaItem item,
    LinkPreview page,
    double width,
    MediaLayoutInput input,
    MediaBoxSizing box,
  ) {
    final size = item.descriptor.size;
    if (width == 0) return 0;
    final m = metrics;
    switch (this.width) {
      case LinkPreviewCardWidth.fitMedia:
        final natural = box.linkPreviewMedia(item, input).size;
        if (natural.isEmpty) return m.largeMediaZeroSide;
        return natural.height * math.min(1, width / natural.width);
      case LinkPreviewCardWidth.fillBudget || LinkPreviewCardWidth.fitContent:
        if (size == null || size.width <= 0 || size.height <= 0) {
          return m.largeMediaZeroSide;
        }
        var height = width * size.height / size.width;
        final share = page.type == 'document'
            ? m.largeMediaHeightShareDocument ?? m.largeMediaHeightShare
            : m.largeMediaHeightShare;
        if (share != null) {
          height = math.min(height, input.displayHeight * share);
        } else {
          height = math.min(height, width);
        }
        return math.max(height, m.largeMediaMinHeight);
    }
  }

  static MediaCell _cell(MediaItem item, Rect rect, MediaCornerRadii radii) =>
      MediaCell(
        itemId: item.id,
        kind: item.kind,
        rect: rect,
        fit: const MediaFit.crop(),
        neighbours: const MediaNeighbours(
          top: MediaNeighbour.item,
          bottom: MediaNeighbour.item,
          left: MediaNeighbour.item,
          right: MediaNeighbour.item,
        ),
        radii: radii,
      );

  /// A copy with the given parts replaced.
  LinkPreviewCardPolicy copyWith({
    LinkPreviewBlockStyle? style,
    LinkPreviewCardMetrics? metrics,
    LinkPreviewCardText? text,
    LinkPreviewCardWidth? width,
    LinkPreviewMediaSizeRule? mediaSize,
    LinkPreviewAppearForm? appear,
    Duration? appearDuration,
    LinkPreviewCardPress? press,
    bool? photoTapOpensPage,
    LinkPreviewEnlargeButton? enlarge,
    bool removeEnlarge = false,
    LinkPreviewTimePlacement? time,
    double? timeLineHeight,
    double? timeSpacing,
    double? defaultTimeHeight,
    bool? mirrorsInRtl,
  }) => LinkPreviewCardPolicy(
    style: style ?? this.style,
    metrics: metrics ?? this.metrics,
    text: text ?? this.text,
    width: width ?? this.width,
    mediaSize: mediaSize ?? this.mediaSize,
    appear: appear ?? this.appear,
    appearDuration: appearDuration ?? this.appearDuration,
    press: press ?? this.press,
    photoTapOpensPage: photoTapOpensPage ?? this.photoTapOpensPage,
    enlarge: removeEnlarge ? null : enlarge ?? this.enlarge,
    time: time ?? this.time,
    timeLineHeight: timeLineHeight ?? this.timeLineHeight,
    timeSpacing: timeSpacing ?? this.timeSpacing,
    defaultTimeHeight: defaultTimeHeight ?? this.defaultTimeHeight,
    mirrorsInRtl: mirrorsInRtl ?? this.mirrorsInRtl,
  );

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewCardPolicy &&
      other.style == style &&
      other.metrics == metrics &&
      other.text == text &&
      other.width == width &&
      other.mediaSize == mediaSize &&
      other.appear == appear &&
      other.appearDuration == appearDuration &&
      other.press == press &&
      other.photoTapOpensPage == photoTapOpensPage &&
      other.enlarge == enlarge &&
      other.time == time &&
      other.timeLineHeight == timeLineHeight &&
      other.timeSpacing == timeSpacing &&
      other.defaultTimeHeight == defaultTimeHeight &&
      other.mirrorsInRtl == mirrorsInRtl;

  @override
  int get hashCode => Object.hash(
    style,
    metrics,
    text,
    width,
    mediaSize,
    appear,
    appearDuration,
    press,
    photoTapOpensPage,
    enlarge,
    time,
    timeLineHeight,
    timeSpacing,
    defaultTimeHeight,
    mirrorsInRtl,
  );
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

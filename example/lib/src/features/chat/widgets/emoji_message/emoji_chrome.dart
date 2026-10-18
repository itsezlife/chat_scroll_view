/// The chrome around an emoji-only message, per platform family: where the
/// time pill, the header and the reactions go, as pure geometry.
///
/// The viewport's `ChatEmojiBody` lays the emoji out and says where its parts
/// are (`ChatEmojiGeometry`); everything around it is the host's, and the three
/// platform families differ almost completely in it, so each is a strategy of
/// its own, picked from the same [ChatEmojiPolicy] the body was given. Nothing
/// here paints or measures text: the widgets measure and ask.
///
/// ## Frame
///
/// Every rectangle is in the *row frame*: x from the row's left edge to its
/// right edge (a row [EmojiChromeInput.rowWidth] wide), y from the top of the
/// body. A platform that does not mirror (Android, iOS) keeps an outgoing
/// message at the right and an incoming one at the left in a right-to-left chat;
/// Desktop does, and [EmojiChromeLayout.mirrored] flips the frame for it.
///
/// ## Numbers
///
/// Each constant cites the reference source it was traced from (`A` Android's
/// `ChatMessageCell`, `I` the iOS animated-sticker node, `D` Desktop's
/// unwrapped media), with the section of the research note
/// (`04-emoji-only-chrome.md`). A value the reference does not give in the
/// sources at hand is named `unverified*`, takes the nearest verified
/// platform's value, and is listed in the divergence table of ADR 036.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show
        ChatEmojiGeometry,
        ChatEmojiLayoutKind,
        ChatEmojiPolicy,
        ChatEmojiPolicy$Android,
        ChatEmojiPolicy$Desktop,
        ChatEmojiPolicy$Ios;
import 'package:content_model/content_model.dart'
    show ContentKey$Document, EmojiOnly;
import 'package:flutter/foundation.dart' show immutable;

/// Where a message is in its delivery, for the ticks of the pill.
enum EmojiSendState {
  /// No status: an incoming message, or a scheduled one.
  none,

  /// Being sent: the clock.
  sending,

  /// Sent: one check.
  sent,

  /// Read: two checks.
  read,

  /// Failed: the error square.
  error,
}

/// What stands above or beside an emoji-only message.
enum EmojiHeaderShape {
  /// A reply.
  reply,

  /// A forward.
  forward,

  /// A forward that is also a reply, one panel.
  forwardedReply,
}

/// How message selection shows on an emoji-only message.
enum EmojiSelectionStyle {
  /// The viewport's whole-row tint; the body paints nothing of its own.
  viewportRowTint,

  /// A checkbox only; the body paints nothing.
  none,

  /// The glyphs are recoloured while selected.
  glyphRecolour,
}

/// The measured text of the pill, in logical pixels.
@immutable
final class EmojiMetaMetrics {
  /// Creates the metrics.
  const EmojiMetaMetrics({
    required this.timeWidth,
    required this.timeHeight,
    this.viewsWidth,
  });

  /// The width of the time string (`edited 09:05` is one string).
  final double timeWidth;

  /// The height of its line.
  final double timeHeight;

  /// The width of the views count, or null for a message without views.
  final double? viewsWidth;
}

/// The measured text of a header, in logical pixels.
@immutable
final class EmojiHeaderText {
  /// Creates the metrics.
  const EmojiHeaderText({
    required this.nameWidth,
    required this.nameHeight,
    required this.textWidth,
    required this.textHeight,
    required this.forwardWidth,
    required this.forwardHeight,
  });

  /// The width of the quoted sender's name line.
  final double nameWidth;

  /// The height of that line.
  final double nameHeight;

  /// The width of the quoted text line.
  final double textWidth;

  /// The height of that line.
  final double textHeight;

  /// The width of the widest "Forwarded from" line.
  final double forwardWidth;

  /// The height of the forward lines together.
  final double forwardHeight;
}

/// The inside of a pill: where the time, the views and the ticks go, in the
/// pill's own coordinates.
@immutable
final class EmojiPillLayout {
  /// Creates the layout.
  const EmojiPillLayout({
    required this.size,
    required this.metaWidth,
    required this.timeOrigin,
    required this.state,
    this.viewsIcon,
    this.viewsCountOrigin,
    this.status,
  });

  /// The pill's size.
  final Size size;

  /// The width of the text of the pill: the time, and the views before it.
  final double metaWidth;

  /// The top left of the time's line.
  final Offset timeOrigin;

  /// The views icon, or null without views.
  final Rect? viewsIcon;

  /// The top left of the views count, or null without views.
  final Offset? viewsCountOrigin;

  /// The delivery state the [status] shows.
  final EmojiSendState state;

  /// Where the ticks, the clock or the error square are drawn (the glyphs are
  /// right-aligned in it), or null for none.
  final Rect? status;
}

/// What the placement reads.
@immutable
final class EmojiChromeInput {
  /// Creates the input.
  const EmojiChromeInput({
    required this.body,
    required this.outgoing,
    required this.rowWidth,
    required this.pill,
    this.headerShape,
    this.header,
    this.reactions,
  });

  /// The body's geometry, with the strip the chrome asked for.
  final ChatEmojiGeometry body;

  /// Whether the message is the user's.
  final bool outgoing;

  /// The width of the row.
  final double rowWidth;

  /// The pill's inside.
  final EmojiPillLayout pill;

  /// What the header is, or null for none.
  final EmojiHeaderShape? headerShape;

  /// The header panel's size, or null for none.
  final Size? header;

  /// The reactions row's size, or null for none.
  final Size? reactions;
}

/// Where everything is, in the row frame.
@immutable
final class EmojiChromeLayout {
  /// Creates the layout.
  const EmojiChromeLayout({
    required this.body,
    required this.pill,
    this.header,
    this.reactions,
  });

  /// The body's box.
  final Rect body;

  /// The pill.
  final Rect? pill;

  /// The header panel, or null.
  final Rect? header;

  /// The reactions row, or null.
  final Rect? reactions;

  /// Everything together.
  Rect get bounds {
    var result = body;
    for (final rect in [pill, header, reactions]) {
      if (rect != null) result = result.expandToInclude(rect);
    }
    return result;
  }

  /// The layout of a right-to-left chat: every rectangle flipped across a row
  /// [width] wide.
  EmojiChromeLayout mirrored(double width) {
    Rect? flip(Rect? rect) => rect == null
        ? null
        : Rect.fromLTRB(
            width - rect.right,
            rect.top,
            width - rect.left,
            rect.bottom,
          );
    return EmojiChromeLayout(
      body: flip(body)!,
      pill: flip(pill),
      header: flip(header),
      reactions: flip(reactions),
    );
  }
}

/// A platform family's chrome strategy.
@immutable
sealed class EmojiChrome {
  /// Base constructor for the strategies.
  const EmojiChrome();

  /// The chrome of [policy]'s platform family.
  factory EmojiChrome.of(ChatEmojiPolicy policy) => switch (policy) {
    ChatEmojiPolicy$Android() => const EmojiChrome$Android(),
    ChatEmojiPolicy$Ios() => const EmojiChrome$Ios(),
    ChatEmojiPolicy$Desktop() => const EmojiChrome$Desktop(),
  };

  /// The policy this chrome goes with.
  ChatEmojiPolicy get policy;

  /// The font size of the pill's text.
  double get metaFontSize;

  /// The font size of the header's text.
  double get headerFontSize;

  /// Whether the layout mirrors in a right-to-left chat.
  bool get mirrorsInRtl => policy.mirrorsInRtl;

  /// How selection shows.
  EmojiSelectionStyle get selection;

  /// The shape of the ticks: Android's checks, or iOS's vector ones.
  bool get usesVectorTicks => false;

  /// The corner radius of a pill [height] high.
  double pillRadius(double height);

  /// The corner radius of a header panel.
  double get headerRadius;

  /// The pill for [metrics].
  EmojiPillLayout pill({
    required EmojiMetaMetrics metrics,
    required bool outgoing,
    required ChatEmojiLayoutKind kind,
    EmojiSendState state = EmojiSendState.none,
  });

  /// The height of the strip the body keeps free under its items, for a
  /// [pill] of that size under items [contentHeight] high.
  double bottomReserve({
    required ChatEmojiLayoutKind kind,
    required bool outgoing,
    required double contentHeight,
    required Size pill,
  });

  /// Whether the pill is drawn now. Only Desktop hides it.
  bool showsMeta({
    required bool outgoing,
    required ChatEmojiLayoutKind kind,
    required EmojiOnly emojiOnly,
    required bool hovered,
    required bool isLastOwn,
    required EmojiSendState state,
  }) => true;

  /// The size of a header panel of [shape] around [text].
  Size headerSize({
    required EmojiHeaderShape shape,
    required EmojiHeaderText text,
  });

  /// Sets everything in the row frame.
  EmojiChromeLayout layout(EmojiChromeInput input);

  // The views icon is the reference's 17 x 12 bitmap scaled to a height.
  static const double _viewsAspect = 17 / 12;
}

// --- Android ---------------------------------------------------------------

/// Android's chrome (`A` = `ChatMessageCell.java`, research 04 section 1).
final class EmojiChrome$Android extends EmojiChrome {
  /// Creates the strategy.
  const EmojiChrome$Android();

  /// The pill's height: `max(dp(17), timeTextSize + dp(5))` (`A:23799`, 1.4).
  static const double pillHeight = 17;

  /// The time text's size (`Theme:8983`, 1.4).
  static const double timeSize = 12;

  /// The pill's corner radius: `dp(4) + dp(8)` for any kind of sticker, the
  /// emoji text layout included (`A:23782-23786`, 1.4).
  static const double radius = 12;

  /// Padding between the pill's leading edge and the time (`A:23836`, 1.4).
  static const double padding = 6;

  /// The width a pill adds around the time: 6 + 6 (`A:23799`, 1.4 D).
  static const double chromeWidth = 12;

  /// What an outgoing pill adds for the ticks: 20, and 4 more for the emoji
  /// text layout (`A:23799`, 1.4).
  static const double ticksRoomText = 24;

  /// Ticks room of an outgoing sticker-layout pill.
  static const double ticksRoomSticker = 20;

  /// A check is a 12 x 12 bitmap (`msg_check_s`, 1.5).
  static const double checkSize = 12;

  /// Distance between the full and the half check: 26.3 - 21.5 (`A:24479-24650`,
  /// 1.5).
  static const double checkGap = 4.8;

  /// Distance from the end of a text-layout pill to the end of its checks:
  /// the check ends 27.5 from the row's end (`layoutWidth - 21.5 - 12 - 6`),
  /// the pill 20 (1.5 and 1.4, D).
  static const double checkInsetText = 7.5;

  /// The same for a sticker-layout pill, which ends 22 from the row's end.
  static const double checkInsetSticker = 5.5;

  /// The clock is drawn at `layoutWidth - 22 - width - 6`.
  static const double clockInsetText = 8;

  /// The same for a sticker-layout pill.
  static const double clockInsetSticker = 6;

  /// The clock's size: `MsgClockDrawable`'s intrinsic size was not traced.
  static const double unverifiedClockSize = 12;

  /// The error square: 14 dp (`A`, 1.5).
  static const double errorSize = 14;

  /// The error square ends `layoutWidth - 34.5 - 6 + 14` from the row's end,
  /// 26.5 (1.5, D).
  static const double errorInsetText = 6.5;

  /// The same for a sticker-layout pill.
  static const double errorInsetSticker = 4.5;

  /// The views icon's height: `timeTextSize - 2dp` (`A:24381-24401`, 1.4).
  static const double viewsIconHeight = 10;

  /// The gap between the views icon and its count (1.4).
  static const double viewsIconGap = 3;

  /// The gap between the views block and the time (1.4).
  static const double viewsGap = 10;

  // Under the text (1.4 D): 3 below the text box, the pill, 3 below it.
  static const double _gapAboveStrip = 3;
  static const double _gapBelowPill = 3;

  // A lone emoji is an animated emoji: its pill is `photoBottom - 23 + 16`,
  // so [-7, +10] of the art's bottom, and the cell is 9 + 16 below the art
  // (`A:10446`, `10917-10925`, 1.3 D).
  static const double _stickerPillTop = -7;
  static const double _stickerStrip = 25;

  @override
  ChatEmojiPolicy get policy => const ChatEmojiPolicy.android();

  @override
  double get metaFontSize => timeSize;

  @override
  double get headerFontSize => 14;

  @override
  EmojiSelectionStyle get selection => EmojiSelectionStyle.viewportRowTint;

  @override
  double pillRadius(double height) => radius;

  @override
  double get headerRadius => 4;

  @override
  EmojiPillLayout pill({
    required EmojiMetaMetrics metrics,
    required bool outgoing,
    required ChatEmojiLayoutKind kind,
    EmojiSendState state = EmojiSendState.none,
  }) {
    final text = kind == ChatEmojiLayoutKind.text;
    final views = metrics.viewsWidth;
    const iconWidth = viewsIconHeight * EmojiChrome._viewsAspect;
    final tw =
        metrics.timeWidth + (views == null ? 0 : views + iconWidth + viewsGap);
    final room = !outgoing
        ? 0.0
        : text
        ? ticksRoomText
        : ticksRoomSticker;
    final width = tw + chromeWidth + room;
    final textTop = (pillHeight - metrics.timeHeight) / 2;

    Rect? status;
    if (outgoing) {
      Rect glyphs(double glyphWidth, double glyphHeight, double inset) =>
          Rect.fromLTWH(
            width - inset - glyphWidth,
            (pillHeight - glyphHeight) / 2,
            glyphWidth,
            glyphHeight,
          );
      final check = text ? checkInsetText : checkInsetSticker;
      status = switch (state) {
        EmojiSendState.none => null,
        EmojiSendState.sending => glyphs(
          unverifiedClockSize,
          unverifiedClockSize,
          text ? clockInsetText : clockInsetSticker,
        ),
        EmojiSendState.sent => glyphs(checkSize, checkSize, check),
        EmojiSendState.read => glyphs(checkSize + checkGap, checkSize, check),
        EmojiSendState.error => glyphs(
          errorSize,
          errorSize,
          text ? errorInsetText : errorInsetSticker,
        ),
      };
    }
    return EmojiPillLayout(
      size: Size(width, pillHeight),
      metaWidth: tw,
      timeOrigin: Offset(padding + (tw - metrics.timeWidth), textTop),
      state: state,
      viewsIcon: views == null
          ? null
          : Rect.fromLTWH(padding, textTop + 1.5, iconWidth, viewsIconHeight),
      viewsCountOrigin: views == null
          ? null
          : Offset(padding + iconWidth + viewsIconGap, textTop),
      status: status,
    );
  }

  @override
  double bottomReserve({
    required ChatEmojiLayoutKind kind,
    required bool outgoing,
    required double contentHeight,
    required Size pill,
  }) => kind == ChatEmojiLayoutKind.text
      ? _gapAboveStrip + pill.height + _gapBelowPill
      : _stickerStrip;

  @override
  Size headerSize({
    required EmojiHeaderShape shape,
    required EmojiHeaderText text,
  }) {
    // `replyNameWidth = 4 + name + 4 + 3`, `replyTextWidth = 4 + text + 18`,
    // the panel one more than the larger, 3 (`A:19478-19540`, 1.6).
    final reply = math.max(text.nameWidth + 11, text.textWidth + 22) + 3;
    final forward = text.forwardWidth + 14;
    return switch (shape) {
      EmojiHeaderShape.reply => Size(reply, 43),
      EmojiHeaderShape.forward => Size(forward, 44),
      EmojiHeaderShape.forwardedReply => Size(math.max(forward, reply), 84),
    };
  }

  @override
  EmojiChromeLayout layout(EmojiChromeInput input) {
    final body = input.body;
    final outgoing = input.outgoing;
    final isSticker = body.kind == ChatEmojiLayoutKind.sticker;
    final bodyLeft = outgoing ? input.rowWidth - body.size.width : 0.0;
    final bodyRect = Rect.fromLTWH(
      bodyLeft,
      0,
      body.size.width,
      body.size.height,
    );
    final content = body.content.shift(Offset(bodyLeft, 0));
    final pillSize = input.pill.size;
    final tw = input.pill.metaWidth;

    // 1.4: the text layout's pill is 3 below the text, 1 (incoming) or 4
    // (outgoing) inside its end; the sticker layout's overlaps the art, 5
    // inside it, never left of 1 (`timeX >= 26`).
    final Rect pill;
    if (isSticker) {
      final left = outgoing
          ? content.right - 5 - pillSize.width
          : bodyLeft + math.max(1, content.width - 17 - tw);
      pill = Rect.fromLTWH(
        left,
        content.bottom + _stickerPillTop,
        pillSize.width,
        pillSize.height,
      );
    } else {
      final left = outgoing
          ? content.right - 4 - pillSize.width
          : bodyLeft + math.max(3, content.width - 13 - tw);
      pill = Rect.fromLTWH(
        left,
        content.bottom + _gapAboveStrip,
        pillSize.width,
        pillSize.height,
      );
    }

    Rect? header;
    final headerSize = input.header;
    final shape = input.headerShape;
    if (headerSize != null && shape != null) {
      header = isSticker
          ? _besideSticker(shape, headerSize, content, outgoing)
          : _aboveText(shape, headerSize, bodyLeft, outgoing, input.rowWidth);
    }

    Rect? reactions;
    final reactionsSize = input.reactions;
    if (reactionsSize != null) {
      // 1.7: the row ends at the text's end (outgoing) or starts at its start;
      // it is 29 dp (text) or 23 dp (sticker) under the items.
      final top = content.bottom + (isSticker ? 23 : 29);
      final left = outgoing
          ? content.right + (isSticker ? 1 : 0) - reactionsSize.width
          : bodyLeft + (isSticker ? -4 : 0);
      reactions = Rect.fromLTWH(
        left,
        top,
        reactionsSize.width,
        reactionsSize.height,
      );
    }
    return EmojiChromeLayout(
      body: bodyRect,
      pill: pill,
      header: header,
      reactions: reactions,
    );
  }

  // 1.6: above the text, left-aligned to the box in both directions; the
  // panel's left is `replyStartX - 7`, with `replyStartX` 12 (reply) or 11
  // (forward) past the background's left minus 7 for the emoji layout.
  Rect _aboveText(
    EmojiHeaderShape shape,
    Size size,
    double bodyLeft,
    bool outgoing,
    double rowWidth,
  ) {
    final reply = shape == EmojiHeaderShape.reply;
    var left = reply
        ? (outgoing ? bodyLeft - 9 : bodyLeft - 2)
        : (outgoing ? bodyLeft - 3 : bodyLeft + 4);
    if (outgoing) {
      // The panel is pulled back so its end is 18 (reply) or 7 (forward) in.
      left = math.min(left, rowWidth - (reply ? 18 : 7) - size.width);
    }
    // The text starts at `namesOffset + 6`: 60 (reply), 52 (forward) or 102
    // (both) past the cell's top; the panel is 9.66 / 6 / 6 from it.
    final gap = switch (shape) {
      EmojiHeaderShape.reply => 13.34,
      EmojiHeaderShape.forward => 8.0,
      EmojiHeaderShape.forwardedReply => 18.0,
    };
    return Rect.fromLTWH(left, -(gap + size.height), size.width, size.height);
  }

  // 1.6: beside the sticker; an outgoing one at 23 - 7 = 16 from the row's
  // left edge, an incoming one 17 - 7 + 12 - 3... = 18 from the art's end.
  Rect _besideSticker(
    EmojiHeaderShape shape,
    Size size,
    Rect art,
    bool outgoing,
  ) {
    final left = outgoing ? 16.0 : art.right + 18;
    // `replyStartY = 12.66` for a reply (panel top 9.66, art top 5); the
    // forward panel is 6 from the top.
    final top = shape == EmojiHeaderShape.reply ? 4.66 : 1.0;
    return Rect.fromLTWH(left, art.top + top, size.width, size.height);
  }
}

// --- iOS -------------------------------------------------------------------

/// iOS's chrome (`I` = `ChatMessageAnimatedStickerItemNode`,
/// `ChatMessageDateAndStatusNode`; research 04 section 2).
final class EmojiChrome$Ios extends EmojiChrome {
  /// Creates the strategy.
  const EmojiChrome$Ios();

  /// The pill's height: the date line's height plus 2 + 2. The line height is a
  /// font metric the sources do not give: 17 (`DS:702-715`, 2.4 D).
  static const double unverifiedPillHeight = 17;

  /// The date font (`DS:551`, 2.4).
  static const double dateSize = 11;

  /// The pill's left and right inset (`DS:702-715`, 2.4).
  static const double inset = 7;

  /// The status width of an outgoing pill (`DS:610-665`, 2.4).
  static const double statusWidth = 13;

  /// A check: 11 pt wide, 9 high (`generateCheckImage`, 2.4).
  static const double checkWidth = 11;

  /// A check's height.
  static const double checkHeight = 9;

  /// The distance between the full and the partial check (`DS:610-665`, 2.4).
  static const double checkGap = 6;

  /// The clock: 11 x 11 (`generateClockFrameImage`, 2.4).
  static const double clockSize = 11;

  /// The pill is 4 pt inside the node's end and bottom (`AS:1708`, 2.4).
  static const double edgeInset = 4;

  /// The pill's left stops 3 pt inside the frame; the body is 6 further in
  /// (`displayLeftInset`, `AS:1708`, 2.4 D).
  static const double displayLeftOffset = -6;

  /// The strip under the text: `imageBottomPadding` (`AS:1281-1286`, 2.2).
  static const double textStrip = 20;

  /// The text frame's top padding: `imageTopPadding` (2.2).
  static const double textTopPadding = 16;

  /// A header's top, below the frame's top (`AS:1588-1599`, 2.5).
  static const double headerTop = 8;

  /// An outgoing header's left: `leftInset + edgeInset + 11` (2.5).
  static const double outgoingHeaderLeft = 14;

  /// An incoming header's end, from the row's right: `edgeInset + 9` (2.5).
  static const double incomingHeaderRight = 12;

  /// A reply panel's height: the two lines' metrics are not in the sources, the
  /// research gives about 40 (`ChatMessageReplyInfoNode`, 2.5).
  static const double unverifiedHeaderHeight = 40;

  /// A forward panel's height: not traced, two lines of the reply's size.
  static const double unverifiedForwardHeight = 44;

  /// The views icon's size: the bundle bitmap's was not read; a 17:12 icon the
  /// height of a check.
  static const double unverifiedViewsIconHeight = 9;

  /// The gap in the date text between the count and the time.
  static const double unverifiedViewsSpace = 4;

  /// The space between the views icon and the count: `impressionWidth = iconW + 3`.
  static const double viewsIconGap = 3;

  @override
  ChatEmojiPolicy get policy => const ChatEmojiPolicy.ios();

  @override
  double get metaFontSize => dateSize;

  @override
  double get headerFontSize => 14;

  @override
  EmojiSelectionStyle get selection => EmojiSelectionStyle.none;

  @override
  bool get usesVectorTicks => true;

  @override
  double pillRadius(double height) => height / 2;

  @override
  double get headerRadius => 4;

  @override
  EmojiPillLayout pill({
    required EmojiMetaMetrics metrics,
    required bool outgoing,
    required ChatEmojiLayoutKind kind,
    EmojiSendState state = EmojiSendState.none,
  }) {
    final views = metrics.viewsWidth;
    const iconWidth = unverifiedViewsIconHeight * EmojiChrome._viewsAspect;
    final impression = views == null ? 0.0 : iconWidth + viewsIconGap;
    // The count is part of the date text: `count + " " + date`.
    final date =
        metrics.timeWidth + (views == null ? 0 : views + unverifiedViewsSpace);
    final width = impression + date + (outgoing ? statusWidth : 0) + 2 * inset;
    const height = unverifiedPillHeight;
    final textTop = (height - metrics.timeHeight) / 2;

    Rect? status;
    if (outgoing) {
      // x = leftInset + impression + date + 5 + 13 - checkW - 6, the full
      // check; the partial one is [checkGap] after it (`DS:610-665`).
      final first =
          inset + impression + date + 5 + statusWidth - checkWidth - checkGap;
      status = switch (state) {
        EmojiSendState.none => null,
        EmojiSendState.sending => Rect.fromLTWH(
          inset + impression + date + 8.5,
          (height - clockSize) / 2,
          clockSize,
          clockSize,
        ),
        EmojiSendState.sent => Rect.fromLTWH(
          first,
          (height - checkHeight) / 2,
          checkWidth,
          checkHeight,
        ),
        EmojiSendState.read => Rect.fromLTWH(
          first,
          (height - checkHeight) / 2,
          checkWidth + checkGap,
          checkHeight,
        ),
        // iOS has no error square on a free message: a failed message shows
        // its error beside the node, which is the host's list row.
        EmojiSendState.error => null,
      };
    }
    return EmojiPillLayout(
      size: Size(width, height),
      metaWidth: date,
      timeOrigin: Offset(
        inset + impression + (date - metrics.timeWidth),
        textTop,
      ),
      state: state,
      viewsIcon: views == null
          ? null
          : const Rect.fromLTWH(
              inset,
              (height - unverifiedViewsIconHeight) / 2,
              iconWidth,
              unverifiedViewsIconHeight,
            ),
      viewsCountOrigin: views == null
          ? null
          : Offset(inset + impression, textTop),
      status: status,
    );
  }

  @override
  double bottomReserve({
    required ChatEmojiLayoutKind kind,
    required bool outgoing,
    required double contentHeight,
    required Size pill,
  }) => kind == ChatEmojiLayoutKind.text ? textStrip : 0;

  @override
  Size headerSize({
    required EmojiHeaderShape shape,
    required EmojiHeaderText text,
  }) {
    // `size.width = max(title, text) + leftInset 11 + 6` (2.5).
    final reply = math.max(text.nameWidth, text.textWidth) + 17;
    final forward = text.forwardWidth + 14;
    return switch (shape) {
      EmojiHeaderShape.reply => Size(reply, unverifiedHeaderHeight),
      EmojiHeaderShape.forward => Size(forward, unverifiedForwardHeight),
      EmojiHeaderShape.forwardedReply => Size(
        math.max(reply, forward),
        unverifiedForwardHeight + unverifiedHeaderHeight,
      ),
    };
  }

  @override
  EmojiChromeLayout layout(EmojiChromeInput input) {
    final body = input.body;
    final outgoing = input.outgoing;
    final isSticker = body.kind == ChatEmojiLayoutKind.sticker;
    final bodyLeft = outgoing ? input.rowWidth - body.size.width : 0.0;
    final bodyRect = Rect.fromLTWH(
      bodyLeft,
      0,
      body.size.width,
      body.size.height,
    );
    final pillSize = input.pill.size;

    // 2.4: `x = max(displayLeftInset, maxX - dateW - 4)`,
    // `y = maxY - dateH - 4 (+ the bottom padding)`: the node's end and bottom,
    // for both layouts (the sticker's frame includes its inset).
    final pill = Rect.fromLTWH(
      math.max(
        bodyLeft + displayLeftOffset,
        bodyRect.right - edgeInset - pillSize.width,
      ),
      bodyRect.bottom - edgeInset - pillSize.height,
      pillSize.width,
      pillSize.height,
    );

    Rect? header;
    final headerSize = input.header;
    if (headerSize != null) {
      // 2.5: beside both layouts, pinned to the edge away from the message.
      header = Rect.fromLTWH(
        outgoing
            ? outgoingHeaderLeft
            : input.rowWidth - incomingHeaderRight - headerSize.width,
        isSticker ? headerTop : headerTop - textTopPadding,
        headerSize.width,
        headerSize.height,
      );
    }

    Rect? reactions;
    final reactionsSize = input.reactions;
    if (reactionsSize != null) {
      // 2.6: under the node, aligned to its side.
      reactions = Rect.fromLTWH(
        outgoing ? bodyRect.right - reactionsSize.width : bodyLeft,
        bodyRect.bottom,
        reactionsSize.width,
        reactionsSize.height,
      );
    }
    return EmojiChromeLayout(
      body: bodyRect,
      pill: pill,
      header: header,
      reactions: reactions,
    );
  }
}

// --- Desktop ---------------------------------------------------------------

/// Desktop's chrome (`D` = `history_view_media_unwrapped.cpp`,
/// `history_view_message.cpp`; research 04 section 3).
final class EmojiChrome$Desktop extends EmojiChrome {
  /// Creates the strategy.
  const EmojiChrome$Desktop();

  /// The date font, px (`msgDateFont`, 3.3).
  static const double dateSize = 13;

  /// The pill's padding: `msgDateImgPadding` (8, 2) (3.3).
  static const double paddingX = 8;

  /// The pill's vertical padding.
  static const double paddingY = 2;

  /// The gap between the content and the pill beside it:
  /// `msgReplyPadding.left` (3.3).
  static const double besideGap = 6;

  /// The space a status icon takes: `historySendStateSpace` (3.3).
  static const double statusSpace = 24;

  /// The row's margin an incoming pill stays inside: `msgPadding.left 11 +
  /// msgPadding.right 11` (`calculateFullRight`, 3.3).
  static const double rightSkip = 22;

  /// The wide ceiling of a header's width under which it is beside:
  /// `msgReplyPadding.left + msgMinWidth / 2` (3.4).
  static const double additionalMinWidth = 86;

  /// A header's offset from the element's top: `topicButtonSkip` (3.4).
  static const double headerSkip = 3;

  /// The margin between an above header and the content: `msgMargin.bottom`
  /// (3.4).
  static const double headerMarginBelow = 2;

  /// The least height of the large-emoji row: `largeEmojiSize + outline` (3.3).
  static const double largeRow = 38;

  /// The space between the pill and the content above it: `msgDateImgDelta`
  /// (3.3).
  static const double infoDelta = 4;

  /// Of which, the pixels the content is centred inside its taller row (3.3 D).
  static const double centring = 2;

  /// The pill's corner radius: `roundRadiusLarge` lives in the absent
  /// `lib_ui`, commonly 6 (3.3).
  static const double unverifiedRadius = 6;

  /// The ticks' size: the sprites' sizes are not in the sources.
  static const double unverifiedTickSize = 12;

  /// The gap between two checks: Android's.
  static const double unverifiedTickGap = EmojiChrome$Android.checkGap;

  /// The end padding of the status area, from the pill's end.
  static const double unverifiedStatusInset = paddingX;

  /// The views icon (`historyViewsWidth` 20 is icon plus gap): 12 wide.
  static const double unverifiedViewsIconWidth = 12;

  /// The views block's width before the count: icon plus gap (3.3).
  static const double viewsBlock = 20;

  /// The gap between the views count and the time (`historyViewsSpace`).
  static const double viewsSpace = 8;

  /// The space between the element and the reactions below it: Desktop's own
  /// is in the message widget, not in the sources at hand; iOS's 4.
  static const double unverifiedReactionsGap = 4;

  /// A custom emoji line of more than this many items shows an outgoing time
  /// always (`history_view_custom_emoji.cpp:305-307`, 3.3).
  static const int alwaysShownCustomItems = 3;

  @override
  ChatEmojiPolicy get policy => const ChatEmojiPolicy.desktop();

  @override
  double get metaFontSize => dateSize;

  @override
  double get headerFontSize => 13;

  @override
  EmojiSelectionStyle get selection => EmojiSelectionStyle.glyphRecolour;

  @override
  double pillRadius(double height) => unverifiedRadius;

  @override
  double get headerRadius => unverifiedRadius;

  @override
  EmojiPillLayout pill({
    required EmojiMetaMetrics metrics,
    required bool outgoing,
    required ChatEmojiLayoutKind kind,
    EmojiSendState state = EmojiSendState.none,
  }) {
    final views = metrics.viewsWidth;
    final block = views == null ? 0.0 : viewsBlock + views + viewsSpace;
    final info = block + metrics.timeWidth + (outgoing ? statusSpace : 0);
    final width = info + 2 * paddingX;
    final height = 2 * paddingY + metrics.timeHeight;

    Rect? status;
    if (outgoing) {
      Rect glyphs(double w, double h) => Rect.fromLTWH(
        width - unverifiedStatusInset - w,
        (height - h) / 2,
        w,
        h,
      );
      status = switch (state) {
        EmojiSendState.none => null,
        EmojiSendState.sending => glyphs(
          unverifiedTickSize,
          unverifiedTickSize,
        ),
        EmojiSendState.sent => glyphs(unverifiedTickSize, unverifiedTickSize),
        EmojiSendState.read => glyphs(
          unverifiedTickSize + unverifiedTickGap,
          unverifiedTickSize,
        ),
        EmojiSendState.error => glyphs(
          EmojiChrome$Android.errorSize,
          EmojiChrome$Android.errorSize,
        ),
      };
    }
    return EmojiPillLayout(
      size: Size(width, height),
      metaWidth: info,
      timeOrigin: Offset(paddingX + block, paddingY),
      state: state,
      viewsIcon: views == null
          ? null
          : Rect.fromLTWH(
              paddingX,
              (height - unverifiedViewsIconWidth / EmojiChrome._viewsAspect) /
                  2,
              unverifiedViewsIconWidth,
              unverifiedViewsIconWidth / EmojiChrome._viewsAspect,
            ),
      viewsCountOrigin: views == null
          ? null
          : const Offset(paddingX + viewsBlock, paddingY),
      status: status,
    );
  }

  @override
  double bottomReserve({
    required ChatEmojiLayoutKind kind,
    required bool outgoing,
    required double contentHeight,
    required Size pill,
  }) {
    // 3.3: only a right layout lifts the row to `min(38, content) + 4 + info`;
    // an incoming pill is beside the content. A tall content already holds it.
    if (!outgoing) return 0;
    final lifted = math.min(largeRow, contentHeight) + infoDelta + pill.height;
    final centred = contentHeight <= largeRow ? centring : 0.0;
    return math.max(0, lifted - contentHeight - centred);
  }

  @override
  bool showsMeta({
    required bool outgoing,
    required ChatEmojiLayoutKind kind,
    required EmojiOnly emojiOnly,
    required bool hovered,
    required bool isLastOwn,
    required EmojiSendState state,
  }) {
    // 3.3, `needInfoDisplay`: sending, failed, under the cursor, the last own
    // message, or outgoing with a content that always shows an outgoing time:
    // the large emoji does; a custom emoji line does for more than 3 items in
    // one line; a sticker does not.
    if (state == EmojiSendState.sending || state == EmojiSendState.error) {
      return true;
    }
    if (hovered || isLastOwn) return true;
    if (!outgoing || kind == ChatEmojiLayoutKind.sticker) return false;
    final allCustom = emojiOnly.items.every(
      (item) => item.key is ContentKey$Document,
    );
    if (!allCustom) return true;
    final oneLine = emojiOnly.items
        .skip(1)
        .every((item) => item.lineBreaksBefore == 0);
    return oneLine && emojiOnly.items.length > alwaysShownCustomItems;
  }

  @override
  Size headerSize({
    required EmojiHeaderShape shape,
    required EmojiHeaderText text,
  }) {
    // 3.4: `historyReplyPadding (11, 2, 6, 2)` around a name line and a text
    // line; a forward is stacked above in the same panel,
    // `msgReplyPadding (6, 6, 11, 6)`.
    final reply = Size(
      11 + math.max(text.nameWidth, text.textWidth) + 6,
      2 + text.nameHeight + text.textHeight + 2,
    );
    final forward = Size(
      6 + text.forwardWidth + 11,
      6 + text.forwardHeight + 6,
    );
    return switch (shape) {
      EmojiHeaderShape.reply => reply,
      EmojiHeaderShape.forward => forward,
      EmojiHeaderShape.forwardedReply => Size(
        math.max(reply.width, forward.width),
        forward.height + reply.height,
      ),
    };
  }

  @override
  EmojiChromeLayout layout(EmojiChromeInput input) {
    final body = input.body;
    final outgoing = input.outgoing;
    final rowWidth = input.rowWidth;
    final pillSize = input.pill.size;
    final headerSize = input.header;
    final bodyLeft = outgoing ? rowWidth - body.size.width : 0.0;
    final contentWidth = body.content.width;

    // 3.4: beside when `optimal + min(additional, 86)` fits the row, else above.
    final additional = headerSize == null
        ? pillSize.width + besideGap
        : math.max(pillSize.width, headerSize.width) + besideGap;
    final above =
        headerSize != null &&
        contentWidth + math.min(additional, additionalMinWidth) > rowWidth;

    // The element's own frame first (top 0), then every y is moved so the
    // body's top is 0, as in the other strategies.
    final double elementHeight;
    final double bodyTop;
    if (headerSize == null) {
      elementHeight = body.size.height;
      bodyTop = 0;
    } else if (above) {
      bodyTop = headerSkip + headerSize.height + headerMarginBelow;
      elementHeight = bodyTop + body.size.height;
    } else {
      elementHeight = math.max(
        body.size.height,
        headerSkip + headerSize.height + infoDelta + pillSize.height,
      );
      bodyTop = outgoing ? 0 : elementHeight - body.size.height;
    }
    final contentRight = bodyLeft + body.content.right;

    // 3.3: outgoing, the pill ends where the content ends; incoming, it is
    // 6 after it, kept inside the row's margin. Both sit on the element's
    // bottom.
    final pillRight = outgoing
        ? contentRight
        : math.min(
            contentRight + besideGap + pillSize.width,
            rowWidth - rightSkip,
          );
    final pill = Rect.fromLTWH(
      pillRight - pillSize.width,
      elementHeight - pillSize.height,
      pillSize.width,
      pillSize.height,
    );

    Rect? header;
    if (headerSize != null) {
      final double left;
      final double top;
      if (above) {
        left = outgoing ? contentRight - headerSize.width : bodyLeft;
        top = headerSkip;
      } else {
        left = outgoing
            ? bodyLeft - besideGap - headerSize.width
            : contentRight + besideGap;
        top = headerSkip;
      }
      header = Rect.fromLTWH(left, top, headerSize.width, headerSize.height);
    }

    Rect? reactions;
    final reactionsSize = input.reactions;
    if (reactionsSize != null) {
      reactions = Rect.fromLTWH(
        outgoing ? bodyLeft + body.size.width - reactionsSize.width : bodyLeft,
        elementHeight + unverifiedReactionsGap,
        reactionsSize.width,
        reactionsSize.height,
      );
    }

    final shift = Offset(0, -bodyTop);
    return EmojiChromeLayout(
      body: Rect.fromLTWH(bodyLeft, 0, body.size.width, body.size.height),
      pill: pill.shift(shift),
      header: header?.shift(shift),
      reactions: reactions?.shift(shift),
    );
  }
}

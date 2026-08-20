import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// Where the message column sits when the viewport is wider than
/// [ChatMessageThemeData.contentMaxWidth].
enum ChatMessageColumnPlacement {
  /// Pin the column to the start edge (incoming side in LTR).
  start,

  /// Center the column. Typical desktop / wide-layout chat.
  center,

  /// Pin the column to the end edge (outgoing side in LTR).
  end,
}

/// Layout tokens for a message row inside [ChatScrollView].
///
/// The viewport always lays a row out at the full viewport width. Hosts cap
/// and inset the bubble column with these tokens so message widgets and
/// selection chrome share one source of truth.
///
/// Resolution order: [ChatScrollThemeData.message], then [resolve] from
/// `ThemeData.extensions`, then [fallback].
@immutable
class ChatMessageThemeData extends ThemeExtension<ChatMessageThemeData> {
  /// Creates message-layout tokens.
  const ChatMessageThemeData({
    this.contentMaxWidth = 338,
    this.bubbleMaxWidth = 480,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 2),
    this.runGap = 2,
    this.avatarSize = 32,
    this.avatarGap = 8,
    this.columnPlacement = ChatMessageColumnPlacement.start,
    this.bubbleRadius = 17,
    this.cornerNearCap = 6,
    this.mediaRadiusInset = 2,
    this.mediaNearCap = 3,
    this.bubblePadding = const EdgeInsetsDirectional.fromSTEB(11, 8, 11, 8),
  });

  /// Resolves from [context], falling back to [fallback].
  factory ChatMessageThemeData.resolve(BuildContext context) =>
      Theme.of(context).extension<ChatMessageThemeData>() ?? fallback;

  /// Package defaults — a capped, padded column that centres on wide
  /// viewports and full-bleeds when the viewport is narrower than the cap.
  static const fallback = ChatMessageThemeData();

  /// Maximum width of the message column, including [padding].
  ///
  /// On a narrower viewport the column is `min(viewportWidth, contentMaxWidth)`.
  final double contentMaxWidth;

  /// Maximum width of a single bubble inside the column.
  final double bubbleMaxWidth;

  /// [padding.top] is the gap before the first message in a sender run
  /// (unclustered / new run — ≈ 8dp). [padding.bottom] is the gap after the
  /// last message in a run (Telegram `offsetBottom` when `!drawPinnedBottom`
  /// — ≈ 2dp). Mid-run rows split [runGap] evenly across the shared edge
  /// (half bottom of the upper bubble + half top of the lower).
  final EdgeInsets padding;

  /// Full seam between two bubbles in the same sender run.
  ///
  /// Applied as [runGap] `/ 2` above the lower bubble and `/ 2` below the
  /// upper one. Default `2` → 1+1 between clustered messages.
  final double runGap;

  /// Avatar diameter; also the leading gutter when the avatar is omitted
  /// mid-run.
  final double avatarSize;

  /// Gap between the avatar gutter and the bubble.
  final double avatarGap;

  /// Column placement on viewports wider than [contentMaxWidth].
  final ChatMessageColumnPlacement columnPlacement;

  /// Large corner radius for a bubble that is not clustered on that edge.
  ///
  /// Hosts typically expose this as a settings control (Telegram-style
  /// “message corners”). Clustered outer corners use [nearRadius] instead.
  /// See [ChatBubbleMetrics.bubbleBorderRadius].
  final double bubbleRadius;

  /// Cap on the clustered (“near”) outer corner — applied as
  /// `min(cornerNearCap, bubbleRadius)`.
  final double cornerNearCap;

  /// How much smaller media content radii are than [bubbleRadius]
  /// (`max(0, bubbleRadius - mediaRadiusInset)`).
  final double mediaRadiusInset;

  /// Cap on clustered media content corners —
  /// `min(mediaNearCap, mediaLargeRadius)`.
  final double mediaNearCap;

  /// Base in-bubble content insets before radius-scaled extras.
  ///
  /// Horizontal [EdgeInsetsDirectional.start] / [EdgeInsetsDirectional.end]
  /// are the base content insets before [ChatMessageThemeData.extraTextX].
  /// [ChatBubbleMetrics.bubbleContentPadding] keeps them symmetric (no
  /// Telegram tail-side +6) until a real bubble-tail path exists.
  final EdgeInsetsDirectional bubblePadding;

  /// Clustered outer-corner radius: `min([cornerNearCap], [bubbleRadius])`.
  double get nearRadius => math.min(cornerNearCap, bubbleRadius);

  /// Media content large radius: `max(0, [bubbleRadius] - [mediaRadiusInset])`.
  double get mediaLargeRadius => math.max(0, bubbleRadius - mediaRadiusInset);

  /// Clustered media outer corner: `min([mediaNearCap], [mediaLargeRadius])`.
  double get mediaNearRadius => math.min(mediaNearCap, mediaLargeRadius);

  /// Extra horizontal text inset that grows with [bubbleRadius].
  ///
  /// Matches Telegram: ≥15 → 2, ≥11 → 1, else 0.
  double get extraTextX {
    if (bubbleRadius >= 15) return 2;
    if (bubbleRadius >= 11) return 1;
    return 0;
  }

  /// Column width for [viewportWidth] — never exceeds the viewport or
  /// [contentMaxWidth].
  double columnWidth(double viewportWidth) =>
      math.min(viewportWidth, contentMaxWidth);

  /// Inner width after [padding], for bubble layout.
  double innerWidth(double viewportWidth) =>
      math.max(0, columnWidth(viewportWidth) - padding.horizontal);

  /// Bubble cap for [viewportWidth], optionally subtracting the avatar gutter.
  double bubbleCap(double viewportWidth, {required bool hasAvatarGutter}) {
    var inner = innerWidth(viewportWidth);
    if (hasAvatarGutter) {
      inner -= avatarSize + avatarGap;
    }
    return math.min(bubbleMaxWidth, math.max(0, inner));
  }

  /// Extra width beside the column. Zero when the column is full-bleed.
  double horizontalSlack(double viewportWidth) =>
      math.max(0, viewportWidth - columnWidth(viewportWidth));

  /// Right-side margin of the column — room for a rightward selection slide.
  ///
  /// A centered column splits slack on both sides; an end-aligned column
  /// has no right-side margin.
  double endSlack(double viewportWidth) {
    final slack = horizontalSlack(viewportWidth);
    return switch (columnPlacement) {
      ChatMessageColumnPlacement.start => slack,
      ChatMessageColumnPlacement.center => slack / 2,
      ChatMessageColumnPlacement.end => 0.0,
    };
  }

  /// Whether a [slotWidth] gutter can slide in without pushing the column
  /// past [viewportWidth].
  ///
  /// [padding] lives inside the column, so it is already in this check —
  /// a rightward slide needs [slotWidth] of end margin after the padded
  /// column.
  bool selectionGutterFits({
    required double viewportWidth,
    required double slotWidth,
  }) => endSlack(viewportWidth) >= slotWidth;

  /// Column alignment for a row in [viewportWidth].
  ///
  /// Wide viewports use [columnPlacement]. Narrow (full-bleed) viewports
  /// pin incoming rows to the start and outgoing rows to the end.
  AlignmentDirectional columnAlignment({
    required double viewportWidth,
    required bool outgoing,
  }) {
    if (viewportWidth > bubbleMaxWidth) {
      return switch (columnPlacement) {
        ChatMessageColumnPlacement.start => AlignmentDirectional.centerStart,
        ChatMessageColumnPlacement.center => AlignmentDirectional.center,
        ChatMessageColumnPlacement.end => AlignmentDirectional.centerEnd,
      };
    }
    return outgoing
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;
  }

  /// Top inset for a row in a sender run.
  ///
  /// First-in-run uses [padding.top]; otherwise half of [runGap] (paired with
  /// [bottomInset] on the neighbor above).
  double topInset({required bool isFirstInRun}) =>
      isFirstInRun ? padding.top : runGap / 2;

  /// Bottom inset for a row in a sender run.
  ///
  /// Last-in-run uses [padding.bottom]; otherwise half of [runGap] (paired
  /// with [topInset] on the neighbor below).
  double bottomInset({required bool isLastInRun}) =>
      isLastInRun ? padding.bottom : runGap / 2;

  @override
  ChatMessageThemeData copyWith({
    double? contentMaxWidth,
    double? bubbleMaxWidth,
    EdgeInsets? padding,
    double? runGap,
    double? avatarSize,
    double? avatarGap,
    ChatMessageColumnPlacement? columnPlacement,
    double? bubbleRadius,
    double? cornerNearCap,
    double? mediaRadiusInset,
    double? mediaNearCap,
    EdgeInsetsDirectional? bubblePadding,
  }) => ChatMessageThemeData(
    contentMaxWidth: contentMaxWidth ?? this.contentMaxWidth,
    bubbleMaxWidth: bubbleMaxWidth ?? this.bubbleMaxWidth,
    padding: padding ?? this.padding,
    runGap: runGap ?? this.runGap,
    avatarSize: avatarSize ?? this.avatarSize,
    avatarGap: avatarGap ?? this.avatarGap,
    columnPlacement: columnPlacement ?? this.columnPlacement,
    bubbleRadius: bubbleRadius ?? this.bubbleRadius,
    cornerNearCap: cornerNearCap ?? this.cornerNearCap,
    mediaRadiusInset: mediaRadiusInset ?? this.mediaRadiusInset,
    mediaNearCap: mediaNearCap ?? this.mediaNearCap,
    bubblePadding: bubblePadding ?? this.bubblePadding,
  );

  @override
  ChatMessageThemeData lerp(covariant ChatMessageThemeData? other, double t) {
    if (other == null) return this;
    return ChatMessageThemeData(
      contentMaxWidth: lerpDouble(contentMaxWidth, other.contentMaxWidth, t)!,
      bubbleMaxWidth: lerpDouble(bubbleMaxWidth, other.bubbleMaxWidth, t)!,
      padding: EdgeInsets.lerp(padding, other.padding, t)!,
      runGap: lerpDouble(runGap, other.runGap, t)!,
      avatarSize: lerpDouble(avatarSize, other.avatarSize, t)!,
      avatarGap: lerpDouble(avatarGap, other.avatarGap, t)!,
      columnPlacement: t < 0.5 ? columnPlacement : other.columnPlacement,
      bubbleRadius: lerpDouble(bubbleRadius, other.bubbleRadius, t)!,
      cornerNearCap: lerpDouble(cornerNearCap, other.cornerNearCap, t)!,
      mediaRadiusInset: lerpDouble(
        mediaRadiusInset,
        other.mediaRadiusInset,
        t,
      )!,
      mediaNearCap: lerpDouble(mediaNearCap, other.mediaNearCap, t)!,
      bubblePadding: EdgeInsetsDirectional.lerp(
        bubblePadding,
        other.bubblePadding,
        t,
      )!,
    );
  }
}

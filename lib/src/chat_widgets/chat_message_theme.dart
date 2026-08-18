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
    this.padding = const EdgeInsets.fromLTRB(12, 6, 12, 2),
    this.runGap = 2,
    this.avatarSize = 32,
    this.avatarGap = 8,
    this.columnPlacement = ChatMessageColumnPlacement.start,
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

  /// Insets around the bubble row, inside the column.
  ///
  /// [padding.top] is the gap before the first message in a sender run;
  /// subsequent rows use [runGap] instead.
  final EdgeInsets padding;

  /// Top inset for a message that is not the first in its sender run.
  final double runGap;

  /// Avatar diameter; also the leading gutter when the avatar is omitted
  /// mid-run.
  final double avatarSize;

  /// Gap between the avatar gutter and the bubble.
  final double avatarGap;

  /// Column placement on viewports wider than [contentMaxWidth].
  final ChatMessageColumnPlacement columnPlacement;

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
  double topInset({required bool isFirstInRun}) =>
      isFirstInRun ? padding.top : runGap;

  @override
  ChatMessageThemeData copyWith({
    double? contentMaxWidth,
    double? bubbleMaxWidth,
    EdgeInsets? padding,
    double? runGap,
    double? avatarSize,
    double? avatarGap,
    ChatMessageColumnPlacement? columnPlacement,
  }) => ChatMessageThemeData(
    contentMaxWidth: contentMaxWidth ?? this.contentMaxWidth,
    bubbleMaxWidth: bubbleMaxWidth ?? this.bubbleMaxWidth,
    padding: padding ?? this.padding,
    runGap: runGap ?? this.runGap,
    avatarSize: avatarSize ?? this.avatarSize,
    avatarGap: avatarGap ?? this.avatarGap,
    columnPlacement: columnPlacement ?? this.columnPlacement,
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
    );
  }
}

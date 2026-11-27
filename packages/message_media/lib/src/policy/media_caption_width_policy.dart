import 'dart:math' as math;

import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:meta/meta.dart';

/// How a caption's width and its media's width relate, per platform: the
/// [MediaWidthMetrics] a layout carries for the bubble to wrap its caption
/// at.
///
/// | | [rule] | The caption wraps at |
/// | --- | --- | --- |
/// | Android | `widenMedia` | the bubble's max content width |
/// | iOS | `wrapAtMedia` | the media's max width (the block width) |
/// | Desktop | `widenMedia` | the bubble's max content width, up to [widenLimit] 430 |
///
/// Never narrower than the media itself. Under either rule the media widens
/// to a caption wider than it, when the host passes the caption's measured
/// width (`MediaLayoutInput.captionWidth`) to the layout: the box sizing
/// widens the box, up to its own limit.
@immutable
final class MediaCaptionWidthPolicy {
  /// A caption width policy of [rule], widening up to [widenLimit].
  const MediaCaptionWidthPolicy({required this.rule, this.widenLimit});

  /// The Android family: the caption may be wider than the media.
  const MediaCaptionWidthPolicy.android()
    : this(rule: MediaCaptionWidthRule.widenMedia);

  /// The iOS family: the media's max width caps the bubble.
  const MediaCaptionWidthPolicy.ios()
    : this(rule: MediaCaptionWidthRule.wrapAtMedia);

  /// The desktop family: the caption widens the media up to 430.
  const MediaCaptionWidthPolicy.desktop()
    : this(rule: MediaCaptionWidthRule.widenMedia, widenLimit: 430);

  /// How the caption and the media widths relate.
  final MediaCaptionWidthRule rule;

  /// The widest a `widenMedia` caption wraps at; null is the bubble's max
  /// content width alone.
  final double? widenLimit;

  /// The metrics of a layout [mediaWidth] wide laid out from [input], whose
  /// media may take [blockWidth]; null when the media has no caption (no
  /// items, or no text next to them).
  MediaWidthMetrics? metricsOf(
    MediaLayoutInput input, {
    required double mediaWidth,
    required double blockWidth,
  }) {
    if (!input.hasText || input.items.isEmpty) return null;
    final limit = switch (rule) {
      MediaCaptionWidthRule.widenMedia => math.min(
        input.contentWidth,
        widenLimit ?? double.infinity,
      ),
      MediaCaptionWidthRule.wrapAtMedia => blockWidth,
    };
    return MediaWidthMetrics(
      rule: rule,
      captionMaxWidth: math.max(mediaWidth, limit),
    );
  }

  /// A copy with the given values replaced.
  MediaCaptionWidthPolicy copyWith({
    MediaCaptionWidthRule? rule,
    double? widenLimit,
  }) => MediaCaptionWidthPolicy(
    rule: rule ?? this.rule,
    widenLimit: widenLimit ?? this.widenLimit,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaCaptionWidthPolicy &&
      other.rule == rule &&
      other.widenLimit == widenLimit;

  @override
  int get hashCode => Object.hash(rule, widenLimit);
}

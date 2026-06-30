import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:flutter/rendering.dart';

/// Floating-header height assumed for the inline-divider fade before the real
/// header has been laid out (first frame only).
const double kHeaderFallbackHeight = 32;

/// Travel distance over which an inline date separator fades in / out near the
/// floating header — short, so it reaches full opacity almost as soon as it
/// clears the header.
const double kDividerFadeBand = 20;

/// Topmost visible day group visible in the viewport.
typedef TopDayScan = ({Object? bucket, int? id});

/// Owns floating day-header state and pure geometry for [RenderChatScrollView].
///
/// The render object owns the header [RenderBox], calls [scanTopDay] with live
/// children, and executes `buildFloatingHeader` / `layout` inside
/// `invokeLayoutCallback`. This class reads child parent data via callbacks
/// supplied by the render object — it never inflates or parents widgets.
///
/// **Layout vs tick:**
/// - [evaluateLayoutRebuild] — end of `performLayout`; may request a header
///   widget rebuild when the topmost day bucket changes or [headerDirty] is set.
/// - [tickForDayChange] — Tier-1 scroll path; detects bucket change without
///   rebuilding; caller relayouts when `true`.
class ChatFloatingHeaderController {
  /// Group bucket the floating header was last built for; `null` = none.
  /// The header is rebuilt only when the topmost visible group changes.
  Object? headerBucket;

  /// Date the header currently shows — for debugging / introspection.
  DateTime? headerDate;

  /// Set when the header must rebuild regardless of the day (its builder
  /// reference changed). Consumed by the next layout pass.
  bool headerDirty = false;

  /// Force rebuild on the next layout — used when the header builder reference
  /// changes, which the day-bucket gate cannot detect.
  void invalidate() => headerDirty = true;

  /// Reset after a data-source swap — old buckets/dates belong to the prior
  /// conversation.
  void resetOnDataSourceChange() {
    headerBucket = null;
    headerDate = null;
    headerDirty = true;
  }

  /// Clear header state when entering overlay mode (loading / empty).
  void clearForOverlay() {
    headerBucket = null;
    headerDate = null;
    headerDirty = false;
  }

  /// Height of the floating header — its laid-out size, or [kHeaderFallbackHeight]
  /// before it has first laid out.
  double floatingHeaderHeight(RenderBox? header) =>
      (header != null && header.hasSize)
      ? header.size.height
      : kHeaderFallbackHeight;

  /// Fade opacity for an inline date separator whose top edge sits at
  /// viewport-Y [topY]. Reaches full as soon as the separator clears the
  /// floating header's bottom edge, fading over a short [kDividerFadeBand] as
  /// it rises into the header's zone — so the two never both show.
  double dividerOpacityFor({
    required double topY,
    required double topPad,
    required double floatingHeaderHeight,
  }) {
    final fadeEnd = topPad + floatingHeaderHeight;
    return ((topY - fadeEnd) / kDividerFadeBand + 1.0).clamp(0.0, 1.0);
  }

  /// The topmost visible group — the bucket + message id of the first child
  /// crossing the top edge. O(visible children) of pure parent-data reads.
  ///
  /// [offsetOf], [dayBucketOf], and [heightOf] are supplied by the render
  /// object so this class stays decoupled from [ChatMessageParentData].
  TopDayScan scanTopDay({
    required Iterable<MapEntry<int, RenderBox>> children,
    required double topPad,
    required double viewportHeight,
    required double Function(RenderBox child) offsetOf,
    required Object? Function(RenderBox child) dayBucketOf,
    required double Function(RenderBox child) heightOf,
  }) {
    final topEdge = topPad;
    for (final entry in children) {
      final child = entry.value;
      final offset = offsetOf(child);
      if (offset + heightOf(child) <= topEdge) continue; // above the top
      if (offset >= viewportHeight) break; // below the viewport
      final bucket = dayBucketOf(child);
      if (bucket != null) return (bucket: bucket, id: entry.key);
    }
    return (bucket: null, id: null);
  }

  /// Whether the header widget must rebuild and which bucket/date to pass to
  /// the element-side builder. Updates [headerBucket] / [headerDate] when
  /// rebuild is needed.
  ({
    bool needsRebuild,
    Object? bucket,
    DateTime? firstMessageDate,
  }) evaluateLayoutRebuild({
    required TopDayScan scan,
    required Object Function(IChatMessage)? groupBy,
    required DateTime? Function(int messageId) createdAtOf,
  }) {
    final targetBucket = groupBy == null ? null : scan.bucket;
    if (targetBucket != headerBucket || headerDirty) {
      headerBucket = targetBucket;
      headerDirty = false;
      headerDate = (targetBucket == null || scan.id == null)
          ? null
          : createdAtOf(scan.id!);
      return (
        needsRebuild: true,
        bucket: targetBucket,
        firstMessageDate: headerDate,
      );
    }
    return (
      needsRebuild: false,
      bucket: headerBucket,
      firstMessageDate: headerDate,
    );
  }

  /// During a Tier-1 scroll: report whether the topmost day changed — the
  /// caller then relayouts to rebuild the header text. Placement is handled
  /// separately by the render object ([placeHeaderOffset]).
  bool tickForDayChange({
    required TopDayScan scan,
    required Object Function(IChatMessage)? groupBy,
    required bool hasFloatingHeader,
  }) {
    if (!hasFloatingHeader && groupBy == null) return false;
    final targetBucket = groupBy == null ? null : scan.bucket;
    return targetBucket != headerBucket;
  }

  /// Viewport-local Y for the floating header's top edge — pinned below the
  /// top inset; never moves with scroll.
  double placeHeaderOffset({required double topPad}) => topPad;
}

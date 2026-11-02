import 'package:chat_scroll_view/src/chat_scroll/chat_animator.dart';
import 'package:meta/meta.dart' show immutable;

/// A point-in-time copy of the viewport's internal state, for tests.
///
/// `RenderChatScrollView.debugSnapshot` builds one per read, so a field read
/// is as fresh as the call and a held snapshot never changes underneath the
/// test. Collections are copies. Nothing in `lib/` reads this; it exists so
/// the render object carries one test accessor instead of one per fact.
@immutable
final class ChatScrollDebugSnapshot {
  /// Creates a snapshot from the values read off the render object.
  const ChatScrollDebugSnapshot({
    required this.childCount,
    required this.chunkErrorCount,
    required this.chunkCount,
    required this.layoutMinChunk,
    required this.layoutMaxChunk,
    required this.firstId,
    required this.lastId,
    required this.builtMessageIds,
    required this.stretchOverscroll,
    required this.hasFloatingHeader,
    required this.floatingHeaderVisible,
    required this.floatingHeaderOffset,
    required this.floatingHeaderOpacity,
    required this.headerDate,
    required this.headerBucket,
    required this.highlightTargetId,
    required this.pendingHighlightTargetId,
    required this.highlightFactor,
    required this.highlightPhase,
    required this.farAnimateActive,
    required this.farAnimateJumped,
    required this.isAnimating,
    required this.loadGateWaiting,
    required this.stitchOutgoingIds,
    required this.stitchProgress,
    required this.stitchScrollLength,
    required this.lastRepositionVisits,
    required this.scrollActivity,
  });

  /// Count of message children in the sparse child map.
  final int childCount;

  /// Count of chunk-error overlay children currently built.
  final int chunkErrorCount;

  /// Number of pagination chunks held by the data source.
  final int chunkCount;

  /// Lowest chunk index included in the last layout fan-out.
  final int layoutMinChunk;

  /// Highest chunk index included in the last layout fan-out.
  final int layoutMaxChunk;

  /// Smallest message id with a built child, or `null` when empty.
  final int? firstId;

  /// Largest message id with a built child, or `null` when empty.
  final int? lastId;

  /// Built message ids (fan-out plus stitch-pinned outgoing).
  final Set<int> builtMessageIds;

  /// Paint stretch in `[-1, 1]`; zero at rest and under any other edge
  /// effect.
  final double stretchOverscroll;

  /// Whether a floating header child is attached (it may still be hidden, see
  /// [floatingHeaderVisible]).
  final bool hasFloatingHeader;

  /// Whether the floating header would be painted this frame (suppressed above
  /// the oldest boundary during short content).
  final bool floatingHeaderVisible;

  /// Viewport-local Y of the floating header's top edge, if built.
  final double? floatingHeaderOffset;

  /// Opacity the floating header resolved to this frame.
  final double floatingHeaderOpacity;

  /// Calendar date shown in the floating header, if any.
  final DateTime? headerDate;

  /// Group bucket the floating header was last built for.
  final Object? headerBucket;

  /// Message id receiving the post-navigation highlight tint.
  final int? highlightTargetId;

  /// Message id waiting for a loaded message with a built child before the
  /// highlight arms.
  final int? pendingHighlightTargetId;

  /// Highlight animation progress in `0..1` for [highlightTargetId]; the
  /// solid hold stays at `1.0`, the fade declines toward `0`.
  final double highlightFactor;

  /// Current highlight phase.
  final ChatHighlightPhase highlightPhase;

  /// Whether the far-path stitch is in flight (post-jump dual-translate).
  final bool farAnimateActive;

  /// Whether the stitch has already run its teleport `jumpTo`.
  final bool farAnimateJumped;

  /// Whether any `animateTo` (close, stitch, or preferBuilt wait) is in
  /// flight.
  final bool isAnimating;

  /// Whether close-path versus stitch is deferred under the navigation
  /// load-gate.
  final bool loadGateWaiting;

  /// Outgoing ids retained during stitch (GC pin plus frozen paint Y).
  final Set<int> stitchOutgoingIds;

  /// Stitch progress `0..1` after measure; `0` before measure or when idle.
  final double stitchProgress;

  /// Measured stitch travel (px) after layout measure; `0` before measure.
  final double stitchScrollLength;

  /// Ids the last reposition-from-anchor walk visited (debug builds only):
  /// bounded by the built rows and chunk-error tiles, not the id span.
  final int lastRepositionVisits;

  /// Current scroll activity; `1` without an activity clock.
  final double scrollActivity;
}

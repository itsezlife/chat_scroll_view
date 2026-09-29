import 'dart:async';

import 'package:chat_scroll_view/src/chat_scroll/animate_to_busy_policy.dart';
import 'package:chat_scroll_view/src/chat_scroll/animate_to_disposition.dart';
import 'package:chat_scroll_view/src/chat_scroll/animate_to_load_policy.dart';
import 'package:chat_scroll_view/src/chat_scroll/animate_to_path.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_events.dart';
import 'package:chat_scroll_view/src/chat_scroll/navigation_placement.dart';
import 'package:chat_scroll_view/src/chat_scroll/tail_or_target_outcome.dart';
import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

export 'package:chat_scroll_view/src/chat_scroll/animate_to_busy_policy.dart';
export 'package:chat_scroll_view/src/chat_scroll/animate_to_disposition.dart';
export 'package:chat_scroll_view/src/chat_scroll/animate_to_load_policy.dart';
export 'package:chat_scroll_view/src/chat_scroll/animate_to_path.dart';
export 'package:chat_scroll_view/src/chat_scroll/tail_or_target_outcome.dart';

/// Visibility metrics for one built message row intersecting the paint band.
///
/// [visibleFraction] is `visible_intersection_height /
/// min(height, paintBandHeight)`, clamped to `0.0`–`1.0`. When [height] is at
/// least the parent range's [ChatVisibleRange.paintBandHeight], the fraction
/// used the band-height denominator — use [visibleRowFillsBand] with that band
/// height before treating the fraction as share-of-message read.
typedef ChatVisibleRow = ({int id, double visibleFraction, double height});

/// Visible-range snapshot exposed by [ChatScrollController.visibleRange].
///
/// [firstId] / [lastId] are inclusive id bounds of children whose rect
/// intersects the viewport's logical paint area (top inset to bottom inset).
/// Chunk-error id expansion may widen [lastId] beyond built children.
///
/// [lastRow] is the built child that owns the tail [ChatVisibleRow.visibleFraction]
/// — key progressive-read and threshold logic off [lastRow.id], not [lastId]
/// alone.
///
/// Layout anchor: [ChatScrollController.anchorMessageId] (not duplicated here).
/// Optional [anchorNextRow] describes `anchorMessageId + 1` when built and
/// intersecting — near-tail unread without equating [firstId] to first unread.
///
/// [anyRowFillsBand] is `true` when any built child intersecting the paint band
/// is at least as tall as the band — tall content is on screen.
typedef ChatVisibleRange = ({
  int firstId,
  int lastId,
  double paintBandHeight,
  bool anyRowFillsBand,
  ChatVisibleRow firstRow,
  ChatVisibleRow lastRow,
  ChatVisibleRow? anchorNextRow,
});

/// Whether [rowHeight] used the band-height denominator for a visible fraction.
bool visibleRowFillsBand(double rowHeight, double paintBandHeight) =>
    paintBandHeight > 0 && rowHeight >= paintBandHeight;

/// Snapshot of the Message under the fixed mid paint-band ray.
///
/// Hosts observe this via [ChatScrollController.centerBand] for leave/reopen
/// reading position. It is **not** the layout Anchor origin
/// ([ChatScrollController.anchorMessageId] /
/// [ChatScrollController.anchorPixelOffset]).
///
/// [messageId] is the built Message whose rect contains the center-band ray
/// (50% of the paint band between reserved top and bottom insets).
/// [offsetFromMessageTop] is logical pixels from that Message's top edge down
/// to the ray — so a tall bubble scrolled mid-row reports a non-zero offset
/// inside that Message.
///
/// Value equality supports debounce / “did the leave point change?” checks.
/// Floating headers, chunk-error tiles, and overlay slots are never reported.
@immutable
final class ChatCenterBand {
  /// Creates a Center Band snapshot for [messageId] at [offsetFromMessageTop].
  const ChatCenterBand({
    required this.messageId,
    required this.offsetFromMessageTop,
  });

  /// Built Message id whose rect contains the center-band ray.
  final int messageId;

  /// Logical pixels from [messageId]'s top edge down to the center-band ray.
  ///
  /// Produced values lie in `[0, messageHeight)` for the hit-test used by the
  /// viewport (`top <= rayY < bottom`).
  final double offsetFromMessageTop;

  @override
  bool operator ==(Object other) =>
      other is ChatCenterBand &&
      other.messageId == messageId &&
      other.offsetFromMessageTop == offsetFromMessageTop;

  @override
  int get hashCode => Object.hash(messageId, offsetFromMessageTop);

  @override
  String toString() =>
      'ChatCenterBand(messageId: $messageId, '
      'offsetFromMessageTop: $offsetFromMessageTop)';
}

/// Delegate that performs `animateTo` motion and Message highlight paint on
/// behalf of [ChatScrollController]. Implemented by [ChatAnimator] and bound
/// automatically when the widget mounts; consumers do not interact with this
/// directly.
abstract class ChatScrollAnimator {
  /// Whether an [animate] call is currently in flight.
  bool get isAnimating;

  /// Target id of the in-flight [animate], if any (undefined when idle).
  int get animateTargetId;

  /// Alignment of the in-flight [animate], if any (undefined when idle).
  double get animateAlignment;

  /// Additive pixel offset of the in-flight [animate], if any (undefined
  /// when idle).
  double get animatePixelOffset;

  /// Scrolls so [targetId] lands at [alignment] within the viewport scroll
  /// band between top and bottom insets (`0` = band top, `1` = band bottom)
  /// over [duration] with [curve].
  ///
  /// When [highlight] is `true`, the viewport briefly tints the target row
  /// after the animation settles — used by search / deep-link navigation.
  ///
  /// [loadPolicy] controls waiting for an unbuilt target before choosing
  /// close-path vs far-path stitch.
  ///
  /// Same-target spam while animating coalesces onto the in-flight future.
  /// Different-target spam is ignored by default, or cancelled and replaced
  /// when [busyPolicy] is [AnimateToBusyPolicy.replace].
  ///
  /// Completes with the [AnimateToPath] the flight took — on settle and on
  /// cancel. A coalesced call completes with the in-flight flight's path; an
  /// ignored call completes at once with [AnimateToPath.none].
  Future<AnimateToPath> animate(
    int targetId, {
    required Duration duration,
    required Curve curve,
    double alignment = 0.0,
    bool highlight = true,
    AnimateToLoadPolicy loadPolicy = AnimateToLoadPolicy.immediate,
    AnimateToBusyPolicy busyPolicy = AnimateToBusyPolicy.ignore,
    double pixelOffset = 0.0,
  });

  /// Cancels the in-flight [animate] without arming a highlight.
  void cancel();

  /// Request Message highlight on [messageId] without changing Anchor origin.
  ///
  /// Replaces any previous request. Arms a solid wash when the row is a loaded
  /// Message with a built child (same id restarts hold); otherwise defers
  /// until layout/data make that row ready. Absent or error drops the request
  /// (controller slot included) so bind cannot late-arm. [Duration.zero]
  /// highlight duration on the bound viewport is a silent no-op.
  void requestHighlight(int messageId);

  /// Drop pending or armed Message highlight immediately (no fade).
  void clearHighlight();
}

/// Scroll controller for [ChatScrollView].
///
/// Owns anchor state and navigation: which message is the layout origin, its
/// pixel offset, the jump / animate / Center Band apply entry points, the
/// Message highlight request slot, deferred paint-band listenables
/// ([visibleRange], [centerBand], [isAtTail]), the typed event stream
/// (drag, fling, jump), and the host's claims on the scrollbar
/// ([holdScrollbar], [suppressScrollbar], [flashScrollbar]) for conditions
/// the viewport cannot see. Conversation boundaries (`oldestKnownId`,
/// `reachedOldest`, …) live on [ChatDataSource] — they describe the *data*,
/// not the navigation.
///
/// Uses typed listeners instead of [ChangeNotifier] — subscribers know
/// exactly what event occurred.
class ChatScrollController {
  /// Whether an [animateTo] is currently in flight.
  ///
  /// Under [AnimateToBusyPolicy.ignore], hosts that keep a selection index
  /// should refuse to advance that index while this is `true` (or only commit
  /// after [animateTo] returns a non-[AnimateToDisposition.ignored]
  /// disposition).
  bool get isAnimating => _animator?.isAnimating ?? false;

  // --- Jump: typed listener with payload ---

  /// Plain `List` so the field's runtime type stays stable across hot-reload
  /// (a `Set<>` would trip `_Set is not List` on any old code path that
  /// hadn't been re-jited yet). `addJumpListener` dedups explicitly so a
  /// double-registration with the same closure is a no-op.
  final _jumpListeners = <ValueChanged<int>>[];

  /// Subscribe to jump events. Callback receives the target message ID.
  /// Adding the same callback twice is a no-op.
  void addJumpListener(ValueChanged<int> callback) {
    if (_jumpListeners.contains(callback)) return;
    _jumpListeners.add(callback);
  }

  /// Unsubscribe from jump events.
  void removeJumpListener(ValueChanged<int> callback) =>
      _jumpListeners.remove(callback);

  /// Jump to a specific message, resetting the anchor.
  ///
  /// [alignment] positions the target within the viewport's scrollable band
  /// between the top inset and bottom inset. `0.0` places the message top at
  /// the band top (below [ChatScrollView.topPadding]); `0.5` centers it;
  /// `1.0` aligns the message bottom to the bottom inset. Boundary clamping may reduce the effective
  /// alignment when insufficient content exists above or below.
  ///
  /// **Alignment hold**: once the target has landed as a loaded row, the
  /// alignment stays held on it until the first user scroll (drag, fling,
  /// wheel, scrollbar drag), [scrollBy], or the next [jumpTo] /
  /// [animateTo] / [jumpToCenterBand]. While held, a
  /// [ChatScrollView.topPadding] change or a row chrome change on the target
  /// row (such as the unread separator appearing on it) re-applies the
  /// alignment, so the row — row chrome included — keeps its place in the
  /// scroll band instead of sliding under top chrome. Everything else keeps
  /// its usual effect: bottom inset changes are compensated, the boundary
  /// clamp may still reduce the alignment, and row chrome changes on other
  /// rows keep the reading position. The hold ends without moving anything
  /// when the target stops being the layout origin (it becomes absent, or
  /// the list follows the tail). A target that is the known newest is not
  /// held — the tail pin owns its geometry.
  ///
  /// **Highlight**: default [highlight] is `false` — geometry only. Hosts
  /// MUST treat that as a hard-clear of any leftover Message highlight
  /// request (same as [jumpToCenterBand]). Pass `true` to write origin then
  /// request [highlight] so the jump hard-clear cannot drop the wash.
  ///
  /// **Tail or target**: a non-null [tailFitFraction] makes the jump choose
  /// between [messageId] and the tail in one layout — the first that lays
  /// out [messageId] as a loaded message row, which for a jump issued before
  /// the view mounts, or onto a row that is still loading, is a later
  /// layout. It measures the span from the target row's body top, its row
  /// chrome excluded, to the newest message's bottom. When the newest
  /// message is known (`ChatDataSource.reachedNewest`) and loaded and the
  /// span is at most [tailFitFraction] of the viewport height, the chat
  /// opens pinned at the tail ([TailOrTargetOutcome.tail]); otherwise the
  /// target is placed at [alignment] as usual
  /// ([TailOrTargetOutcome.target]). The fraction MUST be within `0..1`;
  /// release builds clamp it. Frames before that layout paint the target
  /// region as it loads, and never the tail.
  ///
  /// The outcome goes to [addTailOrTargetListener] listeners synchronously
  /// inside that layout, before any of it is painted. A change a listener
  /// makes to the viewport's unread boundary is laid out in the same pass:
  /// clearing it on [TailOrTargetOutcome.tail] means no frame paints the
  /// unread separator at the tail, and setting it on
  /// [TailOrTargetOutcome.target] lands the separator at [alignment] plus
  /// [pixelOffset] with the body below it. The jump reports at most once,
  /// and not at all when it is released before deciding — by a user scroll,
  /// [scrollBy], or the next navigation, including when its target never
  /// loads.
  ///
  /// **Pixel offset**: [pixelOffset] is added after the alignment seat
  /// (`topPad + alignment * free travel + pixelOffset`). Positive values
  /// move the target down the scroll band. Free travel depends on row and
  /// viewport height, so alignment alone cannot hold a fixed inset below the
  /// band top. Hosts that need one pass it here. The alignment hold
  /// re-applies the same offset when the band top moves or the target's row
  /// chrome changes.
  ///
  /// **Absent-target behavior**: if [messageId] is confirmed absent after its
  /// owning chunk's fetch resolves (see `ChatMessageStatus.absent`), the
  /// navigation completes without error and the viewport renders no row at
  /// that position. The anchor is set to [messageId] as requested, but
  /// because absent slots have zero height the viewport behaves as if the
  /// nearest non-absent neighbor were the effective anchor. Integrators MUST
  /// NOT assume the viewport moved to [messageId] — verify via
  /// `ChatDataSource.statusOf` before navigating, or navigate to the nearest
  /// known-present ID instead.
  void jumpTo(
    int messageId, {
    double alignment = 0.0,
    bool highlight = false,
    double? tailFitFraction,
    double pixelOffset = 0.0,
  }) {
    if (_disposed) return;
    _debugCheckNotDispatchingTailOrTarget('jumpTo');
    assert(
      tailFitFraction == null ||
          (tailFitFraction >= 0 && tailFitFraction <= 1),
      'tailFitFraction must be within 0..1, got $tailFitFraction',
    );
    // Absent targets: the anchor id is updated below, but absent slots render
    // at zero height — the viewport does not scroll to a visible row at
    // [messageId]. Fan-out and clamping behave as if the nearest non-absent
    // neighbor were the effective position. Check statusOf(messageId).isAbsent
    // before navigating if the user must see a specific message. ADR 002.
    _anchorMessageId = messageId;
    _anchorPixelOffset = 0.0;
    _navigationPlacement = NavigationPlacement.alignment(
      messageId,
      alignment,
      tailFitFraction: tailFitFraction,
      pixelOffset: pixelOffset,
    );
    if (!highlight) {
      // Geometry jump drops leftover attention. Stitch-owned jumps still skip
      // animator hard-clear in the viewport `_onJump`; the animator re-asserts
      // its in-flight wash after teleport.
      _requestedHighlightMessageId = null;
    }
    _notifyJump(messageId);
    if (highlight) {
      this.highlight(messageId);
    }
  }

  /// Request Message highlight on [messageId] without changing Anchor origin.
  ///
  /// One pending slot: a new call replaces any previous request. When the
  /// viewport is bound, the animator arms a solid wash if [messageId] is a
  /// loaded Message with a built child, otherwise defers until that row is
  /// ready (layout / data — no pending ticker). Hold starts immediately when
  /// already aligned (no extra motion). A same-id call while the row is on
  /// screen restarts hold. If a wash is already painted on a different id,
  /// that wash is hard-cleared then the new id is armed or deferred. Absent
  /// or error drops the request (and this slot) so a later upsert cannot
  /// late-arm.
  ///
  /// MUST NOT write Anchor origin — use [jumpTo] with `highlight: true`
  /// (or [jumpTo] then this) when first layout must fan out from [messageId].
  /// MUST NOT notify jump or scroll listeners. Post-[dispose] calls MUST be
  /// silent no-ops (they are). `highlightDuration: Duration.zero` on the view
  /// still disables paint globally.
  void highlight(int messageId) {
    if (_disposed) return;
    _requestedHighlightMessageId = messageId;
    _animator?.requestHighlight(messageId);
  }

  /// Place the paint-band center-band ray at
  /// `[messageId]` top + [offsetFromMessageTop].
  ///
  /// One layout navigation for leave/reopen reading position — hosts MUST NOT
  /// compose [jumpTo] + [scrollBy] for this job (ADR 009). The viewport applies
  /// the pending Center Band after the target row is built (same build /
  /// settle lifecycle as [jumpTo] alignment), writing Anchor origin so the
  /// ray hits that within-message offset.
  ///
  /// [offsetFromMessageTop] is logical pixels from the Message's top edge
  /// down toward newer content — the same coordinate as
  /// [ChatCenterBand.offsetFromMessageTop]. Non-finite values are a silent
  /// no-op (no jump listeners, no [ChatProgrammaticJump]). Values outside
  /// the eventual row height are clamped at apply time so the ray stays
  /// inside the Message rect.
  ///
  /// Emits the same jump listeners and [ChatProgrammaticJump] as [jumpTo].
  /// A pending or held band alignment from a prior [jumpTo] / [animateTo] is
  /// cleared — Center Band placement and fractional alignment are mutually
  /// exclusive placements. Once placed on a loaded row, the Center Band is
  /// held with the same lifecycle as the [jumpTo] alignment hold: a
  /// [ChatScrollView.topPadding] change or a row chrome change on the target
  /// re-places the ray at [offsetFromMessageTop], until the first user
  /// scroll, [scrollBy], or the next navigation. Unlike [jumpTo], a
  /// known-newest target is placed and held too. Leftover Message highlight is hard-cleared — restore
  /// is not attention (ADR 009). There is no highlight flag on this method.
  ///
  /// **Absent-target behavior**: same ADR 002 caution as [jumpTo] — navigation
  /// completes without error; absent slots have zero height and do not produce
  /// a visible row at [messageId]. Post-[dispose] calls are silent no-ops.
  void jumpToCenterBand(int messageId, double offsetFromMessageTop) {
    if (_disposed) return;
    _debugCheckNotDispatchingTailOrTarget('jumpToCenterBand');
    if (!offsetFromMessageTop.isFinite) return;
    // Absent targets: same contract as [jumpTo] — see ADR 002.
    _anchorMessageId = messageId;
    _anchorPixelOffset = 0.0;
    _setNavigationCenterBand(messageId, offsetFromMessageTop);
    // Restore is geometry-only (ADR 009) — leftover attention must not ride
    // the Center Band apply.
    _requestedHighlightMessageId = null;
    _notifyJump(messageId);
  }

  /// Places the scroll band's top edge [fraction] of the way into
  /// [messageId]'s row: `0` at the row's top edge, `1` at its bottom edge.
  /// The scrollbar grab's navigation, one call per pointer move.
  ///
  /// Writes Anchor origin, notifies jump listeners, emits
  /// [ChatProgrammaticJump], and hard-clears leftover Message highlight,
  /// like a [jumpTo] without highlight — so the viewport's jump reaction
  /// (fetch wake, load-gate release, fling and edge-effect cancel) runs on
  /// every call. [fraction] is clamped to `0..1`; a non-finite value is a
  /// silent no-op.
  ///
  /// The viewport seats the row once it is built, its top at
  /// `fraction × row height` above the band top, with the same pending →
  /// held → released lifecycle as [jumpTo] alignment. While pending, every
  /// layout re-seats the row, so a row still loading lands at [fraction] of
  /// its real height once loaded. Unlike an alignment jump, a known-newest
  /// target is seated too: the jump-to-tail pin is not armed while this
  /// placement is pending, and the boundary clamp alone keeps the newest
  /// row's bottom from rising above the bottom inset.
  ///
  /// Absent targets behave as for [jumpTo] (ADR 002). Post-[dispose] calls
  /// are silent no-ops.
  @internal
  void jumpToFraction(int messageId, double fraction) {
    if (_disposed) return;
    _debugCheckNotDispatchingTailOrTarget('jumpToFraction');
    if (!fraction.isFinite) return;
    _anchorMessageId = messageId;
    _anchorPixelOffset = 0.0;
    _navigationPlacement = NavigationPlacement.fractional(messageId, fraction);
    _requestedHighlightMessageId = null;
    _notifyJump(messageId);
  }

  void _notifyJump(int messageId) {
    // Iterate a snapshot — a listener may add or remove listeners (including
    // itself) while reacting to the jump.
    for (final cb in List<ValueChanged<int>>.of(
      _jumpListeners,
      growable: false,
    )) {
      cb(messageId);
    }
    _emitScroll(ChatProgrammaticJump(messageId));
  }

  // --- Tail or target: typed listener with payload ---

  /// Plain `List` — same dedup-on-add rationale as [_jumpListeners].
  final _tailOrTargetListeners = <ValueChanged<TailOrTargetOutcome>>[];

  /// Subscribe to the outcome of tail-or-target [jumpTo]s (those with a
  /// `tailFitFraction`). Adding the same callback twice is a no-op.
  ///
  /// The callback runs synchronously inside the viewport's layout, once per
  /// decided jump. It MAY change the unread boundary listenable handed to
  /// [ChatScrollView.unreadBoundary]; the viewport lays that change out in
  /// the same pass. No other input changed from here reaches this layout.
  /// It MUST NOT call `setState`, mark widgets for rebuild, or navigate this
  /// controller ([jumpTo], [animateTo], [jumpToCenterBand], [scrollBy]): the
  /// viewport is mid-layout, and the rows it builds next share the widget
  /// tree's build scope. That covers listeners of the unread boundary
  /// listenable itself, which the change notifies synchronously. A
  /// navigation from a callback fails an assert in debug builds.
  void addTailOrTargetListener(ValueChanged<TailOrTargetOutcome> callback) {
    if (_tailOrTargetListeners.contains(callback)) return;
    _tailOrTargetListeners.add(callback);
  }

  /// Unsubscribe from tail-or-target outcomes. No-op when not present.
  void removeTailOrTargetListener(ValueChanged<TailOrTargetOutcome> callback) =>
      _tailOrTargetListeners.remove(callback);

  /// Viewport-only: delivers the decision of the armed tail-or-target jump.
  ///
  /// Called by `RenderChatScrollView` inside a layout callback, once per
  /// decided jump. Iterates a snapshot, so a listener may add or remove
  /// listeners (itself included) while reacting. Silent after [dispose].
  @internal
  void notifyTailOrTarget(TailOrTargetOutcome outcome) {
    if (_disposed) return;
    _dispatchingTailOrTarget = true;
    try {
      for (final cb in List<ValueChanged<TailOrTargetOutcome>>.of(
        _tailOrTargetListeners,
        growable: false,
      )) {
        cb(outcome);
      }
    } finally {
      _dispatchingTailOrTarget = false;
    }
  }

  /// Set while [notifyTailOrTarget] runs its listeners, so a navigation
  /// from inside the viewport's layout fails an assert instead of
  /// corrupting the pass.
  bool _dispatchingTailOrTarget = false;

  void _debugCheckNotDispatchingTailOrTarget(String method) {
    assert(
      !_dispatchingTailOrTarget,
      '$method called from a tail-or-target listener; listeners run inside '
      'the viewport layout and must not navigate',
    );
  }

  // --- Scroll-by: typed listener -------------------------------------------

  /// Plain `List` — same dedup-on-add rationale as [_jumpListeners].
  final _scrollByListeners = <ValueChanged<double>>[];

  /// Subscribe to programmatic `scrollBy` events. Callback receives the
  /// pixel delta. Used by the viewport to cancel any in-flight fling and
  /// relayout in response; consumers can listen too if they need to react.
  /// Adding the same callback twice is a no-op.
  void addScrollByListener(ValueChanged<double> callback) {
    if (_scrollByListeners.contains(callback)) return;
    _scrollByListeners.add(callback);
  }

  /// Unsubscribe from `scrollBy` events.
  void removeScrollByListener(ValueChanged<double> callback) =>
      _scrollByListeners.remove(callback);

  /// Shift the viewport's anchor by [pixels]. Positive values reveal older
  /// messages (content moves down); negative values reveal newer (content
  /// moves up). Use for keyboard scroll, mouse-wheel forwarding, or any
  /// programmatic "scroll by N pixels" affordance — the underlying physics
  /// (clamping, follow-tail, fetch poll) all settle on the next frame.
  ///
  /// **Sign convention is anchor-relative**, the opposite of a Flutter
  /// `ScrollController.position.pixels` delta. When porting code from a
  /// `ListView` scroll listener, negate the value.
  ///
  /// **`scrollBy(0.0)` is a silent no-op** — listeners are not notified
  /// and `ChatProgrammaticScroll` is not emitted. If a consumer counts
  /// notifications, account for the zero short-circuit. Non-finite values
  /// (NaN / ±∞) are also dropped silently — they would otherwise poison
  /// the anchor for the rest of the controller's lifetime.
  ///
  /// To navigate to a specific message id use [jumpTo] or [animateTo]
  /// instead. To know "what's N viewport-heights away" the consumer needs
  /// the current viewport size, which the controller does not own — fold
  /// that into [pixels] at the call site.
  ///
  /// **Highlight**: matches user drag. An armed wash fades; a pending
  /// request is hard-cleared so a later-built row cannot late-arm.
  ///
  /// **Placement**: matches user drag. A pending or held [jumpTo] /
  /// [animateTo] alignment or [jumpToCenterBand] placement is released, so
  /// the shift sticks and a later top inset change does not re-seat the
  /// former target.
  void scrollBy(double pixels) {
    if (_disposed) return;
    _debugCheckNotDispatchingTailOrTarget('scrollBy');
    if (pixels == 0.0 || !pixels.isFinite) return;
    releaseNavigationPlacement();
    _anchorPixelOffset += pixels;
    for (final cb in List<ValueChanged<double>>.of(
      _scrollByListeners,
      growable: false,
    )) {
      cb(pixels);
    }
    _emitScroll(ChatProgrammaticScroll(pixels));
  }

  /// Smoothly move the anchor onto [messageId].
  ///
  /// Completes when motion settles (or immediately if no viewport is bound).
  ///
  /// ## Close vs stitch
  ///
  /// - **Built target** → continuous close-path scroll to the aligned seat.
  /// - **Not built** → **stitch**: keep outgoing rows, teleport, dual-translate
  ///   into the destination band (continuity illusion — not a viewport fade).
  ///   Stitch waits on the load-gate until the destination is a real row.
  ///
  /// The resolved path is reported on the flight's [ChatAnimateEnd.path],
  /// emitted before the returned future completes: [AnimateToPath.close] or
  /// [AnimateToPath.stitch] as chosen above, [AnimateToPath.instant] for
  /// `duration ≤ 0`, and [AnimateToPath.none] when the flight is cancelled
  /// on the load-gate before choosing. With no viewport bound the call is a
  /// [jumpTo] and emits [ChatProgrammaticJump] only — no animate events, so
  /// no path.
  ///
  /// ## Duration / curve
  ///
  /// Both paths use travel-scaled timing
  /// (`((travel / viewportHeight) + 1) * 200` ms, clamped 300–1300) with
  /// [Curves.easeOutQuint]. [duration] / [curve] are compatibility hints:
  /// `duration ≤ 0` ⇒ instant [jumpTo] (no highlight while a viewport is
  /// bound); otherwise caller duration is ignored so a tall close hop and a
  /// matching stitch feel alike. Defaults (`300ms`, `easeOutQuint`) match
  /// that floor.
  ///
  /// ## Alignment
  ///
  /// [alignment] places the target in the scroll band (`0` = top, `1` = bottom).
  /// Rows taller than the band pin to the band top — **except** the known
  /// conversation newest (`reachedNewest` + `newestKnownId`): close-path then
  /// ends at **tail-pin** (message bottom on the bottom inset), matching
  /// [jumpTo] / follow-tail, so “go to end” does not animate to the message
  /// top and snap. Use [alignment] for mid-history (search, deep link).
  ///
  /// After the motion settles on a loaded row, the alignment is held with
  /// the same lifecycle as the [jumpTo] alignment hold.
  ///
  /// ## Highlight
  ///
  /// When [highlight] is true (default), a soft full-width **underlay** arms
  /// at flight start, holds through settle +
  /// [ChatScrollThemeData.highlightDuration] (default 1000ms), then fades
  /// ~300ms. Pass `false` for routine hops (e.g. return to tail). Use [jumpTo]
  /// when both motion and tint are unwanted, or [highlight] to wash a row
  /// without moving. `highlightDuration: Duration.zero` on the view disables
  /// tint globally. Drag and [scrollBy] cancel motion and fade an armed wash
  /// (pending is hard-cleared). Default [jumpTo] / overlay / controller swap /
  /// [dispose] hard-clear. If no viewport is bound, [highlight] is forwarded
  /// into the same [jumpTo] sugar (pre-mount open-at-message).
  ///
  /// ## Load policy
  ///
  /// Defaults to [AnimateToLoadPolicy.immediate]: enter the load-gate when
  /// unready, then close (built) vs stitch (not built). Use
  /// [AnimateToLoadPolicy.preferBuilt] for self-insert / follow-tail where a
  /// warming newest may win close-path. Neither policy stitches over unresolved
  /// placeholders.
  ///
  /// ## Busy / re-entry
  ///
  /// - Same id, alignment, and [pixelOffset] while busy →
  ///   [AnimateToDisposition.coalesced].
  /// - Different target while busy → [AnimateToDisposition.ignored] by default.
  ///   Pass [AnimateToBusyPolicy.replace] to cancel and start immediately
  ///   ([AnimateToDisposition.accepted]).
  /// - Already-aligned targets short-circuit (optional highlight only).
  ///
  /// Drag / clamp still call [ChatScrollAnimator.cancel] separately.
  ///
  /// **Hosts that keep a selection index** (e.g. search next/prev) with
  /// [AnimateToBusyPolicy.ignore]: only advance that index when disposition is
  /// not [AnimateToDisposition.ignored], or the UI races ahead of the viewport.
  ///
  /// **Absent targets:** same as [jumpTo] — completes without error but does
  /// not land on a deleted id.
  Future<AnimateToDisposition> animateTo(
    int messageId, {
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeOutQuint,
    double alignment = 0.0,
    bool highlight = true,
    AnimateToLoadPolicy loadPolicy = AnimateToLoadPolicy.immediate,
    AnimateToBusyPolicy busyPolicy = AnimateToBusyPolicy.ignore,
    double pixelOffset = 0.0,
  }) async {
    if (_disposed) return AnimateToDisposition.ignored;
    _debugCheckNotDispatchingTailOrTarget('animateTo');
    // Same absent-target contract as [jumpTo]: no visible row at [messageId]
    // when statusOf reports absent — animation may run but content does not
    // land on a deleted id. ADR 002 "Navigation to absent IDs".
    final animator = _animator;
    if (animator == null) {
      _setNavigationAlignment(messageId, alignment, pixelOffset: pixelOffset);
      jumpTo(
        messageId,
        alignment: alignment,
        highlight: highlight,
        pixelOffset: pixelOffset,
      );
      return AnimateToDisposition.accepted;
    }
    final align = alignment.clamp(0.0, 1.0);
    final busy = animator.isAnimating;
    final sameTarget =
        busy &&
        animator.animateTargetId == messageId &&
        (animator.animateAlignment - align).abs() < 0.001 &&
        (animator.animatePixelOffset - pixelOffset).abs() < 0.001;
    if (busy && !sameTarget) {
      if (busyPolicy != AnimateToBusyPolicy.replace) {
        // Do not update navigation alignment for ignored spam — that desyncs
        // the counter from the viewport and makes a later reverse tap look
        // like a forward jump.
        return AnimateToDisposition.ignored;
      }
      animator.cancel();
    }
    _setNavigationAlignment(messageId, alignment, pixelOffset: pixelOffset);
    if (highlight) {
      _requestedHighlightMessageId = messageId;
    } else {
      _requestedHighlightMessageId = null;
    }
    final coalesce = duration > Duration.zero && sameTarget;
    if (!coalesce) {
      _emitScroll(ChatAnimateStart(messageId, duration));
    }
    var path = AnimateToPath.none;
    try {
      path = await animator.animate(
        messageId,
        duration: duration,
        curve: curve,
        alignment: alignment,
        highlight: highlight,
        loadPolicy: loadPolicy,
        busyPolicy: busyPolicy,
        pixelOffset: pixelOffset,
      );
    } finally {
      if (!coalesce) {
        _emitScroll(ChatAnimateEnd(messageId, path: path));
      }
    }
    return coalesce
        ? AnimateToDisposition.coalesced
        : AnimateToDisposition.accepted;
  }

  // --- Scroll-animator binding (viewport-only) -----------------------------

  ChatScrollAnimator? _animator;

  /// Requested Message highlight id, or `null` when none. Survives detach /
  /// reattach of the same controller; [dispose] clears it.
  int? _requestedHighlightMessageId;

  /// Bound by `RenderChatScrollView` on attach. Detach passes `null` and
  /// does **not** clear [_requestedHighlightMessageId] — bind/reattach adopts
  /// the stored request into the new animator.
  @internal
  set animator(ChatScrollAnimator? value) {
    _animator = value;
    switch ((value, _requestedHighlightMessageId)) {
      case (final animator?, final id?):
        animator.requestHighlight(id);
      case _:
        break;
    }
  }

  /// Drop the stored Message highlight request when the target is confirmed
  /// absent or error.
  ///
  /// Without this, bind/reattach would replay [_requestedHighlightMessageId]
  /// into the animator and late-arm a wash after the row reappears. Pass
  /// [messageId] so a newer request is not cleared by a stale drop. Silent
  /// after [dispose].
  @internal
  void dropHighlightRequest([int? messageId]) {
    if (_disposed) return;
    switch (messageId) {
      case final id? when _requestedHighlightMessageId != id:
        return;
      case _:
        _requestedHighlightMessageId = null;
    }
  }

  // --- Scrollbar hold, suppression, and flash ------------------------------

  final Set<ChatScrollbarHold> _scrollbarHolds = <ChatScrollbarHold>{};
  final Set<ChatScrollbarSuppression> _scrollbarSuppressions =
      <ChatScrollbarSuppression>{};

  /// The bound viewport's reactions, or `null` while no viewport is bound.
  ({VoidCallback onChanged, VoidCallback onFlash})? _scrollbarBinding;

  /// Takes a **scrollbar hold**: while it is alive, the bound viewport's
  /// scrollbar stays shown — for a condition the viewport cannot see, such
  /// as host UI that reads the reader's position off the scrollbar.
  ///
  /// Under auto-hide visibility the first live hold reveals a hidden
  /// scrollbar (fading in) and cancels a pending hide; list motion, a grab,
  /// or strip hover ending while the hold lives hides nothing. Releasing
  /// the last hold starts the idle delay unless another holder (list
  /// motion, a grab, strip hover) still holds. Under always-shown
  /// visibility a hold changes nothing, and it carries over when the
  /// viewport's preset switches visibility mode. A live suppression beats
  /// every hold ([suppressScrollbar]).
  ///
  /// Holds count independently: each returned handle releases only itself,
  /// so independent host features never undo each other.
  ///
  /// Taken while no viewport is bound, the hold applies once one binds.
  /// Every live hold is released when the bound viewport leaves the tree
  /// or switches to another controller, and on [dispose]; the handle then
  /// reports [ChatScrollbarHandle.isReleased]. After [dispose] the returned
  /// handle is already released.
  ChatScrollbarHold holdScrollbar() =>
      _takeScrollbarHandle(ChatScrollbarHold._(this), _scrollbarHolds);

  /// Takes a **scrollbar suppression**: while it is alive, the bound
  /// viewport's scrollbar is hidden and inert — for host gestures or
  /// content over the trailing edge that the scrollbar must neither show
  /// over nor take presses from.
  ///
  /// While any suppression lives:
  ///
  /// - The scrollbar fades out from wherever it is, over the preset
  ///   visibility's fade-out (250 ms under always-shown visibility).
  /// - Every show trigger is ignored, not deferred: list motion, host
  ///   navigation, a mouse entering the viewport or hovering the strip,
  ///   holds, and [flashScrollbar]. A trigger that fired while suppressed
  ///   shows nothing once the suppression ends.
  /// - No press or hover is claimed: touch and mouse presses along the
  ///   trailing edge reach messages, and a mouse over the strip keeps the
  ///   cursor beneath. A grab in progress when the first suppression is
  ///   taken ends at once; its pointer then scrolls nothing until it lifts.
  ///
  /// Releasing the last suppression fades an always-shown scrollbar back
  /// in. An auto-hide scrollbar comes back only while something holds it —
  /// a live [holdScrollbar], list motion still running, or a mouse resting
  /// on the strip — and otherwise stays hidden until the next show trigger.
  ///
  /// Suppressions count independently, like holds, with the same
  /// attach, detach, controller-swap, and [dispose] rules.
  ChatScrollbarSuppression suppressScrollbar() => _takeScrollbarHandle(
    ChatScrollbarSuppression._(this),
    _scrollbarSuppressions,
  );

  /// A **scrollbar flash**: shows the bound viewport's auto-hide scrollbar,
  /// then hides it after the preset's idle delay — a one-shot hint at the
  /// reader's position with no handle to release.
  ///
  /// Hides nothing early: a scrollbar that something holds stays shown
  /// until that holder releases, and while a hide after host navigation is
  /// pending the flash waits the navigation delay, counted from the flash,
  /// instead of the idle delay. Ignored while any suppression lives, under
  /// always-shown visibility, and with no painted scrollbar. Dropped when
  /// no viewport is bound — unlike holds and suppressions, a flash is not
  /// replayed on a later attach. Silent after [dispose].
  void flashScrollbar() {
    if (_disposed) return;
    _scrollbarBinding?.onFlash();
  }

  // --- Scrollbar binding (viewport-only) -----------------------------------

  /// Whether any scrollbar hold is alive.
  @internal
  bool get isScrollbarHeld => _scrollbarHolds.isNotEmpty;

  /// Whether any scrollbar suppression is alive.
  @internal
  bool get isScrollbarSuppressed => _scrollbarSuppressions.isNotEmpty;

  /// Binds the attached viewport's scrollbar: [onChanged] runs whenever
  /// [isScrollbarHeld] or [isScrollbarSuppressed] flips, synchronously
  /// inside the host's [holdScrollbar], [suppressScrollbar], or
  /// [ChatScrollbarHandle.release] call; [onFlash] runs on
  /// [flashScrollbar].
  ///
  /// Called by `RenderChatScrollView` on attach and when it switches to
  /// this controller; the viewport reads both getters right after binding,
  /// so handles taken before it apply. At most one viewport is bound.
  @internal
  void bindScrollbar({
    required VoidCallback onChanged,
    required VoidCallback onFlash,
  }) {
    assert(
      _scrollbarBinding == null,
      'bindScrollbar: a viewport is already bound to this controller',
    );
    if (_disposed) return;
    _scrollbarBinding = (onChanged: onChanged, onFlash: onFlash);
  }

  /// Unbinds the viewport bound by [bindScrollbar] and releases every live
  /// hold and suppression without calling back: the viewport is leaving
  /// the tree or switching controllers, and a forgotten handle must not pin
  /// the next viewport's scrollbar. No-op while nothing is bound.
  @internal
  void unbindScrollbar() {
    if (_scrollbarBinding == null) return;
    _scrollbarBinding = null;
    _releaseScrollbarHandles();
  }

  T _takeScrollbarHandle<T extends ChatScrollbarHandle>(
    T handle,
    Set<T> live,
  ) {
    if (_disposed) {
      handle._controller = null;
      return handle;
    }
    live.add(handle);
    if (live.length == 1) _scrollbarBinding?.onChanged();
    return handle;
  }

  void _releaseScrollbarHandle(ChatScrollbarHandle handle) {
    final live = switch (handle) {
      ChatScrollbarHold() => _scrollbarHolds,
      ChatScrollbarSuppression() => _scrollbarSuppressions,
    };
    if (live.remove(handle) && live.isEmpty) _scrollbarBinding?.onChanged();
  }

  void _releaseScrollbarHandles() {
    for (final handle in <ChatScrollbarHandle>[
      ..._scrollbarHolds,
      ..._scrollbarSuppressions,
    ]) {
      handle._controller = null;
    }
    _scrollbarHolds.clear();
    _scrollbarSuppressions.clear();
  }

  // --- Visible range -------------------------------------------------------

  final _DeferredValueNotifier<ChatVisibleRange?> _visibleRange =
      _DeferredValueNotifier<ChatVisibleRange?>(null);

  /// Inclusive id range of currently-on-screen messages plus the active
  /// anchor id and boundary visibility fractions. `null` before the first
  /// layout has run (or when no message intersects the paint area). Push as
  /// the viewport scrolls / re-fans. Fractions use the same scrollable paint
  /// band as the id intersection test — see [ChatVisibleRange].
  ///
  /// **Listener safety**: pushes from `RenderChatScrollView` happen inside
  /// `performLayout`, where calling `setState` is illegal. The notifier
  /// auto-defers `notifyListeners()` to the end of the frame when the push
  /// lands during the `persistentCallbacks` phase — listeners that call
  /// `setState` (or `markNeedsLayout` on a parent) Just Work without having
  /// to wrap the callback in a `addPostFrameCallback` themselves.
  ValueListenable<ChatVisibleRange?> get visibleRange => _visibleRange;

  /// Viewport-only setter — `RenderChatScrollView` pushes the latest range
  /// after every layout / Tier-1 reposition. Safe to call from inside
  /// `performLayout`: the notification is deferred past the frame.
  @internal
  set visibleRange(ChatVisibleRange? value) {
    if (_disposed) return;
    _visibleRange.value = value;
  }

  // --- Center Band ---------------------------------------------------------

  final _DeferredValueNotifier<ChatCenterBand?> _centerBand =
      _DeferredValueNotifier<ChatCenterBand?>(null);

  /// Live Center Band: Message under the fixed 50% paint-band ray, plus
  /// pixels from that Message's top to the ray. `null` before the first
  /// layout or when no built Message intersects the ray.
  ///
  /// Pushed after layout and Tier-1 reposition — including silent Anchor
  /// origin renormalize frames that do not emit [ChatViewportScrolled].
  /// Geometric ray hit wins over any `visibleRange` id-midpoint heuristic.
  ValueListenable<ChatCenterBand?> get centerBand => _centerBand;

  /// Viewport-only setter — `RenderChatScrollView` pushes after every
  /// layout / Tier-1 reposition. Safe to call from inside `performLayout`.
  /// Post-[dispose] writes are silent no-ops.
  @internal
  set centerBand(ChatCenterBand? value) {
    if (_disposed) return;
    _centerBand.value = value;
  }

  // --- Tail tracking -------------------------------------------------------

  final _DeferredValueNotifier<bool> _isAtTail = _DeferredValueNotifier<bool>(
    false,
  );

  /// Whether the *newest* known message is currently in the paint area and
  /// the data source has reported [ChatDataSource.reachedNewest]. `false`
  /// when the conversation has no boundary yet, the viewport is in overlay
  /// mode, or the user has scrolled away from the bottom.
  ///
  /// **Initial value is `false`.** The first push happens at the end of
  /// the first `performLayout`, so listeners attached in `initState` will
  /// observe a `false → true` transition on the next frame when the
  /// viewport is at the tail. UI built off the initial synchronous value
  /// (e.g. a new-messages pill in `initState`) will briefly show as if
  /// the user were *not* at the tail until the first layout runs.
  ///
  /// **Listener safety**: same contract as [visibleRange] — pushes from
  /// inside `performLayout` are deferred past the frame so listeners may
  /// call `setState` without an explicit post-frame trampoline.
  ///
  /// Drives the canonical "follow tail" UI patterns: hide a
  /// new-messages-pill when the user is already pinned to the newest, show
  /// it when they've scrolled away. A separate "messages since I left the
  /// tail" counter is the consumer's responsibility — derive it from this
  /// flag plus `dataSource.newestKnownId` so the controller stays
  /// decoupled from the data source.
  ValueListenable<bool> get isAtTail => _isAtTail;

  /// Viewport-only setter — `RenderChatScrollView` pushes after every
  /// layout / Tier-1 reposition. Safe to call from inside `performLayout`.
  @internal
  set isAtTail(bool value) {
    if (_disposed) return;
    _isAtTail.value = value;
  }

  // --- Wired data-source boundaries (viewport passthrough) -----------------

  int? _oldestKnownId;
  int? _newestKnownId;

  /// Oldest message ID currently known to the viewport's wired data source.
  ///
  /// `null` before the first boundary seed. Read-only for consumers — updated
  /// by `RenderChatScrollView` whenever the source calls [ChatDataSource.seedBoundaries].
  int? get oldestKnownId => _oldestKnownId;

  /// Newest message ID currently known to the viewport's wired data source.
  int? get newestKnownId => _newestKnownId;

  /// Viewport-only — mirrors [ChatDataSource.oldestKnownId] / [newestKnownId].
  @internal
  set oldestKnownId(int? value) => _oldestKnownId = value;

  /// Viewport-only — mirrors [ChatDataSource.newestKnownId].
  @internal
  set newestKnownId(int? value) => _newestKnownId = value;

  // --- Scroll events -------------------------------------------------------

  /// Plain `List` — same dedup-on-add rationale as [_jumpListeners].
  final _scrollListeners = <ValueChanged<ChatScrollEvent>>[];

  /// Subscribe to typed scroll events ([ChatUserDragStart], [ChatFlingStart],
  /// [ChatProgrammaticJump], …). Adding the same callback twice is a no-op.
  void addScrollListener(ValueChanged<ChatScrollEvent> callback) {
    if (_scrollListeners.contains(callback)) return;
    _scrollListeners.add(callback);
  }

  /// Unsubscribes [callback] from [addScrollListener]. No-op when not present.
  void removeScrollListener(ValueChanged<ChatScrollEvent> callback) =>
      _scrollListeners.remove(callback);

  /// Viewport-only emitter. Iterates a snapshot — a listener removing itself
  /// or another listener during dispatch is safe.
  @internal
  void notifyScrollEvent(ChatScrollEvent event) => _emitScroll(event);

  void _emitScroll(ChatScrollEvent event) {
    if (_scrollListeners.isEmpty) return;
    for (final cb in List<ValueChanged<ChatScrollEvent>>.of(
      _scrollListeners,
      growable: false,
    )) {
      cb(event);
    }
  }

  // --- Anchor state (read-only for public, writable for viewport) ---

  /// The message ID used as layout origin.
  int get anchorMessageId => _anchorMessageId;
  int _anchorMessageId = 0;

  /// Pixel offset of the anchor message's top edge from the viewport top.
  double get anchorPixelOffset => _anchorPixelOffset;
  double _anchorPixelOffset = 0;

  /// The armed navigation placement from the latest [jumpTo] / [animateTo]
  /// (alignment) or [jumpToCenterBand] (Center Band), pending or held;
  /// `null` once released.
  ///
  /// One slot for both kinds: arming either replaces whatever was armed, and
  /// a release drops it whatever its kind or phase. See [NavigationPlacement]
  /// for the pending → held → released lifecycle.
  @internal
  NavigationPlacement? get navigationPlacement => _navigationPlacement;
  NavigationPlacement? _navigationPlacement;

  /// Whether an in-row placement — [jumpToCenterBand] or [jumpToFraction] —
  /// is armed and has not landed yet.
  ///
  /// When true, the viewport MUST NOT arm jump-to-newest tail pin — that
  /// would pull a point inside the conversation newest (a mid-bubble
  /// restore, a scrollbar grab inside a tall newest row) to the tail.
  /// `false` once the placement is held.
  @internal
  bool get hasPendingInRowPlacement => switch (_navigationPlacement) {
    final placement? => placement.isInRow && !placement.isHeld,
    null => false,
  };

  /// Moves the armed placement from pending to held.
  ///
  /// Called by the render object once the placement has been applied to a
  /// loaded target row. Silent no-op when nothing is armed.
  @internal
  void holdNavigationPlacement() {
    _navigationPlacement = _navigationPlacement?.hold();
  }

  /// Drops the armed placement, pending or held, of either kind.
  ///
  /// Called on user scroll (drag, wheel, scrollbar), by [scrollBy], and by
  /// the render object when the placement no longer applies: the held target
  /// stops being the anchor, the tail pin takes over the geometry (a
  /// known-newest alignment target, a tail follow), or the scroll band is
  /// empty. The anchor stays where it is.
  @internal
  void releaseNavigationPlacement() {
    _navigationPlacement = null;
  }

  /// Marks the armed tail-or-target decision made with a
  /// [TailOrTargetOutcome.target] outcome: the alignment placement stays
  /// armed, phase unchanged, without its `tailFitFraction`.
  ///
  /// Called by the render object in the layout that decides; a
  /// [TailOrTargetOutcome.tail] outcome calls [releaseNavigationPlacement]
  /// instead. No-op when no undecided alignment placement is armed.
  @internal
  void markTailFitDecided() {
    if (_navigationPlacement case final AlignmentPlacement placement) {
      _navigationPlacement = placement.withoutTailFit();
    }
  }

  /// After the viewport clamps a jump target, keeps the armed placement on
  /// [resolvedId], phase unchanged. No-op when nothing is armed.
  @internal
  void syncNavigationPlacementTarget(int resolvedId) {
    _navigationPlacement = _navigationPlacement?.retarget(resolvedId);
  }

  void _setNavigationAlignment(
    int messageId,
    double alignment, {
    double pixelOffset = 0,
  }) {
    _navigationPlacement = NavigationPlacement.alignment(
      messageId,
      alignment,
      pixelOffset: pixelOffset,
    );
  }

  void _setNavigationCenterBand(int messageId, double offsetFromMessageTop) {
    _navigationPlacement = NavigationPlacement.centerBand(
      messageId,
      offsetFromMessageTop,
    );
  }

  // --- Viewport-only: silent mutation without notifications ---

  /// Apply a scroll delta without notification.
  /// Called by the viewport from the Ticker callback.
  @internal
  void applyScrollDelta(double delta) {
    if (_disposed) return;
    _anchorPixelOffset += delta;
  }

  /// Silently reassign anchor (no notification).
  /// Called by the viewport during anchor renormalization inside performLayout.
  @internal
  void reassignAnchor(int messageId, double pixelOffset) {
    if (_disposed) return;
    _anchorMessageId = messageId;
    _anchorPixelOffset = pixelOffset;
  }

  /// Whether [dispose] has been called. Exposed so callers that share a
  /// controller across short-lived widgets can guard against double-dispose.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  /// When true, [SelectableMessage] must not fire tap or long-press selection
  /// actions — the current pointer down caught an in-flight fling or edge
  /// spring.
  @internal
  bool get flingCancelSuppressesLongPress => _flingCancelSuppressesLongPress;
  @internal
  set flingCancelSuppressesLongPress(bool value) {
    if (_disposed) return;
    _flingCancelSuppressesLongPress = value;
  }

  bool _flingCancelSuppressesLongPress = false;

  /// Drop all listeners. Call from the owning widget's `dispose` so a stray
  /// late notification cannot reach a torn-down listener. Idempotent — safe
  /// to call twice.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _jumpListeners.clear();
    _tailOrTargetListeners.clear();
    _scrollListeners.clear();
    _scrollByListeners.clear();
    // Drop the animator binding and Message highlight slot — a pending
    // `await animator.animate(...)` from a previous `animateTo` returning
    // after dispose must not mutate anchor state through a stale reference,
    // and a disposed navigator must not arm after teardown.
    _requestedHighlightMessageId = null;
    _animator?.clearHighlight();
    _animator = null;
    // A viewport still bound learns its handles are gone, so a disposed
    // controller cannot leave its scrollbar held or suppressed.
    final hadScrollbarHandles = isScrollbarHeld || isScrollbarSuppressed;
    final scrollbarBinding = _scrollbarBinding;
    _scrollbarBinding = null;
    _releaseScrollbarHandles();
    if (hadScrollbarHandles) scrollbarBinding?.onChanged();
    _visibleRange.dispose();
    _centerBand.dispose();
    _isAtTail.dispose();
  }
}

/// A live claim a host holds on the scrollbar of the viewport bound to a
/// [ChatScrollController]: a [ChatScrollbarHold] or a
/// [ChatScrollbarSuppression].
///
/// Each handle is one independent claim. Releasing it drops only that
/// claim; the scrollbar follows whatever claims are still alive, so
/// independent host features never undo each other. The controller keeps
/// no other record of who took a handle — a host that loses its handle
/// cannot release that claim until the controller releases it (viewport
/// detach, controller swap, or [ChatScrollController.dispose]).
sealed class ChatScrollbarHandle {
  ChatScrollbarHandle._(ChatScrollController controller)
    : _controller = controller;

  /// The controller holding this claim; `null` once released.
  ChatScrollController? _controller;

  /// Whether this claim no longer applies: [release] was called, or the
  /// controller released it — its viewport left the tree or switched to
  /// another controller, or the controller was disposed.
  bool get isReleased => _controller == null;

  /// Drops this claim. The first call takes effect synchronously; every
  /// later call, and a call after the controller released the claim, is a
  /// no-op.
  void release() {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    controller._releaseScrollbarHandle(this);
  }
}

/// A **scrollbar hold** taken by [ChatScrollController.holdScrollbar]:
/// keeps the scrollbar shown while alive, unless a suppression lives.
final class ChatScrollbarHold extends ChatScrollbarHandle {
  ChatScrollbarHold._(super.controller) : super._();
}

/// A **scrollbar suppression** taken by
/// [ChatScrollController.suppressScrollbar]: hides the scrollbar, ignores
/// its show triggers, and claims no presses while alive.
final class ChatScrollbarSuppression extends ChatScrollbarHandle {
  ChatScrollbarSuppression._(super.controller) : super._();
}

/// `ValueNotifier` subclass that defers `notifyListeners()` to the end of the
/// current frame when its setter fires during the `persistentCallbacks`
/// scheduler phase (layout / paint). Outside that phase it behaves exactly
/// like a plain `ValueNotifier`.
///
/// Used for [ChatScrollController.isAtTail],
/// [ChatScrollController.visibleRange], and
/// [ChatScrollController.centerBand]: `RenderChatScrollView` pushes these
/// from inside `performLayout`, where a synchronous `notifyListeners()` would
/// invite listeners to call `setState` mid-layout — illegal. Deferring the
/// notification lets listeners be naive consumers without each one having to
/// install a `addPostFrameCallback` trampoline.
///
/// Reads (`value` getter) are *not* deferred — they always return the latest
/// pushed value, including a write still pending notification. This keeps the
/// notifier consistent with the underlying viewport state: a render-side
/// equality short-circuit on `_controller.isAtTail.value == newValue` will
/// see the freshly-set value and skip the redundant deferred dispatch.
class _DeferredValueNotifier<T> extends ValueNotifier<T> {
  _DeferredValueNotifier(super.value);

  // Pending-write bookkeeping. `_pending` distinguishes "no pending write"
  // from "pending write whose new value is a typed null" — `_pendingValue`
  // alone cannot tell those apart when `T` itself is nullable
  // (e.g. `ChatVisibleRange?`).
  bool _pending = false;
  late T _pendingValue;
  bool _disposed = false;

  @override
  T get value => _pending ? _pendingValue : super.value;

  @override
  set value(T newValue) {
    if (_disposed) return;
    // Equality short-circuit against the *effective* value (pending or
    // committed). Otherwise a setter that lands inside performLayout
    // would schedule a post-frame even when the value hasn't moved.
    if (value == newValue) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      // First pending write of this frame: schedule the post-frame trampoline
      // that commits + notifies. Subsequent writes just overwrite the pending
      // value — only the final value of the frame is dispatched, matching how
      // a synchronous setter would behave without coalescing.
      final firstPending = !_pending;
      _pendingValue = newValue;
      _pending = true;
      if (firstPending) {
        SchedulerBinding.instance.addPostFrameCallback(_commitPending);
      }
    } else {
      _pending = false;
      super.value = newValue;
    }
  }

  void _commitPending(Duration _) {
    if (_disposed || !_pending) return;
    final committed = _pendingValue;
    _pending = false;
    // Drive notification through the base setter so [ValueNotifier]'s own
    // equality short-circuit and listener iteration apply unchanged.
    super.value = committed;
  }

  @override
  void dispose() {
    _disposed = true;
    _pending = false;
    super.dispose();
  }
}

import 'dart:async';

import 'package:chat_scroll_view/src/chat_scroll/animate_to_busy_policy.dart';
import 'package:chat_scroll_view/src/chat_scroll/animate_to_disposition.dart';
import 'package:chat_scroll_view/src/chat_scroll/animate_to_load_policy.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_events.dart';
import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

export 'package:chat_scroll_view/src/chat_scroll/animate_to_busy_policy.dart';
export 'package:chat_scroll_view/src/chat_scroll/animate_to_disposition.dart';
export 'package:chat_scroll_view/src/chat_scroll/animate_to_load_policy.dart';

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
  Future<void> animate(
    int targetId, {
    required Duration duration,
    required Curve curve,
    double alignment = 0.0,
    bool highlight = true,
    AnimateToLoadPolicy loadPolicy = AnimateToLoadPolicy.immediate,
    AnimateToBusyPolicy busyPolicy = AnimateToBusyPolicy.ignore,
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
/// ([visibleRange], [centerBand], [isAtTail]), and the typed event stream
/// (drag, fling, jump). Conversation boundaries (`oldestKnownId`,
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
  /// **Highlight**: default [highlight] is `false` — geometry only. Hosts
  /// MUST treat that as a hard-clear of any leftover Message highlight
  /// request (same as [jumpToCenterBand]). Pass `true` to write origin then
  /// request [highlight] so the jump hard-clear cannot drop the wash.
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
  void jumpTo(int messageId, {double alignment = 0.0, bool highlight = false}) {
    if (_disposed) return;
    // Absent targets: the anchor id is updated below, but absent slots render
    // at zero height — the viewport does not scroll to a visible row at
    // [messageId]. Fan-out and clamping behave as if the nearest non-absent
    // neighbor were the effective position. Check statusOf(messageId).isAbsent
    // before navigating if the user must see a specific message. ADR 002.
    _anchorMessageId = messageId;
    _anchorPixelOffset = 0.0;
    _setNavigationAlignment(messageId, alignment);
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
  /// Pending band alignment from a prior [jumpTo] / [animateTo] is cleared —
  /// Center Band placement and fractional alignment are mutually exclusive
  /// pending writers. Leftover Message highlight is hard-cleared — restore
  /// is not attention (ADR 009). There is no highlight flag on this method.
  ///
  /// **Absent-target behavior**: same ADR 002 caution as [jumpTo] — navigation
  /// completes without error; absent slots have zero height and do not produce
  /// a visible row at [messageId]. Post-[dispose] calls are silent no-ops.
  void jumpToCenterBand(int messageId, double offsetFromMessageTop) {
    if (_disposed) return;
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
  void scrollBy(double pixels) {
    if (_disposed) return;
    if (pixels == 0.0 || !pixels.isFinite) return;
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
  /// - Same id+alignment while busy → [AnimateToDisposition.coalesced].
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
  }) async {
    if (_disposed) return AnimateToDisposition.ignored;
    // Same absent-target contract as [jumpTo]: no visible row at [messageId]
    // when statusOf reports absent — animation may run but content does not
    // land on a deleted id. ADR 002 "Navigation to absent IDs".
    final animator = _animator;
    if (animator == null) {
      _setNavigationAlignment(messageId, alignment);
      jumpTo(messageId, alignment: alignment, highlight: highlight);
      return AnimateToDisposition.accepted;
    }
    final align = alignment.clamp(0.0, 1.0);
    final busy = animator.isAnimating;
    final sameTarget =
        busy &&
        animator.animateTargetId == messageId &&
        (animator.animateAlignment - align).abs() < 0.001;
    if (busy && !sameTarget) {
      if (busyPolicy != AnimateToBusyPolicy.replace) {
        // Do not update navigation alignment for ignored spam — that desyncs
        // the counter from the viewport and makes a later reverse tap look
        // like a forward jump.
        return AnimateToDisposition.ignored;
      }
      animator.cancel();
    }
    _setNavigationAlignment(messageId, alignment);
    if (highlight) {
      _requestedHighlightMessageId = messageId;
    } else {
      _requestedHighlightMessageId = null;
    }
    final coalesce = duration > Duration.zero && sameTarget;
    if (!coalesce) {
      _emitScroll(ChatAnimateStart(messageId, duration));
    }
    try {
      await animator.animate(
        messageId,
        duration: duration,
        curve: curve,
        alignment: alignment,
        highlight: highlight,
        loadPolicy: loadPolicy,
        busyPolicy: busyPolicy,
      );
    } finally {
      if (!coalesce) {
        _emitScroll(ChatAnimateEnd(messageId));
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

  /// Alignment requested by the latest [jumpTo] / [animateTo], in `0..1`.
  @internal
  double get navigationAlignment => _navigationAlignment;
  double _navigationAlignment = 0;

  /// Message id [navigationAlignment] applies to; cleared after settle.
  @internal
  int? get navigationAlignmentMessageId => _navigationAlignmentMessageId;
  int? _navigationAlignmentMessageId;

  /// Within-message offset pending from the latest [jumpToCenterBand].
  ///
  /// Cleared after the viewport places the center-band ray. Mutually exclusive
  /// with [navigationAlignmentMessageId] — only one pending writer is armed.
  @internal
  double? get navigationCenterBandOffset => _navigationCenterBandOffset;
  double? _navigationCenterBandOffset;

  /// Message id [navigationCenterBandOffset] applies to; cleared after settle.
  @internal
  int? get navigationCenterBandMessageId => _navigationCenterBandMessageId;
  int? _navigationCenterBandMessageId;

  /// Whether a [jumpToCenterBand] placement is still waiting on layout.
  ///
  /// When true, the viewport MUST NOT arm jump-to-newest tail pin — that
  /// would fight mid-bubble restore on the conversation newest.
  @internal
  bool get hasPendingNavigationCenterBand =>
      _navigationCenterBandMessageId != null;

  /// Drops the transient alignment target after a jump / animate settles.
  ///
  /// Called by the render object once the anchor has been applied — consumers
  /// should not call this directly.
  @internal
  void clearNavigationAlignment() {
    _navigationAlignment = 0.0;
    _navigationAlignmentMessageId = null;
  }

  /// Drops the transient Center Band apply target after settle.
  ///
  /// Called by the render object once the ray has been placed — consumers
  /// should not call this directly.
  @internal
  void clearNavigationCenterBand() {
    _navigationCenterBandOffset = null;
    _navigationCenterBandMessageId = null;
  }

  /// After the viewport clamps a jump target, keep alignment on the resolved id.
  @internal
  void syncNavigationAlignmentTarget(int resolvedId) {
    if (_navigationAlignmentMessageId != null) {
      _navigationAlignmentMessageId = resolvedId;
    }
  }

  /// After the viewport clamps a Center Band jump, keep apply on the resolved id.
  @internal
  void syncNavigationCenterBandTarget(int resolvedId) {
    if (_navigationCenterBandMessageId != null) {
      _navigationCenterBandMessageId = resolvedId;
    }
  }

  void _setNavigationAlignment(int messageId, double alignment) {
    clearNavigationCenterBand();
    _navigationAlignment = alignment.clamp(0.0, 1.0);
    _navigationAlignmentMessageId = messageId;
  }

  void _setNavigationCenterBand(int messageId, double offsetFromMessageTop) {
    clearNavigationAlignment();
    _navigationCenterBandOffset = offsetFromMessageTop;
    _navigationCenterBandMessageId = messageId;
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
  /// actions — the current pointer down cancelled an in-flight fling.
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
    _scrollListeners.clear();
    _scrollByListeners.clear();
    // Drop the animator binding and Message highlight slot — a pending
    // `await animator.animate(...)` from a previous `animateTo` returning
    // after dispose must not mutate anchor state through a stale reference,
    // and a disposed navigator must not arm after teardown.
    _requestedHighlightMessageId = null;
    _animator?.clearHighlight();
    _animator = null;
    _visibleRange.dispose();
    _centerBand.dispose();
    _isAtTail.dispose();
  }
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

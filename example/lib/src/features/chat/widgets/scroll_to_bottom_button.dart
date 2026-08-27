import 'dart:async';
import 'dart:ui' as ui;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/widgets/frozen_value.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/side_controls/chat_side_control_counter.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/side_controls/overshoot_curve.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

part 'scroll_to_bottom_fab.dart';
part 'scroll_to_bottom_unread.dart';

/// Scroll-to-bottom control: round FAB above the composer with
/// an optional unread badge.
///
/// Visibility:
/// * show after ~[scrollAwayThreshold] of scroll **toward** the tail (newer),
/// * hide when scrolling **away** from the tail (older) with no unread,
/// * force-show when unread exists off-tail,
/// * hide when the viewport is stably at the newest (tail).
///
/// Badge count uses progressive read against [lastSeenNewestId]. Tap animates
/// to newest and advances the baseline.
///
/// Composed from `isAtTail` / `visibleRange` / [ChatViewportScrolled] +
/// `newestKnownId`. The host owns [lastSeenNewestId] for persistence.
class ChatScrollToBottomButton extends StatefulWidget {
  /// Floating scroll-to-bottom FAB with optional unread badge.
  const ChatScrollToBottomButton({
    required this.controller,
    required this.dataSource,
    this.bottomInset,
    this.isSelfMessage,
    this.lastSeenNewestId,
    this.visibilityThreshold = 0.75,
    this.scrollAwayThreshold = 100,
    this.embedded = false,
    this.onChromeVisibleChanged,
    super.key,
  });

  /// Viewport controller — supplies tail state, visible range, and scroll events.
  final ChatScrollController controller;

  /// Conversation data — supplies `newestKnownId` for the unread baseline.
  final ChatDataSource dataSource;

  /// Reserved space at the bottom — typically composer height so the FAB clears
  /// the input row.
  final ValueListenable<double>? bottomInset;

  /// Same host predicate as [ChatScrollView.isSelfMessage]. When the newest
  /// known id is a self message, the unread baseline advances so own sends
  /// (including multi-device) never inflate the badge — Telegram zeroes the
  /// page-down counter on `hasFromMe`.
  final bool Function(IChatMessage message)? isSelfMessage;

  /// Highest message id treated as "read" for the unread badge. When null,
  /// seeds from [ChatDataSource.newestKnownId] at mount. Writes back on tail
  /// arrival and while scrolling through unread.
  final ValueNotifier<int?>? lastSeenNewestId;

  /// Minimum [ChatVisibleRange.lastRow.visibleFraction] before progressive
  /// scroll marks the last visible message as read. Defaults to `0.75`.
  final double visibilityThreshold;

  /// Cumulative user scroll toward newer (logical px) required to show the FAB
  /// when there is no unread.
  final double scrollAwayThreshold;

  /// When `true`, skips [Positioned] / inset padding so a
  /// [ChatSideControlsStack] can own placement and stack animation.
  final bool embedded;

  /// Reports chrome show-intent for an embedding [ChatSideControlsStack].
  ///
  /// Fires when the page-down visibility policy changes (not every frame).
  final ValueChanged<bool>? onChromeVisibleChanged;

  @override
  State<ChatScrollToBottomButton> createState() =>
      _ChatScrollToBottomButtonState();
}

class _ChatScrollToBottomButtonState extends State<ChatScrollToBottomButton> {
  /// Last value sent to [ChatScrollToBottomButton.onChromeVisibleChanged].
  bool? _reportedChromeVisible;

  /// Fallback when [ChatScrollToBottomButton.lastSeenNewestId] is not provided.
  int? _internalLastSeenNewestId;

  /// Progressive read-marking after the user scrolls — once enabled, every
  /// [ChatScrollController.visibleRange] update may advance the baseline.
  bool _scrollReadingEnabled = false;

  /// After a programmatic open (e.g. jump to last-read at 0.8 alignment),
  /// apply threshold-gated read progress from the first layout snapshot so
  /// messages already visible below the stored baseline reduce the pill count
  /// immediately — without waiting for the first user scroll.
  bool _pendingInitialViewportReadSync = true;

  /// Coalesces post-frame completion checks while the range is still moving.
  bool _initialSyncCompletionCheckScheduled = false;

  // --- Stable at-tail (raw `isAtTail` may flicker near the tail) ------------
  //
  // The viewport publishes `controller.isAtTail` after every layout. With
  // tall messages near the tail, geometry can satisfy the pin check for a
  // frame or two during settling even though the user has not caught up.
  // Acting on those transient `true` edges zeroed the unread count and advanced
  // the read baseline prematurely.
  //
  // `_stableAtTail` uses asymmetric hysteresis: raw `false` clears immediately
  // (pill can reappear quickly when leaving the tail); raw `true` must persist
  // for [_stableAtTailFrameThreshold] consecutive listener fires, or the user
  // must show tail-arrival intent (scroll toward newer / tap jump), before we
  // treat the conversation as fully read for dismiss and baseline writes.

  static const int _stableAtTailFrameThreshold = 2;

  int _consecutiveAtTailFrames = 0;

  bool _stableAtTail = false;

  /// Set before tap jump or when scroll-reading starts — latches stable at-tail
  /// on the next raw-`true` frame without waiting for the frame threshold.
  bool _tailArrivalIntent = false;

  /// Progressive read: last `visibleRange.lastId` observed while scrolling.
  int? _prevLastVisibleId;

  /// Progressive read: last `visibleRange.firstId` observed while scrolling.
  int? _prevFirstVisibleId;

  /// Progressive read: last `visibleRange.lastRow.visibleFraction` observed.
  double _prevLastVisibleFraction = 0;

  /// Message ids already advanced via visibility-threshold crossing — avoids
  /// repeat baseline writes while fraction stays above threshold.
  final _thresholdMarkedIds = <int>{};

  // --- Page-down visibility -----------------------------------------
  // Show after [scrollAwayThreshold] px away from tail, or when unread > 0
  // off-tail. Hide on raw at-tail, or immediately on tap (before animate).

  bool _canShow = false;

  /// Tap started animate-to-newest — keep chrome hidden until settle even if
  /// unread is still non-zero mid-flight.
  bool _pendingTapDismiss = false;

  /// Holds the last non-zero badge through the FAB hide fade after a tap.
  ///
  /// Baseline may zero [liveCount] mid-flight; without this freeze the badge
  /// would clear before opacity reaches 0. Cleared after
  /// [_ScrollToBottomFabState._visibilityDuration] or when chrome re-shows.
  bool _freezeBadgeForHide = false;

  /// Cancels [_freezeBadgeForHide] after the hide animation duration.
  Timer? _badgeFreezeTimer;

  double _totalDy = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.isAtTail.addListener(_onIsAtTailChanged);
    widget.controller.visibleRange.addListener(_onVisibleRangeChanged);
    widget.controller.addScrollListener(_onScrollEvent);
    widget.dataSource.addBoundaryListener(_onBoundaryChanged);
    // Seed the "last seen" baseline unconditionally — `isAtTail` starts as
    // `false` and is only pushed `true` after the first layout, so gating
    // the snapshot on it leaves the baseline `null` for the entire session
    // when the consumer mounts the pill at a non-tail position (e.g. a
    // permalink to an older message). With a `null` baseline `_unseenCount`
    // short-circuits to 0 and the pill silently stays hidden even when new
    // messages have arrived. Seeding here treats "everything that exists
    // now" as already-seen, which is the correct baseline regardless of
    // anchor position.
    //
    // If the source is currently empty (`newestKnownId == null`) the seed
    // stays null — the first non-null arrival on a *non-tail* anchor is
    // promoted in `_onBoundaryChanged` so the pill can surface those
    // messages instead of being silently suppressed forever.
    _seedBaseline();
  }

  void _seedBaseline() {
    final external = widget.lastSeenNewestId;
    if (external != null) {
      if (external.value == null) {
        final newest = widget.dataSource.newestKnownId;
        external.value = newest;
      }
      return;
    }
    _internalLastSeenNewestId = widget.dataSource.newestKnownId;
  }

  @override
  void didUpdateWidget(ChatScrollToBottomButton old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.isAtTail.removeListener(_onIsAtTailChanged);
      old.controller.visibleRange.removeListener(_onVisibleRangeChanged);
      old.controller.removeScrollListener(_onScrollEvent);
      widget.controller.isAtTail.addListener(_onIsAtTailChanged);
      widget.controller.visibleRange.addListener(_onVisibleRangeChanged);
      widget.controller.addScrollListener(_onScrollEvent);
      _scrollReadingEnabled = false;
      _pendingInitialViewportReadSync = true;
      _resetStableAtTail();
    }
    if (!identical(old.dataSource, widget.dataSource)) {
      old.dataSource.removeBoundaryListener(_onBoundaryChanged);
      widget.dataSource.addBoundaryListener(_onBoundaryChanged);
      _seedBaseline();
      _scrollReadingEnabled = false;
      _pendingInitialViewportReadSync = true;
      _resetStableAtTail();
    } else if (!identical(old.lastSeenNewestId, widget.lastSeenNewestId)) {
      _seedBaseline();
      _scrollReadingEnabled = false;
      _pendingInitialViewportReadSync = true;
      _resetStableAtTail();
    }
  }

  void _resetStableAtTail() {
    _consecutiveAtTailFrames = 0;
    _stableAtTail = false;
    _tailArrivalIntent = false;
    _pendingTapDismiss = false;
    _canShow = false;
    _totalDy = 0;
    _resetProgressiveReadTracking();
  }

  void _resetProgressiveReadTracking() {
    _prevLastVisibleId = null;
    _prevFirstVisibleId = null;
    _prevLastVisibleFraction = 0.0;
    _thresholdMarkedIds.clear();
  }

  @override
  void dispose() {
    _badgeFreezeTimer?.cancel();
    widget.controller.isAtTail.removeListener(_onIsAtTailChanged);
    widget.controller.visibleRange.removeListener(_onVisibleRangeChanged);
    widget.controller.removeScrollListener(_onScrollEvent);
    widget.dataSource.removeBoundaryListener(_onBoundaryChanged);
    super.dispose();
  }

  int? get _baseline =>
      widget.lastSeenNewestId?.value ?? _internalLastSeenNewestId;

  void _writeBaseline(int? value, {required String reason}) {
    final before = _baseline;
    if (before == value) return;
    final external = widget.lastSeenNewestId;
    if (external != null) {
      external.value = value;
    } else {
      _internalLastSeenNewestId = value;
    }
  }

  void _advanceBaselineTo(int id, {required String reason}) {
    final current = _baseline;
    if (current == null || id > current) {
      _writeBaseline(id, reason: reason);
      // Badge count is driven by lastSeenNewestId / internal baseline via
      // ListenableBuilder; only sync visibility (may hide when unread → 0
      // without scroll-show).
      _syncCanShow(scheduleRebuild: true);
    }
  }

  void _onScrollEvent(ChatScrollEvent event) {
    switch (event) {
      case ChatViewportScrolled(:final delta):
        _onViewportScrolled(delta);
      case ChatUserDragStart():
        // Drag cancels an in-flight animateTo — do not latch stable-at-tail on
        // the subsequent ChatAnimateEnd unless layout later reports tail.
        _scrollReadingEnabled = true;
        _pendingInitialViewportReadSync = false;
        if (_pendingTapDismiss) {
          _pendingTapDismiss = false;
          _tailArrivalIntent = false;
        } else {
          _tailArrivalIntent = true;
        }
        _syncReadProgressFromViewport();
        _syncCanShow(scheduleRebuild: true);
      case ChatUserDragEnd():
      case ChatFlingStart():
      case ChatProgrammaticScroll():
        _scrollReadingEnabled = true;
        _pendingInitialViewportReadSync = false;
        _tailArrivalIntent = true;
        _syncReadProgressFromViewport();
        _syncCanShow(scheduleRebuild: true);
      case ChatProgrammaticJump(:final targetId):
        if (targetId == widget.dataSource.newestKnownId) {
          _tailArrivalIntent = true;
          _pendingInitialViewportReadSync = false;
        } else {
          _pendingInitialViewportReadSync = true;
        }
      case ChatAnimateStart(:final targetId):
        if (targetId == widget.dataSource.newestKnownId) {
          _tailArrivalIntent = true;
          _pendingInitialViewportReadSync = false;
          // Hide page-down while animating to tail (self-send / FAB).
          _pendingTapDismiss = true;
          _canShow = false;
          _totalDy = 0;
          _syncCanShow(scheduleRebuild: true);
        }
      case ChatAnimateEnd(:final targetId):
        if (targetId == widget.dataSource.newestKnownId) {
          _pendingTapDismiss = false;
          _completeTailAnimateSettle(
            targetId,
            baselineReason: 'animate_to_newest_end',
          );
        }
      case ChatFlingEnd():
        break;
    }
  }

  /// Page-down visibility (host chat, newest at bottom):
  /// * scroll **toward** the tail / newer (~[scrollAwayThreshold]) → show;
  /// * scroll **away** from the tail / older → hide (no unread);
  /// * hide as soon as the viewport reports [ChatScrollController.isAtTail]
  ///   (do not wait on stable-at-tail hysteresis — that is only for baseline);
  /// * force-show when unread exists off-tail.
  void _onViewportScrolled(double delta) {
    if (delta == 0.0) return;

    _reconcileStaleStableAtTail();

    // Raw at-tail wins over scroll-show accumulation. Stable hysteresis can
    // miss a second `isAtTail` edge when the flag stays true, leaving the FAB
    // stuck visible — so dismiss from the controller bit directly.
    if (widget.controller.isAtTail.value) {
      _totalDy = 0;
      if (_canShow) {
        _canShow = false;
        _scheduleRebuild();
      }
      _syncStableAtTail(scheduleRebuild: false);
      return;
    }

    if (_stableAtTail) {
      _totalDy = 0;
      _syncCanShow(scheduleRebuild: true);
      return;
    }

    var showChanged = false;

    if (delta > 0) {
      // Revealing older — leaving the path to the end. Reset toward-tail
      // accumulation and dismiss a scroll-shown FAB (unread may re-show below).
      _totalDy = 0;
      if (_canShow && _unseenCount() == 0) {
        _canShow = false;
        showChanged = true;
      }
    } else {
      // Revealing newer — moving toward the tail. Show after threshold.
      if (!_canShow) {
        _totalDy += -delta;
        if (_totalDy > widget.scrollAwayThreshold) {
          _totalDy = 0;
          _canShow = true;
          showChanged = true;
        }
      }
    }

    final unread = _unseenCount();
    if (!_pendingTapDismiss && unread > 0 && !_canShow) {
      _canShow = true;
      showChanged = true;
    }
    if (showChanged) {
      _scheduleRebuild();
    }
  }

  /// Reconcile [_canShow] with at-tail and unread force-show.
  void _syncCanShow({required bool scheduleRebuild}) {
    final wasShow = _canShow;
    // Prefer raw isAtTail for chrome hide — see [_onViewportScrolled].
    if (widget.controller.isAtTail.value || _stableAtTail) {
      _canShow = false;
      _totalDy = 0;
      _pendingTapDismiss = false;
    } else if (!_pendingTapDismiss && _unseenCount() > 0) {
      _canShow = true;
    }
    if (scheduleRebuild && wasShow != _canShow) {
      _scheduleRebuild();
    }
  }

  void _onVisibleRangeChanged() {
    if (_pendingInitialViewportReadSync) {
      // Fetch/layout churn can publish transient ranges where [lastId] is
      // chunk-expanded or [lastRow.visibleFraction] comes from a not-yet-settled
      // layout. Apply read progress once when the range stabilizes.
      if (widget.controller.visibleRange.value != null) {
        _scheduleInitialViewportReadSyncCompletion();
      }
      return;
    }

    if (!_shouldSyncReadFromViewport()) return;
    _syncReadProgressFromViewport();
  }

  // ignore: prefer_expression_function_bodies
  bool _shouldSyncReadFromViewport() {
    // Read progress from the viewport is only applied during active user
    // scroll-reading. Initial open uses [_completeInitialViewportReadSync];
    // catch-up on layout/boundary churn without scroll over-marked unread rows
    // because [lastRow.visibleFraction] is measured only for the tail row.
    return _scrollReadingEnabled;
  }

  void _scheduleInitialViewportReadSyncCompletion() {
    if (_initialSyncCompletionCheckScheduled) return;
    _initialSyncCompletionCheckScheduled = true;
    final rangeAtSchedule = widget.controller.visibleRange.value;
    final idAtSchedule = rangeAtSchedule?.lastRow.id;
    final fractionAtSchedule = rangeAtSchedule?.lastRow.visibleFraction;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _initialSyncCompletionCheckScheduled = false;
      if (!mounted || !_pendingInitialViewportReadSync) return;
      final current = widget.controller.visibleRange.value;
      if (current == null) {
        _scheduleInitialViewportReadSyncCompletion();
        return;
      }
      final idStable = current.lastRow.id == idAtSchedule;
      final fractionStable =
          idAtSchedule == null ||
          ((current.lastRow.visibleFraction - (fractionAtSchedule ?? 0.0))
                  .abs() <
              1e-4);
      if (idStable && fractionStable) {
        _completeInitialViewportReadSync();
      } else {
        _scheduleInitialViewportReadSyncCompletion();
      }
    });
  }

  void _completeInitialViewportReadSync() {
    if (!_pendingInitialViewportReadSync) return;
    for (var pass = 0; pass < 64; pass++) {
      final passBefore = _baseline;
      _syncReadProgressFromViewport();
      if (_baseline == passBefore) break;
    }
    _pendingInitialViewportReadSync = false;
    _syncCanShow(scheduleRebuild: false);
    _scheduleRebuild();
  }

  void _syncStableAtTail({required bool scheduleRebuild}) {
    final rawAtTail = widget.controller.isAtTail.value;
    final wasStable = _stableAtTail;

    if (!rawAtTail) {
      _consecutiveAtTailFrames = 0;
      _stableAtTail = false;
    } else {
      _consecutiveAtTailFrames++;
      if (_tailArrivalIntent ||
          _consecutiveAtTailFrames >= _stableAtTailFrameThreshold) {
        _stableAtTail = true;
      } else {
        // `isAtTail` may stay true without another listenable edge — schedule
        // one more pass so hysteresis can latch for baseline writes.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!widget.controller.isAtTail.value) return;
          if (_stableAtTail) return;
          _syncStableAtTail(scheduleRebuild: true);
        });
      }
    }

    // Hide chrome on the raw at-tail edge; baseline still waits on stable.
    if (rawAtTail && _canShow) {
      _canShow = false;
      _totalDy = 0;
    }

    if (_stableAtTail && !wasStable) {
      // Pinning the newest row to the bottom inset does not mean the user has
      // read every unread body — near-tail opens can report stable at-tail
      // while tall messages remain mostly off-screen. Only snapshot newest as
      // seen after explicit tail arrival (tap, scroll, programmatic jump).
      if (_tailArrivalIntent || _scrollReadingEnabled) {
        _writeBaseline(
          widget.dataSource.newestKnownId,
          reason: 'stable_at_tail',
        );
        _scrollReadingEnabled = false;
        _pendingInitialViewportReadSync = false;
        _tailArrivalIntent = false;
      }
      _syncCanShow(scheduleRebuild: false);
    } else if (!_stableAtTail && wasStable) {
      _syncCanShow(scheduleRebuild: false);
    }

    if (scheduleRebuild) {
      _scheduleRebuild();
    }
  }

  void _onIsAtTailChanged() {
    _syncStableAtTail(scheduleRebuild: true);
  }

  void _onBoundaryChanged() {
    final newest = widget.dataSource.newestKnownId;
    // Self insert (any device): Telegram zeroes page-down unread on hasFromMe.
    // Do this before the stable-at-tail path so the badge never flashes.
    if (newest != null &&
        _isSelfId(newest) &&
        (_baseline == null || newest > _baseline!)) {
      _writeBaseline(newest, reason: 'boundary_self_newest');
      _syncCanShow(scheduleRebuild: false);
      _scheduleRebuild();
      return;
    }
    // When new messages arrive while the user is already pinned at the
    // tail, the follow-tail layout auto-scrolls them into view — they
    // are *visible*, not unseen. `isAtTail` stays `true` across that
    // transition so `_onIsAtTailChanged` never fires. Without this
    // snapshot the next time the user scrolls away the badge would count
    // those already-viewed messages as unread.
    if (_stableAtTail) {
      _writeBaseline(newest, reason: 'boundary_at_stable_tail');
    } else if (_baseline == null && newest != null) {
      _writeBaseline(newest - 1, reason: 'boundary_null_baseline');
    }
    _syncCanShow(scheduleRebuild: false);
    _scheduleRebuild();
  }

  bool _isSelfId(int id) {
    final pred = widget.isSelfMessage;
    if (pred == null) return false;
    final msg = widget.dataSource.getMessage(id);
    return msg != null && pred(msg);
  }

  int _unseenCount() {
    final newest = widget.dataSource.newestKnownId;
    if (newest == null) return 0;
    // Defensive: self newest must not count even if baseline write lagged.
    if (_isSelfId(newest)) return 0;
    final lastSeen = _baseline;
    if (lastSeen == null) return 0;
    final diff = newest - lastSeen;
    return diff > 0 ? diff : 0;
  }

  // The controller pushes `isAtTail` from inside `performLayout`, so the
  // listener fires during the `persistentCallbacks` phase where `setState`
  // is illegal. Defer the rebuild to the end of the frame in that case.
  void _scheduleRebuild() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _onTap() async {
    final newest = widget.dataSource.newestKnownId;
    if (newest == null) return;
    // Dismiss chrome immediately; FrozenValue keeps the last badge count for
    // the fade. Block unread force-show until we settle at the tail.
    _pendingTapDismiss = true;
    _canShow = false;
    _totalDy = 0;
    _tailArrivalIntent = true;
    _beginBadgeHideFreeze();
    _scheduleRebuild();
    await widget.controller.animateTo(
      newest,
      highlight: false,
      loadPolicy: AnimateToLoadPolicy.preferBuilt,
    );
    if (!mounted) return;
    _completeTailAnimateSettle(newest, baselineReason: 'scroll_to_bottom_tap');
    _pendingTapDismiss = false;
    _scrollReadingEnabled = false;
    _pendingInitialViewportReadSync = false;
    setState(() {});
  }

  /// Freezes the badge for one hide-animation duration after tap dismiss.
  void _beginBadgeHideFreeze() {
    _freezeBadgeForHide = true;
    _badgeFreezeTimer?.cancel();
    _badgeFreezeTimer = Timer(_ScrollToBottomFabState._visibilityDuration, () {
      _badgeFreezeTimer = null;
      if (!mounted || !_freezeBadgeForHide) return;
      setState(() => _freezeBadgeForHide = false);
    });
  }

  void _clearBadgeHideFreeze() {
    _badgeFreezeTimer?.cancel();
    _badgeFreezeTimer = null;
    _freezeBadgeForHide = false;
  }

  /// After animate-to-newest completes (or is cancelled), latch read state only
  /// when layout confirms the viewport is at the tail. A user drag that
  /// aborts mid-flight must not leave [_stableAtTail] latched or the FAB stays
  /// hidden until a manual return to tail.
  void _completeTailAnimateSettle(
    int targetId, {
    required String baselineReason,
  }) {
    void apply() {
      if (!mounted) return;
      _reconcileStaleStableAtTail();
      if (widget.controller.isAtTail.value) {
        _writeBaseline(targetId, reason: baselineReason);
        _stableAtTail = true;
        _consecutiveAtTailFrames = _stableAtTailFrameThreshold;
        _canShow = false;
        _totalDy = 0;
      }
      _tailArrivalIntent = false;
      _syncCanShow(scheduleRebuild: true);
    }

    if (widget.controller.isAtTail.value) {
      apply();
      return;
    }

    // Successful settle may publish isAtTail on the next layout pass.
    SchedulerBinding.instance.addPostFrameCallback((_) => apply());
  }

  /// Clears a latched stable-at-tail when the viewport is visibly off-tail
  /// (e.g. animate-to-newest was cancelled by a drag).
  void _reconcileStaleStableAtTail() {
    if (!_stableAtTail || widget.controller.isAtTail.value) return;
    _stableAtTail = false;
    _consecutiveAtTailFrames = 0;
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      widget.controller.isAtTail,
      widget.controller.visibleRange,
      ?widget.lastSeenNewestId,
    ];

    final inset = widget.bottomInset;
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final liveCount = _stableAtTail ? 0 : _unseenCount();
        final visible = !_pendingInitialViewportReadSync && _canShow;
        if (visible && _freezeBadgeForHide) {
          _clearBadgeHideFreeze();
        }
        _reportChromeVisible(visible);
        // Freeze for tap hide-fade ([_freezeBadgeForHide]) so baseline→0 mid
        // flight does not clear the badge before opacity hits 0. Also freeze
        // while hidden with live unread so held stays coherent; prefer
        // [liveCount] when non-zero so a 0→N arrival is not stuck on held 0.
        return FrozenValue<int>(
          frozen: _freezeBadgeForHide || (!visible && liveCount > 0),
          value: liveCount,
          builder: (context, frozenCount) {
            final count = liveCount > 0 ? liveCount : frozenCount;
            // When embedded, the stack owns opacity/scale/slide; keep keys in
            // sync with policy so tests still see show-intent.
            final fab = _ScrollToBottomFab(
              count: count,
              onTap: _onTap,
              visible: widget.embedded || visible,
              chromeVisible: visible,
              animateVisibility: !widget.embedded,
            );
            if (widget.embedded) return fab;
            return Positioned(
              right: 12,
              bottom: 0,
              child: inset == null
                  ? fab
                  : ValueListenableBuilder<double>(
                      valueListenable: inset,
                      child: fab,
                      builder: (ctx, value, child) => Padding(
                        padding: EdgeInsets.only(bottom: value),
                        child: child,
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  void _reportChromeVisible(bool visible) {
    final cb = widget.onChromeVisibleChanged;
    if (cb == null || _reportedChromeVisible == visible) return;
    _reportedChromeVisible = visible;
    // Avoid calling setState in the host during our build.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cb(visible);
    });
  }
}

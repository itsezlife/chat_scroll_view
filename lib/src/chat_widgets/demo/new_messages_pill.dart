import 'dart:async';

import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_events.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A floating "↓ N new" pill that surfaces when:
///
/// * the user has scrolled away from the bottom
///   (`controller.isAtTail.value == false`), and
/// * one or more newer messages exist above the [lastSeenNewestId] baseline.
///
/// Tap → animate back to the newest message. The baseline advances to the
/// current newest when the user reaches the tail, and advances progressively
/// toward newer ids as the user scrolls down through unread messages.
///
/// Composed from the controller's `isAtTail` / `visibleRange` listenables +
/// the data source's `newestKnownId`. The consumer owns [lastSeenNewestId]
/// (typically a [ValueNotifier]) and may update it when persisting read state.
class NewMessagesPill extends StatefulWidget {
  /// Floating unread counter that appears when the user scrolls off the tail.
  const NewMessagesPill({
    required this.controller,
    required this.dataSource,
    this.bottomInset,
    this.lastSeenNewestId,
    this.visibilityThreshold = 0.75,
    super.key,
  });

  /// Viewport controller — supplies tail state and visible range.
  final ChatScrollController controller;

  /// Conversation data — supplies `newestKnownId` for the unread baseline.
  final ChatDataSource dataSource;

  /// Reserved space at the bottom of the screen — typically the composer's
  /// measured height, so the pill clears the input row.
  final ValueListenable<double>? bottomInset;

  /// Highest message id treated as "read" for the unread counter. When null,
  /// the pill seeds from [ChatDataSource.newestKnownId] at mount. The pill
  /// writes back on tail arrival and boundary updates while at tail; it also
  /// advances the baseline while the user scrolls toward newer messages.
  final ValueNotifier<int?>? lastSeenNewestId;

  /// Minimum [ChatVisibleRange.lastRow.visibleFraction] before progressive scroll
  /// marks the last visible message as read (relative to message height).
  /// Defaults to `0.75` (half the message visible in the scrollable band).
  final double visibilityThreshold;

  @override
  State<NewMessagesPill> createState() => _NewMessagesPillState();
}

class _NewMessagesPillState extends State<NewMessagesPill> {
  /// Fallback when [NewMessagesPill.lastSeenNewestId] is not provided.
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

  /// Last non-zero count rendered — kept during fade-out so the label never
  /// flashes "0 new messages" when the tail is reached or the pill dismisses.
  int _lastNonZeroCount = 0;

  /// Non-null while a tap-driven jump is dismissing — freezes the label until
  /// the opacity fade completes.
  int? _frozenDismissCount;

  Timer? _clearFrozenCountTimer;

  static const Duration _fadeDuration = Duration(milliseconds: 180);

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
  void didUpdateWidget(NewMessagesPill old) {
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
    _clearFrozenCountTimer?.cancel();
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
    }
  }

  void _onScrollEvent(ChatScrollEvent event) {
    switch (event) {
      case ChatUserDragStart():
      case ChatUserDragEnd():
      case ChatFlingStart():
      case ChatProgrammaticScroll():
        _scrollReadingEnabled = true;
        _pendingInitialViewportReadSync = false;
        _tailArrivalIntent = true;
        _syncReadProgressFromViewport();
      case ChatProgrammaticJump(:final targetId):
        if (targetId == widget.dataSource.newestKnownId) {
          _tailArrivalIntent = true;
          _pendingInitialViewportReadSync = false;
        } else {
          _pendingInitialViewportReadSync = true;
        }
      case ChatFlingEnd():
      case ChatAnimateStart():
      case ChatAnimateEnd():
        break;
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
    if (_unseenCount() == 0) {
      _lastNonZeroCount = 0;
      _frozenDismissCount = null;
    }
    _scheduleRebuild();
  }

  /// Id whose [ChatVisibleRange.lastRow.visibleFraction] should drive read progress
  /// — never chunk-expanded [ChatVisibleRange.lastId] alone.
  int? _readMarkId(ChatVisibleRange range) => range.lastRow.id;

  /// On open, short rows may meet [visibilityThreshold]; taller rows must be
  /// fully visible (fraction ≈ 1). Band-fill rows never count on open.
  bool _rowCountsAsReadOnOpen({
    required double fraction,
    required bool fillsBand,
    required double messageHeight,
    required double paintBandHeight,
  }) {
    if (fillsBand) return false;
    final threshold = widget.visibilityThreshold.clamp(0.0, 1.0);
    const fullyVisibleEpsilon = 1e-4;
    const shortRowBandFraction = 0.25;
    final shortRowMaxHeight = paintBandHeight * shortRowBandFraction;
    if (messageHeight > shortRowMaxHeight) {
      return fraction >= 1.0 - fullyVisibleEpsilon;
    }
    return fraction >= threshold;
  }

  /// Whether the first unread row `(baseline + 1)` counts as read on open.
  bool _firstUnreadCountsAsReadOnOpen(ChatVisibleRange range, int baseline) {
    if (range.firstRow.id == baseline + 1) {
      return _rowCountsAsReadOnOpen(
        fraction: range.firstRow.visibleFraction,
        fillsBand: visibleRowFillsBand(
          range.firstRow.height,
          range.paintBandHeight,
        ),
        messageHeight: range.firstRow.height,
        paintBandHeight: range.paintBandHeight,
      );
    }
    if (range.anchorNextRow?.id == baseline + 1) {
      final anchorNext = range.anchorNextRow!;
      return _rowCountsAsReadOnOpen(
        fraction: anchorNext.visibleFraction,
        fillsBand: visibleRowFillsBand(
          anchorNext.height,
          range.paintBandHeight,
        ),
        messageHeight: anchorNext.height,
        paintBandHeight: range.paintBandHeight,
      );
    }
    return false;
  }

  /// Whether [range.lastRow] counts as read on open.
  bool _tailCountsAsReadOnOpen(ChatVisibleRange range) {
    if (_shortTailOnPaintEdgeMeetsOpenRead(range, lenient: true)) {
      return true;
    }
    return _rowCountsAsReadOnOpen(
      fraction: range.lastRow.visibleFraction,
      fillsBand: visibleRowFillsBand(
        range.lastRow.height,
        range.paintBandHeight,
      ),
      messageHeight: range.lastRow.height,
      paintBandHeight: range.paintBandHeight,
    );
  }

  /// Per-id open read when [id] is one of the rows the render layer measures.
  bool _openIdCountsAsRead(ChatVisibleRange range, int id) {
    if (range.firstRow.id == id) {
      return _rowCountsAsReadOnOpen(
        fraction: range.firstRow.visibleFraction,
        fillsBand: visibleRowFillsBand(
          range.firstRow.height,
          range.paintBandHeight,
        ),
        messageHeight: range.firstRow.height,
        paintBandHeight: range.paintBandHeight,
      );
    }
    if (range.lastRow.id == id) {
      return _tailCountsAsReadOnOpen(range);
    }
    final anchorNext = range.anchorNextRow;
    if (anchorNext?.id == id) {
      return _rowCountsAsReadOnOpen(
        fraction: anchorNext!.visibleFraction,
        fillsBand: visibleRowFillsBand(
          anchorNext.height,
          range.paintBandHeight,
        ),
        messageHeight: anchorNext.height,
        paintBandHeight: range.paintBandHeight,
      );
    }
    return false;
  }

  /// Open batch-prefix marking: only when no tall band-fill row is visible and
  /// both ends of the span meet per-row rules (first unread + tail fraction).
  bool _canBatchMarkUnreadOnOpen(
    ChatVisibleRange range,
    int baseline,
    int readId,
  ) {
    if (readId <= baseline + 1) return false;
    if (range.anyRowFillsBand) return false;

    final span = readId - baseline;
    if (span <= 2) {
      if (!_firstUnreadCountsAsReadOnOpen(range, baseline)) {
        return false;
      }
      return _tailCountsAsReadOnOpen(range);
    }

    if (_shortTailOnPaintEdgeMeetsOpenRead(range, lenient: true)) {
      return true;
    }
    return _rowCountsAsReadOnOpen(
      fraction: range.lastRow.visibleFraction,
      fillsBand: visibleRowFillsBand(
        range.lastRow.height,
        range.paintBandHeight,
      ),
      messageHeight: range.lastRow.height,
      paintBandHeight: range.paintBandHeight,
    );
  }

  /// Tail row sitting on the paint-band bottom (above the composer) often
  /// reports a fraction below [visibilityThreshold] even for short bubbles.
  bool _shortTailOnPaintEdgeMeetsOpenRead(
    ChatVisibleRange range, {
    bool lenient = false,
  }) {
    if (visibleRowFillsBand(range.lastRow.height, range.paintBandHeight) ||
        range.paintBandHeight <= 0) {
      return false;
    }
    const shortRowBandFraction = 0.25;
    if (range.lastRow.height <= 0 ||
        range.lastRow.height >
            range.paintBandHeight * shortRowBandFraction) {
      return false;
    }
    if (lenient) {
      // Many short rows stacked above the composer: only the tail clips.
      return range.lastRow.visibleFraction >= 0.2;
    }
    final threshold = widget.visibilityThreshold.clamp(0.0, 1.0);
    final edgeThreshold = (threshold * 0.6).clamp(0.4, threshold);
    return range.lastRow.visibleFraction >= edgeThreshold;
  }

  /// On open, defer prefix read-marking when most of the unread backlog is still
  /// below the visible tail — e.g. 2 of 20 on screen (ratio 0.9). Near-tail
  /// opens where most unread is visible (ratio < [_offScreenUnreadDeferRatio])
  /// still mark what is on screen.
  static const double _offScreenUnreadDeferRatio = 0.75;

  bool _manyUnreadRemainOffScreenOnOpen(
    ChatVisibleRange range,
    int baseline,
    int readId,
  ) {
    final newest = widget.dataSource.newestKnownId;
    if (newest == null) return false;
    final totalUnread = newest - baseline;
    if (totalUnread <= 0) return false;

    final tailId = range.lastRow.id;
    final offScreenUnread = newest - tailId;
    if (offScreenUnread <= 0) return false;

    final offScreenRatio = offScreenUnread / totalUnread;
    return offScreenRatio >= _offScreenUnreadDeferRatio;
  }

  /// Highest id that may be marked read from [range] on the current pass.
  ///
  /// During scroll-reading the full [lastRow.id] may be used (tall bodies
  /// are also covered by [_syncReadProgressFromFirstIdLeaving]). On open,
  /// multi-id advance is gated by [_canBatchMarkUnreadOnOpen].
  int? _resolveReadMarkId(ChatVisibleRange range) {
    final readId = _readMarkId(range);
    if (readId == null) return null;

    final baseline = _baseline;
    if (baseline == null) return readId;
    if (readId <= baseline) return null;

    if (!_scrollReadingEnabled) {
      if (_manyUnreadRemainOffScreenOnOpen(range, baseline, readId)) {
        return null;
      }
      if (readId > baseline + 1 &&
          _canBatchMarkUnreadOnOpen(range, baseline, readId)) {
        return readId;
      }
      final nextId = baseline + 1;
      if (nextId > readId) return null;
      if (!_openIdCountsAsRead(range, nextId)) return null;
      return nextId;
    }
    return readId;
  }

  /// Whether [range.lastId] is visible enough to advance the read baseline.
  ///
  /// Band-fill fractions only measure viewport occupancy, not share-of-message
  /// read. They are ignored on open; during scroll they may mark [lastId] when
  /// a new tall row appears at the bottom, while [_syncReadProgressFromFirstIdLeaving]
  /// marks rows that scroll off the top.
  bool _lastVisibleMeetsReadThreshold(ChatVisibleRange range) {
    if (!_scrollReadingEnabled) {
      final baseline = _baseline;
      final readId = _readMarkId(range);
      if (baseline != null && readId != null && readId > baseline) {
        if (!_manyUnreadRemainOffScreenOnOpen(range, baseline, readId) &&
            readId > baseline + 1 &&
            _canBatchMarkUnreadOnOpen(range, baseline, readId)) {
          return true;
        }
        return _openIdCountsAsRead(range, baseline + 1);
      }
      return false;
    }

    final threshold = widget.visibilityThreshold.clamp(0.0, 1.0);
    if (range.lastRow.visibleFraction < threshold) return false;
    return true;
  }

  /// While the user scrolls toward newer messages, each time the oldest
  /// visible id rises the message that just left the top edge has been seen —
  /// including tall rows where [ChatVisibleRange.lastId] stays fixed for many
  /// frames while the user moves through the body.
  void _syncReadProgressFromFirstIdLeaving(ChatVisibleRange range) {
    if (!_scrollReadingEnabled) return;
    final baseline = _baseline;
    if (baseline == null) return;

    final firstId = range.firstId;
    final prevFirst = _prevFirstVisibleId;
    _prevFirstVisibleId = firstId;
    if (prevFirst == null || firstId <= prevFirst) return;

    final markThrough = firstId - 1;
    if (markThrough > baseline) {
      _advanceBaselineTo(markThrough, reason: 'first_id_leaving');
      _thresholdMarkedIds.add(markThrough);
    }
  }

  /// During [_pendingInitialViewportReadSync] or active user scroll-reading the
  /// at-tail gate is bypassed so near-tail opens and tall unread messages
  /// still advance the baseline progressively.
  void _syncReadProgressFromViewport() {
    final bypassAtTailGate =
        _pendingInitialViewportReadSync || _scrollReadingEnabled;
    if (!bypassAtTailGate && widget.controller.isAtTail.value) return;
    final range = widget.controller.visibleRange.value;
    if (range == null) return;

    if (_scrollReadingEnabled) {
      _syncReadProgressFromFirstIdLeaving(range);
    }

    final readId = _resolveReadMarkId(range);
    if (readId == null) {
      return;
    }

    final fraction = range.lastRow.visibleFraction;
    final threshold = widget.visibilityThreshold.clamp(0.0, 1.0);

    if (!_lastVisibleMeetsReadThreshold(range)) {
      // A rejected open-layout band-fill snapshot must not consume the rising
      // edge — otherwise the first user scroll never advances the baseline.
      final rejectedOpenBandFill =
          !_scrollReadingEnabled &&
          visibleRowFillsBand(range.lastRow.height, range.paintBandHeight);
      if (!rejectedOpenBandFill) {
        _prevLastVisibleId = readId;
        _prevLastVisibleFraction = fraction;
      }
      return;
    }

    final risingEdge =
        readId != _prevLastVisibleId ||
        (_prevLastVisibleFraction < threshold && fraction >= threshold);

    if (risingEdge && !_thresholdMarkedIds.contains(readId)) {
      _advanceBaselineTo(readId, reason: 'viewport_threshold');
      _thresholdMarkedIds.add(readId);
    }

    _prevLastVisibleId = readId;
    _prevLastVisibleFraction = fraction;
  }

  void _scheduleClearFrozenCount() {
    if (_frozenDismissCount == null && _lastNonZeroCount <= 0) return;
    _clearFrozenCountTimer?.cancel();
    _clearFrozenCountTimer = Timer(_fadeDuration, () {
      if (!mounted) return;
      if (!_stableAtTail) return;
      setState(() {
        _frozenDismissCount = null;
        _lastNonZeroCount = 0;
      });
    });
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
      }
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
        _scheduleClearFrozenCount();
      }
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
    // When new messages arrive while the user is already pinned at the
    // tail, the follow-tail layout auto-scrolls them into view — they
    // are *visible*, not unseen. `isAtTail` stays `true` across that
    // transition so `_onIsAtTailChanged` never fires. Without this
    // snapshot the next time the user scrolls away the pill would count
    // those already-viewed messages as "new".
    if (_stableAtTail) {
      _writeBaseline(newest, reason: 'boundary_at_stable_tail');
    } else if (_baseline == null && newest != null) {
      _writeBaseline(newest - 1, reason: 'boundary_null_baseline');
    }
    _scheduleRebuild();
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

  int _unseenCount() {
    final newest = widget.dataSource.newestKnownId;
    if (newest == null) return 0;
    final lastSeen = _baseline;
    if (lastSeen == null) return 0;
    final diff = newest - lastSeen;
    return diff > 0 ? diff : 0;
  }

  Future<void> _onTap() async {
    final newest = widget.dataSource.newestKnownId;
    if (newest == null) return;
    final count = _unseenCount();
    if (count > 0) {
      setState(() => _frozenDismissCount = count);
    }
    _tailArrivalIntent = true;
    await widget.controller.animateTo(newest, highlight: false);
    if (!mounted) return;
    _writeBaseline(newest, reason: 'pill_tap');
    _stableAtTail = true;
    _consecutiveAtTailFrames = _stableAtTailFrameThreshold;
    _tailArrivalIntent = false;
    _scrollReadingEnabled = false;
    _pendingInitialViewportReadSync = false;
    _scheduleClearFrozenCount();
    setState(() {});
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
        final atTail = _stableAtTail;
        final liveCount = atTail ? 0 : _unseenCount();
        if (liveCount > 0) {
          _lastNonZeroCount = liveCount;
        }
        final displayCount = liveCount > 0
            ? liveCount
            : (_frozenDismissCount ?? _lastNonZeroCount);
        final visible =
            !_pendingInitialViewportReadSync && !atTail && liveCount > 0;
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: inset == null
              ? _Pill(count: displayCount, onTap: _onTap, visible: visible)
              : ValueListenableBuilder<double>(
                  valueListenable: inset,
                  builder: (ctx, value, _) => Padding(
                    padding: EdgeInsets.only(bottom: value + 12),
                    child: _Pill(
                      count: displayCount,
                      onTap: _onTap,
                      visible: visible,
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.count,
    required this.onTap,
    required this.visible,
  });

  final int count;
  final VoidCallback onTap;
  final bool visible;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: _NewMessagesPillState._fadeDuration,
      curve: Curves.easeOutCubic,
      child: Center(
        child: Material(
          color: const Color(0xFF0B81F6),
          elevation: 4,
          shape: const StadiumBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 18, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.arrow_downward_rounded,
                    size: 18,
                    color: Color(0xFFFFFFFF),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    count == 1 ? '1 new message' : '$count new messages',
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

part of 'scroll_to_bottom_button.dart';

/// Progressive unread / last-seen baseline helpers for the scroll-to-bottom FAB.
extension on _ChatScrollToBottomButtonState {
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
        range.lastRow.height > range.paintBandHeight * shortRowBandFraction) {
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
}

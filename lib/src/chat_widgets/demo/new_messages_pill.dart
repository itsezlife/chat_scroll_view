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
  const NewMessagesPill({
    required this.controller,
    required this.dataSource,
    this.bottomInset,
    this.lastSeenNewestId,
    super.key,
  });

  final ChatScrollController controller;
  final ChatDataSource dataSource;

  /// Reserved space at the bottom of the screen — typically the composer's
  /// measured height, so the pill clears the input row.
  final ValueListenable<double>? bottomInset;

  /// Highest message id treated as "read" for the unread counter. When null,
  /// the pill seeds from [ChatDataSource.newestKnownId] at mount. The pill
  /// writes back on tail arrival and boundary updates while at tail; it also
  /// advances the baseline while the user scrolls toward newer messages.
  final ValueNotifier<int?>? lastSeenNewestId;

  @override
  State<NewMessagesPill> createState() => _NewMessagesPillState();
}

class _NewMessagesPillState extends State<NewMessagesPill> {
  /// Fallback when [NewMessagesPill.lastSeenNewestId] is not provided.
  int? _internalLastSeenNewestId;

  /// Progressive read-marking only after the user scrolls — keeps the full
  /// open count until the first drag / fling / scrollBy.
  bool _scrollReadingEnabled = false;

  /// Last non-zero count rendered — kept during fade-out so the label never
  /// flashes "0 new messages" when the tail is reached or the pill dismisses.
  int _lastNonZeroCount = 0;

  /// Non-null while a tap-driven jump is dismissing — freezes the label until
  /// the opacity fade completes.
  int? _frozenDismissCount;

  Timer? _clearFrozenCountTimer;

  static const Duration _fadeDuration = Duration(milliseconds: 180);

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
        external.value = widget.dataSource.newestKnownId;
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
    }
    if (!identical(old.dataSource, widget.dataSource)) {
      old.dataSource.removeBoundaryListener(_onBoundaryChanged);
      widget.dataSource.addBoundaryListener(_onBoundaryChanged);
      _seedBaseline();
      _scrollReadingEnabled = false;
    } else if (!identical(old.lastSeenNewestId, widget.lastSeenNewestId)) {
      _seedBaseline();
      _scrollReadingEnabled = false;
    }
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

  void _writeBaseline(int? value) {
    final external = widget.lastSeenNewestId;
    if (external != null) {
      external.value = value;
    } else {
      _internalLastSeenNewestId = value;
    }
  }

  void _advanceBaselineTo(int id) {
    final current = _baseline;
    if (current == null || id > current) {
      _writeBaseline(id);
    }
  }

  void _onScrollEvent(ChatScrollEvent event) {
    switch (event) {
      case ChatUserDragStart():
      case ChatUserDragEnd():
      case ChatFlingStart():
      case ChatProgrammaticScroll():
        _scrollReadingEnabled = true;
        _syncReadProgressFromViewport();
      case ChatFlingEnd():
      case ChatProgrammaticJump():
      case ChatAnimateStart():
      case ChatAnimateEnd():
        break;
    }
  }

  void _onVisibleRangeChanged() {
    if (_scrollReadingEnabled) {
      _syncReadProgressFromViewport();
    }
  }

  /// While off-tail, treat the newest visible message as read-through.
  void _syncReadProgressFromViewport() {
    if (widget.controller.isAtTail.value) return;
    final range = widget.controller.visibleRange.value;
    if (range == null) return;
    _advanceBaselineTo(range.lastId);
  }

  void _scheduleClearFrozenCount() {
    if (_frozenDismissCount == null && _lastNonZeroCount <= 0) return;
    _clearFrozenCountTimer?.cancel();
    _clearFrozenCountTimer = Timer(_fadeDuration, () {
      if (!mounted) return;
      if (!widget.controller.isAtTail.value) return;
      setState(() {
        _frozenDismissCount = null;
        _lastNonZeroCount = 0;
      });
    });
  }

  void _onIsAtTailChanged() {
    if (widget.controller.isAtTail.value) {
      // User is back at the tail — snapshot the current newest as "seen"
      // so subsequent arrivals start the counter from zero.
      _writeBaseline(widget.dataSource.newestKnownId);
      _scrollReadingEnabled = false;
      _scheduleClearFrozenCount();
    }
    _scheduleRebuild();
  }

  void _onBoundaryChanged() {
    final newest = widget.dataSource.newestKnownId;
    // When new messages arrive while the user is already pinned at the
    // tail, the follow-tail layout auto-scrolls them into view — they
    // are *visible*, not unseen. `isAtTail` stays `true` across that
    // transition so `_onIsAtTailChanged` never fires. Without this
    // snapshot the next time the user scrolls away the pill would count
    // those already-viewed messages as "new".
    if (widget.controller.isAtTail.value) {
      _writeBaseline(newest);
    } else if (_baseline == null && newest != null) {
      _writeBaseline(newest - 1);
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
    await widget.controller.animateTo(newest);
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
        final atTail = widget.controller.isAtTail.value;
        final liveCount = atTail ? 0 : _unseenCount();
        if (liveCount > 0) {
          _lastNonZeroCount = liveCount;
        }
        final displayCount = liveCount > 0
            ? liveCount
            : (_frozenDismissCount ?? _lastNonZeroCount);
        final visible = !atTail && liveCount > 0;
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: inset == null
              ? _Pill(
                  count: displayCount,
                  onTap: _onTap,
                  visible: visible,
                )
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
  Widget build(BuildContext context) {
    return IgnorePointer(
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
}

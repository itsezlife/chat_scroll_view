import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_extent_animation.dart';
import 'package:chatscrollview/src/chat_scroll/chat_message_parent_data.dart';
import 'package:chatscrollview/src/chat_scroll/chat_mutations.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_dev_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Owns message insert / update / remove extent lifecycles for
/// [RenderChatScrollView].
///
/// **Tick order** (contract T1): [advanceAnimations] runs springs and opacity,
/// then tail scroll compensation, then queues finished removals. The render
/// object calls [_repositionFromAnchor] afterward using [effectiveHeight].
///
/// **Layout deferral** (contract L1): while visible extent work is in flight,
/// [shouldDeferStructuralLayout] blocks fan-out / eviction until animations
/// settle; [onAnimationsSettled] schedules exactly one structural layout.
///
/// **Mutations-only entry**: [onMutation] is the sole viewport subscription
/// for insert, update, and remove — not [ChatMutationsMixin.pendingRemovalIds].
///
/// **Eager anchor** : when removal starts, scroll reference moves off the
/// collapsing ghost before springs run so [ChatAnimator] never bases navigation
/// on a [pendingRemoval] id. Finalize skips a second move when
/// [_anchorMovedAtRequest] already recorded the id.
///
/// **Multi tail removal**: [_activeTailRemovalIds] aggregates per-frame
/// bottom-pin compensation — parallel tail deletes must not overwrite each
/// other’s track state.
@internal
class ChatExtentCoordinator {
  /// Creates a coordinator bound to [dataSource] and render-object callbacks.
  ChatExtentCoordinator({
    required ChatDataSource dataSource,
    required ChatScrollController controller,
    required RenderBox? Function(int id) childForId,
    required ChatMessageParentData Function(RenderBox child) parentDataOf,
    required bool Function() hasSize,
    required double Function() viewportHeight,
    required double Function() bottomPad,
    required void Function(double delta) applyScrollDelta,
    required VoidCallback markNeedsLayout,
    required VoidCallback markNeedsPaint,
    required VoidCallback ensureTicker,
    required void Function(void Function()) invokeChildManager,
    required ChatChildManagerBridge childManager,
    required void Function() repositionFromAnchor,
    required bool Function() wasAtTailLastLayout,
    required int? Function(int fromId, int direction) findPresentNeighbor,
    required void Function(int targetId, {required bool pinTail})
    applyAnchorMoveAwayFromRemoved,
    required ({int targetId, bool pinTail})? Function(int id)
    planAnchorMoveAwayFromRemoved,
    void Function(int id)? seedTailInsertPin,
    void Function(Iterable<int> ids)? rebuildGroupedNeighbors,
    VoidCallback? onAnimationsFullySettled,
    bool Function(int id)? onRemovalRequested,
    ChatScrollDevLog? extentLog,
  }) : _dataSource = dataSource,
       _controller = controller,
       _childForId = childForId,
       _parentDataOf = parentDataOf,
       _hasSize = hasSize,
       _viewportHeight = viewportHeight,
       _bottomPad = bottomPad,
       _applyScrollDelta = applyScrollDelta,
       _markNeedsLayout = markNeedsLayout,
       _markNeedsPaint = markNeedsPaint,
       _ensureTicker = ensureTicker,
       _invokeChildManager = invokeChildManager,
       _childManager = childManager,
       _repositionFromAnchor = repositionFromAnchor,
       _wasAtTailLastLayout = wasAtTailLastLayout,
       _findPresentNeighbor = findPresentNeighbor,
       _applyAnchorMoveAwayFromRemoved = applyAnchorMoveAwayFromRemoved,
       _planAnchorMoveAwayFromRemoved = planAnchorMoveAwayFromRemoved,
       _seedTailInsertPin = seedTailInsertPin,
       _rebuildGroupedNeighbors = rebuildGroupedNeighbors,
       _onAnimationsFullySettled = onAnimationsFullySettled,
       _onRemovalRequested = onRemovalRequested,
       _extentLog = extentLog ?? ChatScrollDevLog('ChatScrollExtent');

  final ChatDataSource _dataSource;
  final ChatScrollController _controller;
  final RenderBox? Function(int id) _childForId;
  final ChatMessageParentData Function(RenderBox child) _parentDataOf;
  final bool Function() _hasSize;
  final double Function() _viewportHeight;
  final double Function() _bottomPad;
  final void Function(double delta) _applyScrollDelta;
  final VoidCallback _markNeedsLayout;
  final VoidCallback _markNeedsPaint;
  final VoidCallback _ensureTicker;
  final void Function(void Function()) _invokeChildManager;
  final ChatChildManagerBridge _childManager;
  final void Function() _repositionFromAnchor;
  final bool Function() _wasAtTailLastLayout;
  final int? Function(int fromId, int direction) _findPresentNeighbor;
  final void Function(int targetId, {required bool pinTail})
  _applyAnchorMoveAwayFromRemoved;
  final ({int targetId, bool pinTail})? Function(int id)
  _planAnchorMoveAwayFromRemoved;
  final void Function(int id)? _seedTailInsertPin;
  final void Function(Iterable<int> ids)? _rebuildGroupedNeighbors;
  final VoidCallback? _onAnimationsFullySettled;
  final bool Function(int id)? _onRemovalRequested;
  final ChatScrollDevLog _extentLog;

  final Set<int> _pendingInsertAnimations = <int>{};
  final Set<int> _pendingUpdateAnimations = <int>{};
  final List<int> _pendingElementRemovals = <int>[];
  final Set<int> _pendingRemovalNeighborInvalidations = <int>{};
  final Set<int> _animatingMessageIds = <int>{};
  final Map<int, double> _removalPrevHeight = <int, double>{};
  final Map<int, double> _removalFinalizeScrollDelta = <int, double>{};
  final Map<int, double> _tailInsertPrevHeight = <int, double>{};
  final Set<int> _activeRemovalIds = <int>{};
  final Set<int> _activeTailRemovalIds = <int>{};
  final Set<int> _anchorMovedAtRequest = <int>{};
  final Set<int> _anchorWouldPinTailAtRequest = <int>{};
  final Set<int> _deferredRemovalStarts = <int>{};
  final List<int> _finishedRemovalsThisTick = <int>[];

  bool _hasActiveExtentAnimations = false;
  bool _postLayoutRemovalNotify = false;
  bool _queuedLayout = false;

  int? _activeTailInsertId;

  /// Whether any extent spring, opacity run, or pending eviction remains.
  bool get hasActiveWork =>
      _hasActiveExtentAnimations ||
      _animatingMessageIds.isNotEmpty ||
      _pendingElementRemovals.isNotEmpty ||
      _dataSource.pendingRemovalIds.value.isNotEmpty;

  /// Whether [ChatAnimator] should queue `animateTo` until extent springs settle.
  ///
  /// Intentionally narrower than [hasActiveWork]: pending removal ids and
  /// queued evictions may remain after springs finish; navigation must still
  /// flush once [_onAnimationsFullySettled] fires.
  bool shouldDeferNavigation() {
    if (_hasActiveExtentAnimations || _animatingMessageIds.isNotEmpty) {
      return true;
    }
    final anchorId = _controller.anchorMessageId;
    final child = _childForId(anchorId);
    if (child == null) return false;
    return _parentDataOf(child).pendingRemoval;
  }

  /// Pending evictions not yet processed by layout.
  bool get hasPendingElementRemovals => _pendingElementRemovals.isNotEmpty;

  /// Whether [id] is queued for eviction after collapse settled.
  bool isPendingElementRemoval(int id) => _pendingElementRemovals.contains(id);

  /// First active tail-removal id, if any (debug / pinNewest gate).
  int? get activeTailRemovalId =>
      _activeTailRemovalIds.isEmpty ? null : _activeTailRemovalIds.first;

  /// Whether any tail-removal bottom-pin compensation is active.
  bool get hasActiveTailRemovals => _activeTailRemovalIds.isNotEmpty;

  /// Handles insert, update, and remove mutation events.
  void onMutation(ChatMutation mutation) {
    _extentEvent('mutation.handled', {
      'kind': mutation.kind.name,
      'id': mutation.id,
      'reason': mutation.reason,
    });
    switch (mutation.kind) {
      case ChatMutationKind.insert:
        _pendingInsertAnimations.add(mutation.id);
        _markNeedsLayout();
      case ChatMutationKind.update:
        _pendingUpdateAnimations.add(mutation.id);
        _markNeedsLayout();
      case ChatMutationKind.remove:
        _handleRemoveMutation(mutation.id);
    }
  }

  /// Vertical extent reserved for layout — animated during insert/remove/resize.
  double effectiveHeight(RenderBox child) {
    final pd = _parentDataOf(child);
    if (pd.pendingRemoval ||
        pd.heightSpring != null ||
        _pendingElementRemovals.contains(pd.id)) {
      return pd.animatedHeight.clamp(0.0, double.infinity);
    }
    if (pd.animatedHeight > 0) return pd.animatedHeight;
    return child.size.height;
  }

  /// Whether structural layout (fan-out, eviction, clamp refan) should defer.
  bool shouldDeferStructuralLayout() {
    if (_queuedLayout) return false;
    // Collapse finished — eviction must run even if the ghost child is still
    // in the tree until [processPendingElementRemovals] runs.
    if (_pendingElementRemovals.isNotEmpty) return false;
    // Collapse ghosts: refan / pin-newest / band remeasure wait until finalize.
    if (_activeRemovalIds.isNotEmpty) return true;
    if (_hasActiveExtentAnimations || _animatingMessageIds.isNotEmpty) {
      return true;
    }
    if (_dataSource.pendingRemovalIds.value.isEmpty) return false;
    for (final id in _dataSource.pendingRemovalIds.value) {
      if (_deferredRemovalStarts.contains(id)) continue;
      if (_childForId(id) != null) return true;
    }
    return false;
  }

  /// Called when the render object is about to run a deferred structural layout.
  void consumeQueuedLayout() => _queuedLayout = false;

  /// Suppresses layout-phase [pinNewest] while tail insert/remove springs run.
  bool shouldSuppressPinNewest(RenderBox? newestChild) {
    if (_activeTailInsertId != null || _activeTailRemovalIds.isNotEmpty) {
      return true;
    }
    if (newestChild == null) return false;
    final pd = _parentDataOf(newestChild);
    if (pd.targetHeight > 0 && pd.animatedHeight < pd.targetHeight * 0.1) {
      return true;
    }
    return false;
  }

  /// Whether [child] intersects the visible viewport.
  bool shouldAnimateExtent(RenderBox child) {
    final pd = _parentDataOf(child);
    final top = pd.offset;
    final height = pd.targetHeight > 0 ? pd.targetHeight : child.size.height;
    final bottom = top + height;
    return bottom > 0 && top < _viewportHeight();
  }

  /// Passive extent sync during [child.layout] — does not consume pending flags.
  void syncPassiveExtents(RenderBox child, int id) {
    final pd = _parentDataOf(child);
    pd.id = id;
    final measured = child.size.height;

    if (pd.pendingRemoval) {
      pd.targetHeight = 0;
      return;
    }

    if (_pendingInsertAnimations.contains(id) ||
        _pendingUpdateAnimations.contains(id)) {
      _extentEvent('sync.defer', {
        'id': id,
        'pendingInsert': _pendingInsertAnimations.contains(id),
        'pendingUpdate': _pendingUpdateAnimations.contains(id),
        'measured': DevLogFormat.f(measured),
      });
      return;
    }

    if (pd.heightSpring != null || pd.opacityRun != null) {
      if (pd.heightSpring != null && (pd.targetHeight - measured).abs() > 0.5) {
        pd.targetHeight = measured;
        pd.heightSpring!.retarget(measured);
      }
      return;
    }

    _applyInstantExtent(pd, measured);
  }

  /// Starts insert/update animations after fan-out offsets are final.
  void applyDeferredExtentAnimations(Set<int> built) {
    for (final id in built) {
      final child = _childForId(id);
      if (child == null) continue;
      final pd = _parentDataOf(child);
      final measured = child.size.height;

      if (pd.pendingRemoval) continue;

      if (_pendingInsertAnimations.remove(id)) {
        final visible = shouldAnimateExtent(child);
        _extentEvent('defer.insert', {
          'id': id,
          'visible': visible,
          'offset': DevLogFormat.f(pd.offset),
          'measured': DevLogFormat.f(measured),
          'viewportH': DevLogFormat.f(_viewportHeight()),
        });
        if (visible) {
          _beginInsertAnimation(child, pd, measured, id);
        } else {
          _applyInstantExtent(pd, measured);
          _extentEvent('defer.insert.instant', {'id': id});
        }
        continue;
      }

      if (_pendingUpdateAnimations.remove(id)) {
        final visible = shouldAnimateExtent(child);
        _extentEvent('defer.update', {
          'id': id,
          'visible': visible,
          'offset': DevLogFormat.f(pd.offset),
          'measured': DevLogFormat.f(measured),
        });
        if (visible) {
          _beginUpdateAnimation(child, pd, measured, id);
        } else {
          _applyInstantExtent(pd, measured);
        }
      }
    }

    if (_pendingInsertAnimations.isNotEmpty ||
        _pendingUpdateAnimations.isNotEmpty) {
      _extentEvent('defer.unbuilt', {
        'pendingInsert': DevLogFormat.ids(_pendingInsertAnimations),
        'pendingUpdate': DevLogFormat.ids(_pendingUpdateAnimations),
        'builtCount': built.length,
      });
    }
  }

  /// Advances springs, tail compensation, and finished removals (contract T1).
  bool advanceAnimations(Duration elapsed, Duration? prevElapsed) {
    final dtMs = prevElapsed == null || elapsed < prevElapsed
        ? 0.0
        : (elapsed - prevElapsed).inMicroseconds / 1000.0;
    final dtSeconds = dtMs / 1000.0;

    var anyActive = false;
    _finishedRemovalsThisTick.clear();

    for (final id in List<int>.from(_animatingMessageIds)) {
      final child = _childForId(id);
      if (child == null) {
        _animatingMessageIds.remove(id);
        continue;
      }
      final pd = _parentDataOf(child);

      if (pd.heightSpring != null) {
        pd.heightSpring!.advance(dtSeconds);
        pd.animatedHeight = pd.heightSpring!.value;
        if (pd.heightSpring!.isDone) {
          pd.animatedHeight = pd.pendingRemoval ? 0 : pd.targetHeight;
          pd.heightSpring = null;
          if (pd.pendingRemoval && pd.animatedHeight <= 0) {
            _finishedRemovalsThisTick.add(id);
          }
        } else {
          anyActive = true;
        }
      }

      if (pd.opacityRun != null) {
        pd.opacity = pd.opacityRun!.value;
        if (pd.opacityRun!.advance(dtMs)) {
          pd.opacity = pd.pendingRemoval ? 0 : 1;
          pd.opacityRun = null;
        } else {
          anyActive = true;
        }
      }

      if (!pd.pendingRemoval &&
          pd.heightSpring != null &&
          pd.targetHeight > 0 &&
          pd.animatedHeight < pd.targetHeight) {
        final heightFade = (pd.animatedHeight / pd.targetHeight).clamp(
          0.0,
          1.0,
        );
        if (heightFade > pd.opacity) pd.opacity = heightFade;
      }

      if (child case HasHorizontalExtentAnimation horizontal
          when horizontal.horizontalAnimationActive) {
        horizontal.advanceHorizontal(dtMs);
        anyActive = true;
      }

      if (pd.heightSpring == null && pd.opacityRun == null) {
        _animatingMessageIds.remove(id);
      }
    }

    final wasActive = _hasActiveExtentAnimations;
    _hasActiveExtentAnimations = anyActive;

    if (_activeTailInsertId != null) {
      _compensateTailInsertScroll();
    }
    if (_activeRemovalIds.isNotEmpty) {
      _compensateRemovalScrollAll();
    }

    _finishedRemovalsThisTick.forEach(_queueFinalizeRemoval);

    if (wasActive && !anyActive && _animatingMessageIds.isEmpty) {
      _onAnimationsSettled();
    }

    if (_extentLog.enabled &&
        (anyActive || _finishedRemovalsThisTick.isNotEmpty) &&
        _extentLog.bumpTickFrame() % 6 == 0) {
      final sampleId = _animatingMessageIds.isEmpty
          ? null
          : _animatingMessageIds.first;
      final sampleChild = sampleId == null ? null : _childForId(sampleId);
      final samplePd = sampleChild == null ? null : _parentDataOf(sampleChild);
      _extentEvent('tick', {
        'anyActive': anyActive,
        'animatingCount': _animatingMessageIds.length,
        'finishedRemovals': DevLogFormat.ids(_finishedRemovalsThisTick),
        'sampleId': ?sampleId,
        if (samplePd != null)
          'sampleH': DevLogFormat.f(samplePd.animatedHeight),
        if (samplePd != null) 'sampleOpacity': DevLogFormat.f(samplePd.opacity),
        'dtMs': DevLogFormat.f(dtMs),
      });
    }

    return anyActive;
  }

  void processPendingElementRemovals() {
    if (_pendingElementRemovals.isEmpty) return;
    final ids = List<int>.from(_pendingElementRemovals);
    _pendingElementRemovals.clear();

    ids.forEach(_dataSource.silentConfirmRemoval);
    _postLayoutRemovalNotify = true;

    _invokeChildManager(() {
      _childManager.removeChildren(ids);
    });
  }

  void invalidateNeighborsForRemoval(int id) {
    _presentNeighborsAround(
      id,
    ).forEach(_pendingRemovalNeighborInvalidations.add);
    _markNeedsLayout();
  }

  void processPendingNeighborInvalidations() {
    if (_pendingRemovalNeighborInvalidations.isEmpty) return;
    final ids = List<int>.from(_pendingRemovalNeighborInvalidations);
    _pendingRemovalNeighborInvalidations.clear();
    _rebuildGroupedNeighbors?.call(ids);
  }

  void schedulePostLayoutRemovalNotify() {
    if (!_postLayoutRemovalNotify) return;
    _postLayoutRemovalNotify = false;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_dataSource.isDisposed) return;
      _dataSource.flushPendingRemovalNotify();
    });
  }

  void _handleRemoveMutation(int id) {
    final deferRelayout = _onRemovalRequested?.call(id) ?? false;
    final child = _childForId(id);
    if (child == null) {
      if (deferRelayout) {
        _deferredRemovalStarts.add(id);
        _extentEvent('remove.defer', {
          'id': id,
          'reason': 'selection-relayout-offTree',
        });
        _markNeedsLayout();
        return;
      }
      _eagerReassignAnchor(id);
      _extentEvent('remove.offTree', {'id': id});
      _dataSource.confirmMessageRemoval(id);
      return;
    }
    final pd = _parentDataOf(child);
    if (pd.pendingRemoval) return;
    pd.pendingRemoval = true;
    invalidateNeighborsForRemoval(id);
    if (deferRelayout) {
      _deferredRemovalStarts.add(id);
      _extentEvent('remove.defer', {'id': id, 'reason': 'selection-relayout'});
      _markNeedsLayout();
      return;
    }
    _eagerReassignAnchor(id);
    final fromHeight = child.size.height;
    if (!shouldAnimateExtent(child)) {
      _extentEvent('remove.instant', {
        'id': id,
        'offset': DevLogFormat.f(pd.offset),
      });
      pd.targetHeight = 0;
      pd.animatedHeight = 0;
      pd.opacity = 0;
      _recordViewportSpanningPredecessorFinalizeScroll(id, pd, fromHeight);
      _queueFinalizeRemoval(id);
      return;
    }
    _beginRemovalAnimation(child, pd, id, fromHeight: fromHeight);
    _ensureTicker();
    _markNeedsLayout();
  }

  /// Starts removal collapse after selection chrome has snapped shut and
  /// children have been laid out at full width. Returns whether any removal
  /// animation was started (caller should refan when the anchor moved).
  bool startDeferredRemovalAnimations(Set<int> built) {
    if (_deferredRemovalStarts.isEmpty) return false;
    var started = false;
    for (final id in _deferredRemovalStarts.toList()) {
      if (!built.contains(id)) continue;
      final child = _childForId(id);
      if (child == null) {
        _deferredRemovalStarts.remove(id);
        continue;
      }
      _deferredRemovalStarts.remove(id);
      final pd = _parentDataOf(child);
      if (!pd.pendingRemoval) {
        pd.pendingRemoval = true;
        invalidateNeighborsForRemoval(id);
      }
      _eagerReassignAnchor(id);
      final fromHeight = child.size.height;
      if (!shouldAnimateExtent(child)) {
        _extentEvent('remove.instant', {
          'id': id,
          'offset': DevLogFormat.f(pd.offset),
          'deferred': true,
        });
        pd.targetHeight = 0;
        pd.animatedHeight = 0;
        pd.opacity = 0;
        _recordViewportSpanningPredecessorFinalizeScroll(id, pd, fromHeight);
        _queueFinalizeRemoval(id);
        continue;
      }
      _beginRemovalAnimation(child, pd, id, fromHeight: fromHeight);
      _ensureTicker();
      started = true;
    }
    if (_deferredRemovalStarts.isNotEmpty) {
      _extentEvent('defer.remove.unbuilt', {
        'pending': DevLogFormat.ids(_deferredRemovalStarts),
        'builtCount': built.length,
      });
    }
    return started;
  }

  void _onAnimationsSettled() {
    _onAnimationsFullySettled?.call();
    if (shouldDeferStructuralLayout()) return;
    _extentEvent('defer.layout', {'queuedLayout': true});
    _queuedLayout = true;
    _markNeedsLayout();
  }

  /// Moves scroll reference off [removedId] at removal request — not at finalize.
  void _eagerReassignAnchor(int removedId) {
    if (_anchorMovedAtRequest.contains(removedId)) return;

    final wasTailRemoval = _dataSource.isTailRemovalAnimation(removedId);
    ({int targetId, bool pinTail})? move;

    if (_controller.anchorMessageId == removedId) {
      move = _planAnchorMoveAwayFromRemoved(removedId);
    } else if (wasTailRemoval && _wasAtTailLastLayout()) {
      final newest = _dataSource.newestKnownId;
      if (newest != null && newest != removedId) {
        move = (targetId: newest, pinTail: true);
      }
    }

    if (move == null) return;

    _extentEvent('anchor.move.eager', {
      'fromId': removedId,
      'targetId': move.targetId,
      'pinTail': false,
      'wouldPinTail': move.pinTail,
    });
    // Keep the neighbor at its laid-out offset — pin the collapsing ghost to
    // the bottom edge via tick compensation instead (pinTail here hides the
    // collapse below the viewport).
    _applyAnchorMoveAwayFromRemoved(move.targetId, pinTail: false);
    _anchorMovedAtRequest.add(removedId);
    if (move.pinTail) _anchorWouldPinTailAtRequest.add(removedId);
  }

  void _queueFinalizeRemoval(int id) {
    if (_pendingElementRemovals.contains(id)) return;
    _pendingElementRemovals.add(id);
    _animatingMessageIds.remove(id);
    final child = _childForId(id);
    if (child != null) {
      final pd = _parentDataOf(child);
      pd.animatedHeight = 0;
      pd.targetHeight = 0;
      pd.heightSpring = null;
      pd.opacityRun = null;
    }
    _extentEvent('remove.finalize', {'id': id});
    final finalizeDelta = _removalFinalizeScrollDelta.remove(id);
    if (finalizeDelta != null && finalizeDelta.abs() > 0.01) {
      _applyScrollDelta(finalizeDelta);
      _extentEvent('removal.finalize.scroll', {
        'id': id,
        'delta': DevLogFormat.f(finalizeDelta),
      });
    }
    if (!_anchorMovedAtRequest.contains(id)) {
      final wasTailRemoval = _dataSource.isTailRemovalAnimation(id);
      final move = _planAnchorMoveAwayFromRemoved(id);
      if (move != null) {
        _extentEvent('anchor.move', {
          'fromId': id,
          'targetId': move.targetId,
          'pinTail': move.pinTail,
        });
        _applyAnchorMoveAwayFromRemoved(move.targetId, pinTail: move.pinTail);
      } else if (wasTailRemoval && _wasAtTailLastLayout()) {
        final newest = _dataSource.newestKnownId;
        if (newest != null) {
          _extentEvent('anchor.move', {
            'fromId': id,
            'targetId': newest,
            'pinTail': true,
          });
          _applyAnchorMoveAwayFromRemoved(newest, pinTail: true);
        }
      }
    } else if (_anchorWouldPinTailAtRequest.contains(id) &&
        _wasAtTailLastLayout()) {
      // Ghost-pin scroll compensation already migrated the anchor during
      // collapse — do not re-pin here (causes a visible jump at finalize).
      _extentEvent('anchor.move.finalize', {
        'fromId': id,
        'action': 'skip',
        'reason': 'ghost-pin-settled',
      });
    }
    _anchorMovedAtRequest.remove(id);
    _anchorWouldPinTailAtRequest.remove(id);
    _activeRemovalIds.remove(id);
    _activeTailRemovalIds.remove(id);
    _removalPrevHeight.remove(id);
    if (_activeTailInsertId == id) {
      _activeTailInsertId = null;
      _tailInsertPrevHeight.remove(id);
    }
    _repositionFromAnchor();
    _markNeedsLayout();
    _markNeedsPaint();
  }

  Iterable<int> _presentNeighborsAround(int id) sync* {
    final predecessor = _findPresentNeighbor(id, -1);
    if (predecessor != null) yield predecessor;
    final successor = _findPresentNeighbor(id, 1);
    if (successor != null) {
      yield successor;
      final successor2 = _findPresentNeighbor(successor, 1);
      if (successor2 != null) yield successor2;
    }
  }

  void _startHeightSpring(
    ChatMessageParentData pd,
    double to, {
    double? from,
    double velocity = 0,
  }) {
    from ??= pd.animatedHeight;
    pd.heightSpring = ExtentSpring.start(
      from: from,
      to: to,
      velocity: velocity,
    );
  }

  void _extentEvent(String tag, Map<String, Object?> fields) =>
      _extentLog.event(tag, fields);

  void _applyInstantExtent(ChatMessageParentData pd, double measured) {
    pd.targetHeight = measured;
    pd.animatedHeight = measured;
    pd.heightSpring = null;
    pd.opacityRun = null;
    pd.opacity = 1;
  }

  void _beginInsertAnimation(
    RenderBox child,
    ChatMessageParentData pd,
    double measured,
    int id,
  ) {
    pd.targetHeight = measured;
    pd.animatedHeight = 0;
    pd.opacity = 0;
    _startHeightSpring(pd, measured, from: 0);
    pd.opacityRun = CurveRun(
      telegramCurve,
      const Duration(milliseconds: 180),
      0,
      1,
    );
    _animatingMessageIds.add(id);
    if (_dataSource.newestKnownId == id) {
      _activeTailInsertId = id;
      _tailInsertPrevHeight[id] = 0;
      _seedTailInsertPin?.call(id);
    }
    _ensureTicker();
    _extentEvent('anim.insert.start', {
      'id': id,
      'measured': DevLogFormat.f(measured),
      'offset': DevLogFormat.f(_parentDataOf(child).offset),
      'animatingCount': _animatingMessageIds.length,
    });
  }

  void _beginUpdateAnimation(
    RenderBox child,
    ChatMessageParentData pd,
    double measured,
    int id,
  ) {
    pd.targetHeight = measured;
    final from = pd.animatedHeight > 0 ? pd.animatedHeight : measured;
    if ((from - measured).abs() < 0.5) {
      _applyInstantExtent(pd, measured);
      _extentEvent('anim.update.noop', {
        'id': id,
        'measured': DevLogFormat.f(measured),
      });
      return;
    }
    final velocity = pd.heightSpring?.velocity ?? 0;
    if (pd.heightSpring != null) {
      pd.heightSpring!.retarget(measured);
    } else {
      _startHeightSpring(pd, measured, from: from, velocity: velocity);
    }
    _animatingMessageIds.add(id);
    _ensureTicker();
    _extentEvent('anim.update.start', {
      'id': id,
      'from': DevLogFormat.f(from),
      'to': DevLogFormat.f(measured),
      'offset': DevLogFormat.f(_parentDataOf(child).offset),
    });
  }

  void _beginRemovalAnimation(
    RenderBox child,
    ChatMessageParentData pd,
    int id, {
    required double fromHeight,
  }) {
    pd.targetHeight = 0;
    if (pd.animatedHeight <= 0) pd.animatedHeight = fromHeight;
    _startHeightSpring(pd, 0, from: pd.animatedHeight);
    pd.opacityRun = CurveRun(
      telegramCurve,
      const Duration(milliseconds: 220),
      pd.opacity,
      0,
    );
    _animatingMessageIds.add(id);
    _activeRemovalIds.add(id);
    _removalPrevHeight[id] = fromHeight;
    if (_dataSource.isTailRemovalAnimation(id)) {
      _activeTailRemovalIds.add(id);
    }
    _recordViewportSpanningPredecessorFinalizeScroll(id, pd, fromHeight);
    _ensureTicker();
    _extentEvent('anim.remove.start', {
      'id': id,
      'fromHeight': DevLogFormat.f(fromHeight),
      'offset': DevLogFormat.f(_parentDataOf(child).offset),
    });
  }

  /// One-shot scroll at removal finalize for a viewport-spanning predecessor
  /// whose bottom sits above the anchor — mirrors the total tick compensation
  /// that gradual collapse would apply, without mid-animation drift when the
  /// anchor already sits on a different row (e.g. id=5997 while anchor=6002).
  void _recordViewportSpanningPredecessorFinalizeScroll(
    int id,
    ChatMessageParentData pd,
    double fromHeight,
  ) {
    if (_dataSource.isTailRemovalAnimation(id)) return;
    if (_anchorMovedAtRequest.contains(id)) return;
    if (!_hasSize()) return;

    final bottomEdge = _viewportHeight() - _bottomPad();
    final top = pd.offset;
    final bottom = top + fromHeight;
    if (top > 0 || bottom <= bottomEdge) return;

    final anchorY = _controller.anchorPixelOffset;
    if (bottom > anchorY + 0.5) return;

    _removalFinalizeScrollDelta[id] = -fromHeight;
  }

  void _compensateTailInsertScroll() {
    final id = _activeTailInsertId;
    if (id == null || !_hasSize()) return;

    final child = _childForId(id);
    if (child == null) {
      _tailInsertPrevHeight.remove(id);
      _activeTailInsertId = null;
      return;
    }
    final pd = _parentDataOf(child);
    final bottomEdge = _viewportHeight() - _bottomPad();
    final done =
        pd.heightSpring == null && pd.animatedHeight >= pd.targetHeight - 0.5;

    if (_controller.anchorMessageId == id) {
      final desiredY = bottomEdge - pd.animatedHeight;
      final delta = desiredY - _controller.anchorPixelOffset;
      if (delta.abs() > 0.01) {
        _applyScrollDelta(delta);
        _extentEvent('tail.compensate.insert', {
          'id': id,
          'mode': 'anchor',
          'delta': DevLogFormat.f(delta),
          'desiredY': DevLogFormat.f(desiredY),
          'animatedH': DevLogFormat.f(pd.animatedHeight),
        });
      }
    } else {
      final prevH = _tailInsertPrevHeight[id] ?? 0;
      final dH = pd.animatedHeight - prevH;
      if (dH.abs() > 0.01) {
        _applyScrollDelta(-dH);
        _extentEvent('tail.compensate.insert', {
          'id': id,
          'mode': 'height',
          'dH': DevLogFormat.f(dH),
          'animatedH': DevLogFormat.f(pd.animatedHeight),
        });
      }
      _tailInsertPrevHeight[id] = pd.animatedHeight;
    }

    if (done) {
      _tailInsertPrevHeight.remove(id);
      _activeTailInsertId = null;
    }
  }

  void _compensateRemovalScrollAll() {
    if (!_hasSize() || _activeRemovalIds.isEmpty) return;

    var totalDelta = 0.0;
    final finished = <int>[];
    final bottomEdge = _viewportHeight() - _bottomPad();

    for (final id in _activeRemovalIds) {
      final child = _childForId(id);
      if (child == null) {
        finished.add(id);
        continue;
      }
      final pd = _parentDataOf(child);
      if (!pd.pendingRemoval &&
          pd.heightSpring == null &&
          !_pendingElementRemovals.contains(id)) {
        finished.add(id);
        continue;
      }

      if (_activeTailRemovalIds.contains(id)) {
        if (_anchorMovedAtRequest.contains(id)) {
          // Eager anchor move: keep the collapsing ghost's bottom on the inset
          // line so height + opacity animation stays visible at the tail.
          final desiredTop = bottomEdge - pd.animatedHeight;
          totalDelta += desiredTop - pd.offset;
        } else if (_controller.anchorMessageId == id) {
          final desiredY = bottomEdge - pd.animatedHeight;
          totalDelta += desiredY - _controller.anchorPixelOffset;
        } else {
          final prevH = _removalPrevHeight[id];
          if (prevH != null) {
            totalDelta += -(pd.animatedHeight - prevH);
          }
        }
      }
      _removalPrevHeight[id] = pd.animatedHeight;
    }

    if (totalDelta.abs() > 0.01) {
      _applyScrollDelta(totalDelta);
      if (_activeTailRemovalIds.isNotEmpty) {
        _extentEvent('tail.compensate.remove', {
          'mode': 'ghost-pin',
          'activeCount': _activeRemovalIds.length,
          'delta': DevLogFormat.f(totalDelta),
        });
      }
    }

    for (final id in finished) {
      _activeRemovalIds.remove(id);
      _activeTailRemovalIds.remove(id);
      _removalPrevHeight.remove(id);
    }
  }
}

/// Narrow bridge to [ChatChildManager] without importing the render object.
@internal
abstract interface class ChatChildManagerBridge {
  /// Removes message children with the given ids.
  void removeChildren(List<int> ids);

  /// Forces rebuild of a single built child.
  void invalidateBuiltChild(int id);
}

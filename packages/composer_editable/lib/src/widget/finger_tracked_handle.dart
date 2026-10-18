import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

/// Material selection handle diameter (22dp).
const double kMaterialSelectionHandleSize = 22;

/// Touch platforms that use finger-tracked moving-handle overlay during drag.
bool get usesFingerTrackedHandleDrag => switch (defaultTargetPlatform) {
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.fuchsia => true,
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => false,
};

/// Which selection handle is being finger-tracked during drag.
enum FingerTrackedMovingHandle {
  /// The handle at the start of the selection.
  start,

  /// The handle at the end of the selection.
  end,
}

/// Whether [kind] should use finger-tracked handle motion.
///
/// Touch/stylus/unknown always qualify. On Android, [PointerDeviceKind.mouse]
/// qualifies too so scrcpy pointer injection gets composer overlay parity.
bool pointerKindUsesFingerTrackedHandle(PointerDeviceKind kind) {
  if (kind == PointerDeviceKind.touch ||
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.unknown) {
    return true;
  }
  return kind == PointerDeviceKind.mouse &&
      defaultTargetPlatform == TargetPlatform.android;
}

/// Grab offset frozen at drag start (AOSP `mTouchToWindowOffset` parity).
///
/// Overlay anchor = [pointerGlobal] + result = [caretAnchorGlobal] at DOWN.
Offset computeHandleGrabOffset({
  required Offset pointerGlobal,
  required Offset caretAnchorGlobal,
}) => caretAnchorGlobal - pointerGlobal;

/// Caret-equivalent X for extent hit-test during finger-tracked handle drag.
///
/// Uses frozen [grabOffset] so selection tracks the moving overlay, not raw
/// finger position on the handle bulb.
double compensatedHandleHitTestDx({
  required Offset pointerGlobal,
  required Offset grabOffset,
}) => (pointerGlobal + grabOffset).dx;

/// Whether the **moving extent** is at the selection start (extent-based).
///
/// Used for extent/highlight logic when selection inverts. **Frozen handle
/// chrome** keeps the grabbed physical widget as the moving overlay instead —
/// see [ExtendedSelectionOverlay.isFingerTrackedMovingStartHandle] in `text_selection.dart`.
bool fingerTrackedMovingHandleIsStart({
  required int fixedBase,
  required int extentOffset,
  required FingerTrackedMovingHandle grabbedHandle,
}) {
  if (extentOffset < fixedBase) {
    return true;
  }
  if (extentOffset > fixedBase) {
    return false;
  }
  return grabbedHandle == FingerTrackedMovingHandle.start;
}

/// Vector from the Material handle anchor to the visual bulb center.
Offset materialHandleBulbOffsetFromAnchor(Offset handleAnchor) {
  const bulbCenter = Offset(
    kMaterialSelectionHandleSize / 2,
    kMaterialSelectionHandleSize / 2,
  );
  return bulbCenter - handleAnchor;
}

/// Delta compensation when invert swaps left↔right handle geometry.
Offset compensateFollowerDeltaForHandleAnchorChange({
  required Offset fromAnchor,
  required Offset toAnchor,
}) =>
    materialHandleBulbOffsetFromAnchor(fromAnchor) -
    materialHandleBulbOffsetFromAnchor(toAnchor);

/// Endpoint index (`0` = selection start, `1` = end) for the moving extent.
///
/// When [extentOffset] equals [fixedBase] (common on END DOWN after a reverse
/// leaves extent on the start side), indices follow [grabbedHandle] so the
/// fixed-leader snapshot pins to the opposite physical endpoint — not the
/// stale equal-case default that teleports the start overlay to the end.
int fingerTrackedExtentEndpointIndex({
  required int fixedBase,
  required int extentOffset,
  required FingerTrackedMovingHandle grabbedHandle,
}) {
  if (extentOffset < fixedBase) {
    return 0;
  }
  if (extentOffset > fixedBase) {
    return 1;
  }
  return switch (grabbedHandle) {
    FingerTrackedMovingHandle.end => 1,
    FingerTrackedMovingHandle.start => 0,
  };
}

/// Endpoint index for the fixed base (opposite of [fingerTrackedExtentEndpointIndex]).
int fingerTrackedFixedBaseEndpointIndex({
  required int fixedBase,
  required int extentOffset,
  required FingerTrackedMovingHandle grabbedHandle,
}) {
  if (extentOffset < fixedBase) {
    return 1;
  }
  if (extentOffset > fixedBase) {
    return 0;
  }
  return switch (grabbedHandle) {
    FingerTrackedMovingHandle.end => 0,
    FingerTrackedMovingHandle.start => 1,
  };
}

/// Safe [TextSelectionPoint] for [endpointIndex] when [getEndpointsForSelection]
/// may return a single point (exclusive end / collapsed-adjacent chrome).
TextSelectionPoint fingerTrackedEndpointAtIndex({
  required List<TextSelectionPoint> endpoints,
  required int endpointIndex,
}) {
  assert(endpoints.isNotEmpty, 'endpoints must not be empty');
  return endpoints[endpointIndex.clamp(0, endpoints.length - 1)];
}

/// Follower delta for the **moving** handle (`overlay − physicalLeader`).
///
/// Overlay follows `pointer + grabOffset`, then clamps into
/// [fieldBoundsLocal] so the teardrop stays inside the text field (product
/// override of ticket 09 unclamp — leaving the field clipped the handle on
/// reverse/autoscroll). Hit-test still uses unclamped `pointer + grab`.
Offset fingerTrackedMovingHandleDelta({
  required Offset pointerGlobal,
  required Offset grabOffset,
  required Offset physicalLeaderLocal,
  required RenderBox renderEditable,
  required Rect fieldBoundsLocal,
  Offset anchorCompensation = Offset.zero,
}) => fingerTrackedHandleFollowerDelta(
  pointerGlobal: pointerGlobal,
  grabOffset: grabOffset,
  leaderLocal: physicalLeaderLocal,
  renderEditable: renderEditable,
  fieldBoundsLocal: fieldBoundsLocal,
  anchorCompensation: anchorCompensation,
);

/// Follower delta for the **fixed** handle during frozen chrome.
///
/// Pins the handle to [fixedBaseLeaderLocal] while its layer link may sit on
/// the opposite selection end under the invert model.
Offset fingerTrackedFixedHandleDelta({
  required Offset fixedBaseLeaderLocal,
  required Offset physicalLeaderLocal,
}) => fixedBaseLeaderLocal - physicalLeaderLocal;

/// Fixed-base leader during a drag: the snapshot taken at drag start, so the
/// fixed handle does not jump with the selection's affinity, or the live leader
/// once the scroll position changed (a scrolled snapshot would be stale).
Offset fingerTrackedFixedBaseLeader({
  required Offset snapshotLeader,
  required Offset liveLeader,
  required double snapshotScrollPixels,
  required double currentScrollPixels,
}) {
  if (currentScrollPixels != snapshotScrollPixels) {
    return liveLeader;
  }
  return snapshotLeader;
}

/// Settle animation target: visual anchor at extent caret, not physical layer.
Offset fingerTrackedSettleTargetDelta({
  required Offset extentLeaderLocal,
  required Offset physicalLeaderLocal,
}) => extentLeaderLocal - physicalLeaderLocal;

/// Clamps the finger-tracked overlay anchor inside [fieldBounds].
Offset clampFingerTrackedOverlayLocal({
  required Offset overlayLocal,
  required Rect fieldBounds,
}) => Offset(
  overlayLocal.dx.clamp(fieldBounds.left, fieldBounds.right),
  overlayLocal.dy.clamp(fieldBounds.top, fieldBounds.bottom),
);

/// Whether [overlayLocal] would be clamped inside [fieldBounds].
bool fingerTrackedOverlayWouldClamp({
  required Offset overlayLocal,
  required Rect fieldBounds,
}) =>
    clampFingerTrackedOverlayLocal(
      overlayLocal: overlayLocal,
      fieldBounds: fieldBounds,
    ) !=
    overlayLocal;

/// Extra [CompositedTransformFollower] delta in [renderEditable] local space.
///
/// Decouples the moving handle from the caret [leaderLocal] while the leader
/// still tracks logical selection endpoints. Overlay = `pointer + grabOffset`
/// in editable local space, clamped to [fieldBoundsLocal].
Offset fingerTrackedHandleFollowerDelta({
  required Offset pointerGlobal,
  required Offset grabOffset,
  required Offset leaderLocal,
  required RenderBox renderEditable,
  required Rect fieldBoundsLocal,
  Offset anchorCompensation = Offset.zero,
}) {
  final rawOverlayLocal = renderEditable.globalToLocal(
    pointerGlobal + grabOffset,
  );
  final overlayLocal = clampFingerTrackedOverlayLocal(
    overlayLocal: rawOverlayLocal,
    fieldBounds: fieldBoundsLocal,
  );
  return overlayLocal - leaderLocal + anchorCompensation;
}

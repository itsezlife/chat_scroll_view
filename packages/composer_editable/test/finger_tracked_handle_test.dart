import 'dart:ui' show Rect, TextDirection;

import 'package:composer_editable/src/widget/finger_tracked_handle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show TextSelectionPoint;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('usesFingerTrackedHandleDrag', () {
    test('true on android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(usesFingerTrackedHandleDrag, isTrue);
    });

    test('true on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(usesFingerTrackedHandleDrag, isTrue);
    });

    test('false on macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(usesFingerTrackedHandleDrag, isFalse);
    });
  });

  group('computeHandleGrabOffset', () {
    test('preserves handle position at drag start', () {
      const pointer = Offset(100, 200);
      const caret = Offset(80, 180);
      final grab = computeHandleGrabOffset(
        pointerGlobal: pointer,
        caretAnchorGlobal: caret,
      );
      expect(grab, const Offset(-20, -20));
      expect(pointer + grab, caret);
    });
  });

  group('fingerTrackedMovingHandleIsStart', () {
    test('extent right of fixed base → end handle moves', () {
      expect(
        fingerTrackedMovingHandleIsStart(
          fixedBase: 5,
          extentOffset: 10,
          grabbedHandle: FingerTrackedMovingHandle.end,
        ),
        isFalse,
      );
    });

    test('extent left of fixed base after invert → start handle moves', () {
      expect(
        fingerTrackedMovingHandleIsStart(
          fixedBase: 10,
          extentOffset: 3,
          grabbedHandle: FingerTrackedMovingHandle.end,
        ),
        isTrue,
      );
    });

    test('extent equals fixed base falls back to grabbed handle', () {
      expect(
        fingerTrackedMovingHandleIsStart(
          fixedBase: 5,
          extentOffset: 5,
          grabbedHandle: FingerTrackedMovingHandle.end,
        ),
        isFalse,
      );
      expect(
        fingerTrackedMovingHandleIsStart(
          fixedBase: 5,
          extentOffset: 5,
          grabbedHandle: FingerTrackedMovingHandle.start,
        ),
        isTrue,
      );
    });
  });

  group('compensateFollowerDeltaForHandleAnchorChange', () {
    test('right→left material handles shift bulb by (22, 0)', () {
      expect(
        compensateFollowerDeltaForHandleAnchorChange(
          fromAnchor: Offset.zero,
          toAnchor: const Offset(22, 0),
        ),
        const Offset(22, 0),
      );
    });
  });

  group('clampFingerTrackedOverlayLocal', () {
    test('clamps overlay inside field bounds', () {
      expect(
        clampFingerTrackedOverlayLocal(
          overlayLocal: const Offset(-10, 500),
          fieldBounds: const Rect.fromLTWH(0, 0, 200, 100),
        ),
        const Offset(0, 100),
      );
    });
  });

  group('fingerTrackedOverlayWouldClamp', () {
    test('true when overlay X is left of field', () {
      expect(
        fingerTrackedOverlayWouldClamp(
          overlayLocal: const Offset(-30, 5),
          fieldBounds: const Rect.fromLTWH(0, 0, 200, 100),
        ),
        isTrue,
      );
    });

    test('false when overlay is inside field', () {
      expect(
        fingerTrackedOverlayWouldClamp(
          overlayLocal: const Offset(50, 10),
          fieldBounds: const Rect.fromLTWH(0, 0, 200, 100),
        ),
        isFalse,
      );
    });
  });

  group('fingerTrackedHandleFollowerDelta with field clamp', () {
    test('clamps overlay then subtracts leader', () {
      // Without a real RenderBox we assert the clamp helper used by the delta.
      const field = Rect.fromLTWH(0, 0, 200, 100);
      const rawOverlay = Offset(-30, 5);
      final clampedOverlay = clampFingerTrackedOverlayLocal(
        overlayLocal: rawOverlay,
        fieldBounds: field,
      );
      const leaderLocal = Offset(77, 2.6);
      expect(clampedOverlay - leaderLocal, const Offset(-77, 2.4));
    });
  });

  group('fingerTrackedEndpointAtIndex', () {
    test('single endpoint uses index 0 for fixedIndex 1', () {
      const endpoints = [TextSelectionPoint(Offset(10, 20), TextDirection.ltr)];
      expect(
        fingerTrackedEndpointAtIndex(endpoints: endpoints, endpointIndex: 1),
        endpoints.first,
      );
    });

    test('two endpoints preserves index', () {
      const endpoints = [
        TextSelectionPoint(Offset(10, 20), TextDirection.ltr),
        TextSelectionPoint(Offset(30, 40), TextDirection.ltr),
      ];
      expect(
        fingerTrackedEndpointAtIndex(endpoints: endpoints, endpointIndex: 1),
        endpoints.last,
      );
    });
  });

  group('pointerKindUsesFingerTrackedHandle', () {
    test('touch and stylus qualify', () {
      expect(
        pointerKindUsesFingerTrackedHandle(PointerDeviceKind.touch),
        isTrue,
      );
      expect(
        pointerKindUsesFingerTrackedHandle(PointerDeviceKind.stylus),
        isTrue,
      );
    });

    test('mouse qualifies on Android (scrcpy)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        pointerKindUsesFingerTrackedHandle(PointerDeviceKind.mouse),
        isTrue,
      );
    });

    test('mouse does not qualify on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        pointerKindUsesFingerTrackedHandle(PointerDeviceKind.mouse),
        isFalse,
      );
    });

    test('mouse does not qualify on macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        pointerKindUsesFingerTrackedHandle(PointerDeviceKind.mouse),
        isFalse,
      );
    });
  });

  group('compensatedHandleHitTestDx', () {
    test('uses pointer + grabOffset on X', () {
      expect(
        compensatedHandleHitTestDx(
          pointerGlobal: const Offset(100, 200),
          grabOffset: const Offset(-20, -20),
        ),
        80,
      );
    });

    test('matches caret anchor X at drag start', () {
      const pointer = Offset(100, 200);
      const caret = Offset(80, 180);
      final grab = computeHandleGrabOffset(
        pointerGlobal: pointer,
        caretAnchorGlobal: caret,
      );
      expect(
        compensatedHandleHitTestDx(pointerGlobal: pointer, grabOffset: grab),
        caret.dx,
      );
    });
  });

  group('fingerTrackedExtentEndpointIndex', () {
    test('extent right of fixed base → extent at end', () {
      expect(
        fingerTrackedExtentEndpointIndex(
          fixedBase: 6257,
          extentOffset: 6266,
          grabbedHandle: FingerTrackedMovingHandle.end,
        ),
        1,
      );
      expect(
        fingerTrackedFixedBaseEndpointIndex(
          fixedBase: 6257,
          extentOffset: 6266,
          grabbedHandle: FingerTrackedMovingHandle.end,
        ),
        0,
      );
    });

    test('extent left of fixed base after invert → extent at start', () {
      expect(
        fingerTrackedExtentEndpointIndex(
          fixedBase: 10,
          extentOffset: 3,
          grabbedHandle: FingerTrackedMovingHandle.end,
        ),
        0,
      );
      expect(
        fingerTrackedFixedBaseEndpointIndex(
          fixedBase: 10,
          extentOffset: 3,
          grabbedHandle: FingerTrackedMovingHandle.end,
        ),
        1,
      );
    });

    // Post-reverse END DOWN — fixedBase == extentOffset.
    test('equal offsets + grab end → moving at end, fixed at start', () {
      expect(
        fingerTrackedExtentEndpointIndex(
          fixedBase: 43,
          extentOffset: 43,
          grabbedHandle: FingerTrackedMovingHandle.end,
        ),
        1,
      );
      expect(
        fingerTrackedFixedBaseEndpointIndex(
          fixedBase: 43,
          extentOffset: 43,
          grabbedHandle: FingerTrackedMovingHandle.end,
        ),
        0,
      );
    });

    test('equal offsets + grab start → moving at start, fixed at end', () {
      expect(
        fingerTrackedExtentEndpointIndex(
          fixedBase: 48,
          extentOffset: 48,
          grabbedHandle: FingerTrackedMovingHandle.start,
        ),
        0,
      );
      expect(
        fingerTrackedFixedBaseEndpointIndex(
          fixedBase: 48,
          extentOffset: 48,
          grabbedHandle: FingerTrackedMovingHandle.start,
        ),
        1,
      );
    });
  });

  group('fingerTrackedFixedBaseLeader', () {
    test('unchanged scroll keeps snapshot leader', () {
      const snapshot = Offset(104.9, 121.4);
      const live = Offset(104.9, 145.4);
      expect(
        fingerTrackedFixedBaseLeader(
          snapshotLeader: snapshot,
          liveLeader: live,
          snapshotScrollPixels: 120,
          currentScrollPixels: 120,
        ),
        snapshot,
      );
    });

    test('scroll change uses live fixed-base leader', () {
      const snapshot = Offset(104.9, 121.4);
      const live = Offset(104.9, 745.4);
      expect(
        fingerTrackedFixedBaseLeader(
          snapshotLeader: snapshot,
          liveLeader: live,
          snapshotScrollPixels: 120,
          currentScrollPixels: 480,
        ),
        live,
      );
    });
  });

  group('fingerTrackedFixedHandleDelta', () {
    test('start grab extend right pins end widget to fixed base leader', () {
      const physicalLeader = Offset(162.9, 110);
      const fixedLeader = Offset(104.9, 110);
      expect(
        fingerTrackedFixedHandleDelta(
          fixedBaseLeaderLocal: fixedLeader,
          physicalLeaderLocal: physicalLeader,
        ),
        fixedLeader - physicalLeader,
      );
    });

    test('snapshot fixed leader resists physical leader affinity jump', () {
      const snapshotLeader = Offset(255, 85);
      const jumpedPhysical = Offset(255, 109);
      expect(
        fingerTrackedFixedHandleDelta(
          fixedBaseLeaderLocal: snapshotLeader,
          physicalLeaderLocal: jumpedPhysical,
        ),
        const Offset(0, -24),
      );
    });
  });

  group('fingerTrackedSettleTargetDelta', () {
    test('start grab settle target is extent leader minus physical layer', () {
      const physicalLeader = Offset(104.9, 110);
      const extentLeader = Offset(177.1, 110);
      expect(
        fingerTrackedSettleTargetDelta(
          extentLeaderLocal: extentLeader,
          physicalLeaderLocal: physicalLeader,
        ),
        extentLeader - physicalLeader,
      );
    });
  });
}

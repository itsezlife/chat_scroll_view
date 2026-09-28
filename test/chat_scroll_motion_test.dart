import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_motion.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_physics.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_stretch_overscroll.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatScrollPhysics', () {
    test('android preset pairs the spline fling with stretch', () {
      const physics = ChatScrollPhysics.android();
      expect(physics.fling, const ChatFling.spline());
      expect(physics.edgeEffect, const ChatEdgeEffect.stretch());
    });

    test('is value-equal across instances', () {
      // Non-const on purpose: equality must not lean on const identity.
      // ignore: prefer_const_constructors
      final fling = ChatFling$Spline();
      // ignore: prefer_const_constructors
      final edgeEffect = ChatEdgeEffect$Stretch();
      final custom = ChatScrollPhysics(fling: fling, edgeEffect: edgeEffect);
      expect(custom, const ChatScrollPhysics.android());
      expect(custom.hashCode, const ChatScrollPhysics.android().hashCode);
    });

    test('differs when any parameter differs', () {
      const android = ChatScrollPhysics.android();
      expect(
        const ChatScrollPhysics(
          fling: ChatFling.spline(friction: 0.03),
          edgeEffect: ChatEdgeEffect.stretch(),
        ),
        isNot(android),
      );
      expect(
        const ChatScrollPhysics(
          fling: ChatFling.spline(),
          edgeEffect: ChatEdgeEffect.stretch(intensity: 0.03),
        ),
        isNot(android),
      );
      expect(
        const ChatScrollPhysics(
          fling: ChatFling.spline(),
          edgeEffect: ChatEdgeEffect.stretch(dampingRatio: 0.5),
        ),
        isNot(android),
      );
    });
  });

  group('ChatFlingMotion', () {
    double travel(ChatFlingMotion motion, double velocity) {
      motion.startFling(velocity);
      var elapsed = Duration.zero;
      var total = 0.0;
      while (motion.isFlinging) {
        elapsed += const Duration(milliseconds: 16);
        total += motion.tickFling(elapsed);
      }
      return total;
    }

    test('spline friction tunes travel distance', () {
      final standard = travel(ChatFlingMotion(), 3000);
      final heavy = travel(
        ChatFlingMotion(const ChatFling.spline(friction: 0.03)),
        3000,
      );
      expect(
        standard,
        closeTo(ChatSplineFlingSimulation(velocity: 3000).distance, 0.5),
      );
      expect(
        heavy,
        closeTo(
          ChatSplineFlingSimulation(velocity: 3000, friction: 0.03).distance,
          0.5,
        ),
      );
      expect(heavy, lessThan(standard));
    });
  });

  group('ChatScrollMotion', () {
    test('android physics runs a stretch edge effect', () {
      final motion = ChatScrollMotion(const ChatScrollPhysics.android());
      expect(motion.physics, const ChatScrollPhysics.android());
      expect(motion.edge, isA<ChatStretchOverscroll>());
      expect(motion.fling.isFlinging, isFalse);
    });
  });

  group('stretch edge effect contract', () {
    test('claim passes reverse motion through and starts the release', () {
      final stretch = ChatStretchOverscroll()..pull(400, 800);
      expect(stretch.overscroll, greaterThan(0));
      expect(stretch.claim(-10, travel: 10), -10);
      expect(stretch.isSpringing, isTrue);
    });

    test('claim leaves motion toward the pressed edge alone', () {
      final stretch = ChatStretchOverscroll()..pull(400, 800);
      expect(stretch.claim(10, travel: 10), 10);
      expect(stretch.isSpringing, isFalse);
    });

    test('claim does not release on sub-pixel travel into content', () {
      final stretch = ChatStretchOverscroll()..pull(400, 800);
      expect(stretch.claim(-0.5, travel: 0.5), -0.5);
      expect(stretch.isSpringing, isFalse);
    });

    test('claim does not release when reverse motion spills past a pin', () {
      // Short content: no travel either way, so the reverse delta lands as
      // pull at the opposite edge instead.
      final stretch = ChatStretchOverscroll()..pull(400, 800);
      expect(stretch.claim(-10, travel: 0), -10);
      expect(stretch.isSpringing, isFalse);
    });

    test('claim at rest is a pass-through', () {
      final stretch = ChatStretchOverscroll();
      expect(stretch.claim(-10, travel: 10), -10);
      expect(stretch.isActive, isFalse);
    });

    test('onDragEnd answers whether a content fling may start', () {
      expect(ChatStretchOverscroll().onDragEnd(2000), isTrue);
      expect(
        (ChatStretchOverscroll()..pull(-400, 800)).onDragEnd(4000),
        isTrue,
        reason: 'reverse velocity clears the stretch so content can fling',
      );
      expect(
        (ChatStretchOverscroll()..pull(-400, 800)).onDragEnd(-4000),
        isFalse,
        reason: 'same-direction velocity absorbs into the stretch',
      );
      expect(
        (ChatStretchOverscroll()..pull(-400, 800)).onDragEnd(0),
        isFalse,
        reason: 'a soft release springs back from the stretch',
      );
    });

    test('paintTransform is null at rest', () {
      expect(
        ChatStretchOverscroll().paintTransform(const Size(400, 800)),
        isNull,
      );
    });

    test('paintTransform scales from the pressed edge', () {
      const size = Size(400, 800);
      final top = ChatStretchOverscroll()..pull(400, 800);
      final topMatrix = top.paintTransform(size)!;
      expect(MatrixUtils.transformPoint(topMatrix, Offset.zero).dy, 0);
      expect(
        MatrixUtils.transformPoint(topMatrix, const Offset(0, 100)).dy,
        closeTo(100 * (1 + top.overscroll), 1e-9),
      );

      final bottom = ChatStretchOverscroll()..pull(-400, 800);
      final bottomMatrix = bottom.paintTransform(size)!;
      expect(
        MatrixUtils.transformPoint(bottomMatrix, const Offset(0, 800)).dy,
        closeTo(800, 1e-9),
      );
      expect(
        MatrixUtils.transformPoint(bottomMatrix, const Offset(0, 700)).dy,
        closeTo(800 - 100 * (1 + bottom.overscroll.abs()), 1e-9),
      );
    });

    test('onDragStart during a spring freezes the stretch in place', () {
      final stretch = ChatStretchOverscroll()..pull(400, 800);
      stretch
        ..onDragEnd(0)
        ..tick(const Duration(milliseconds: 16))
        ..tick(const Duration(milliseconds: 48));
      expect(stretch.isSpringing, isTrue);
      final frozen = stretch.overscroll;
      stretch.onDragStart();
      expect(stretch.isSpringing, isFalse);
      expect(stretch.tick(const Duration(milliseconds: 240)), isFalse);
      expect(stretch.overscroll, frozen);
      expect(stretch.isActive, isTrue);
    });

    test('intensity tunes the pull response', () {
      final standard = ChatStretchOverscroll()..pull(400, 800);
      final doubled = ChatStretchOverscroll(
        const ChatEdgeEffect$Stretch(intensity: 0.032),
      )..pull(400, 800);
      expect(doubled.overscroll, closeTo(standard.overscroll * 2, 1e-9));
    });
  });
}

import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_rubber_band_overscroll.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_motion.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_physics.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_stretch_overscroll.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatScrollPhysics', () {
    test('stretch preset pairs the spline fling with stretch', () {
      const physics = ChatScrollPhysics.stretch();
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
      expect(custom, const ChatScrollPhysics.stretch());
      expect(custom.hashCode, const ChatScrollPhysics.stretch().hashCode);
    });

    test('differs when any parameter differs', () {
      const stretch = ChatScrollPhysics.stretch();
      expect(
        const ChatScrollPhysics(
          fling: ChatFling.spline(friction: 0.03),
          edgeEffect: ChatEdgeEffect.stretch(),
        ),
        isNot(stretch),
      );
      expect(
        const ChatScrollPhysics(
          fling: ChatFling.spline(),
          edgeEffect: ChatEdgeEffect.stretch(intensity: 0.03),
        ),
        isNot(stretch),
      );
      expect(
        const ChatScrollPhysics(
          fling: ChatFling.spline(),
          edgeEffect: ChatEdgeEffect.stretch(dampingRatio: 0.5),
        ),
        isNot(stretch),
      );
    });

    test('rubber-band preset pairs the decay fling with rubber-band', () {
      const physics = ChatScrollPhysics.rubberBand();
      expect(physics.fling, const ChatFling.decay());
      expect(physics.edgeEffect, const ChatEdgeEffect.rubberBand());
    });

    test('clamped preset pairs the spline fling with no edge effect', () {
      const physics = ChatScrollPhysics.clamped();
      expect(physics.fling, const ChatFling.spline());
      expect(physics.edgeEffect, const ChatEdgeEffect.none());
    });

    test('new variants are value-equal and parameter-sensitive', () {
      // ignore: prefer_const_constructors
      expect(ChatFling$Decay(), const ChatFling.decay());
      expect(
        const ChatFling.decay(decelerationRate: 0.99),
        isNot(const ChatFling.decay()),
      );
      // ignore: prefer_const_constructors
      expect(ChatEdgeEffect$RubberBand(), const ChatEdgeEffect.rubberBand());
      expect(
        const ChatEdgeEffect.rubberBand(resistance: 0.3),
        isNot(const ChatEdgeEffect.rubberBand()),
      );
      // ignore: prefer_const_constructors
      expect(ChatEdgeEffect$None(), const ChatEdgeEffect.none());
      expect(
        const ChatEdgeEffect.none(),
        isNot(const ChatEdgeEffect.rubberBand()),
      );
    });

    test('platform default follows the OS family', () {
      const expected = <TargetPlatform, ChatScrollPhysics>{
        TargetPlatform.android: ChatScrollPhysics.stretch(),
        TargetPlatform.fuchsia: ChatScrollPhysics.stretch(),
        TargetPlatform.iOS: ChatScrollPhysics.rubberBand(),
        TargetPlatform.macOS: ChatScrollPhysics.rubberBand(),
        TargetPlatform.windows: ChatScrollPhysics.clamped(),
        TargetPlatform.linux: ChatScrollPhysics.clamped(),
      };
      for (final MapEntry(key: platform, value: physics) in expected.entries) {
        expect(
          ChatScrollPhysics.forPlatform(platform: platform),
          physics,
          reason: '$platform',
        );
      }
    });

    test('platform default reads the target platform when not pinned', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        ChatScrollPhysics.forPlatform(),
        const ChatScrollPhysics.rubberBand(),
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

    test('decay travels as far as the ideal friction curve', () {
      final normal = travel(ChatFlingMotion(const ChatFling.decay()), 3000);
      final ideal = FrictionSimulation(0.135, 0, 3000).finalX;
      // The tail below the stop velocity is dropped: v / ln(1 / drag) px.
      expect(normal, lessThan(ideal));
      expect(normal, closeTo(ideal, 6));
    });

    test('decay ends once speed falls below 10 px/s', () {
      final motion = ChatFlingMotion(const ChatFling.decay())..startFling(3000);
      var elapsed = Duration.zero;
      motion.tickFling(elapsed);
      while (motion.isFlinging) {
        elapsed += const Duration(milliseconds: 1);
        motion.tickFling(elapsed);
      }
      // 3000 · 0.135^t = 10  ⇒  t = ln(300) / ln(1 / 0.135) ≈ 2.85 s.
      final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
      expect(seconds, closeTo(math.log(300) / math.log(1 / 0.135), 0.01));
    });

    test('decay deceleration rate tunes travel', () {
      final normal = travel(ChatFlingMotion(const ChatFling.decay()), 3000);
      final fast = travel(
        ChatFlingMotion(const ChatFling.decay(decelerationRate: 0.99)),
        3000,
      );
      expect(fast, lessThan(normal / 3));
    });

    test('decay velocity decays by the rate per millisecond', () {
      final motion = ChatFlingMotion(const ChatFling.decay())
        ..startFling(3000)
        ..tickFling(Duration.zero);
      expect(motion.flingVelocity(Duration.zero), closeTo(3000, 1e-6));
      expect(
        motion.flingVelocity(const Duration(seconds: 1)),
        closeTo(3000 * 0.135, 3000 * 0.001),
      );
    });
  });

  group('ChatScrollMotion', () {
    test('stretch physics runs a stretch edge effect', () {
      final motion = ChatScrollMotion(const ChatScrollPhysics.stretch());
      expect(motion.physics, const ChatScrollPhysics.stretch());
      expect(motion.edge, isA<ChatStretchOverscroll>());
      expect(motion.fling.isFlinging, isFalse);
    });

    test('rubber-band physics runs a rubber-band edge effect', () {
      final motion = ChatScrollMotion(const ChatScrollPhysics.rubberBand());
      expect(motion.edge, isA<ChatRubberBandOverscroll>());
      expect(motion.fling.fling, const ChatFling.decay());
    });

    test('clamped physics runs the no-overscroll state', () {
      final motion = ChatScrollMotion(const ChatScrollPhysics.clamped());
      expect(motion.edge, isA<ChatNoOverscroll>());
    });
  });

  group('none edge effect contract', () {
    test('never paints, never claims, always allows the fling', () {
      const none = ChatNoOverscroll();
      none
        ..onDragStart()
        ..pull(400, 800)
        ..absorbImpact(4000);
      expect(none.claim(-10, 800, travel: 10), -10);
      expect(none.isActive, isFalse);
      expect(none.isSpringing, isFalse);
      expect(none.tick(const Duration(milliseconds: 16)), isFalse);
      expect(none.paintTransform(const Size(400, 800)), isNull);
      expect(none.onDragEnd(-4000), isTrue);
    });
  });

  group('rubber-band edge effect contract', () {
    /// Ticks [band] at 60 Hz until its spring stops; returns the peak
    /// displacement magnitude seen on the way.
    double runSpring(ChatRubberBandOverscroll band) {
      var elapsed = Duration.zero;
      var peak = band.displacement.abs();
      while (band.tick(elapsed)) {
        peak = math.max(peak, band.displacement.abs());
        elapsed += const Duration(microseconds: 16667);
        expect(elapsed, lessThan(const Duration(seconds: 3)));
      }
      return peak;
    }

    test('pull translates with growing resistance', () {
      final small = ChatRubberBandOverscroll()..pull(100, 800);
      final large = ChatRubberBandOverscroll()..pull(400, 800);
      expect(small.displacement, greaterThan(0));
      expect(small.displacement, lessThan(100));
      expect(large.displacement, greaterThan(small.displacement));
      expect(
        large.displacement - small.displacement,
        lessThan(small.displacement * 3),
        reason:
            'the second 300 px of pull move less than three times the '
            'first 100 px',
      );
      expect(large.displacement, lessThan(800));
    });

    test('pull follows the band curve d·c·x / (d + c·x)', () {
      const c = 0.55;
      const d = 800.0;
      final band = ChatRubberBandOverscroll()..pull(-300, d);
      expect(band.displacement, closeTo(-(d * c * 300) / (d + c * 300), 1e-9));
    });

    test('pull is path-independent', () {
      final once = ChatRubberBandOverscroll()..pull(300, 800);
      final steps = ChatRubberBandOverscroll();
      for (var i = 0; i < 30; i++) {
        steps.pull(10, 800);
      }
      expect(steps.displacement, closeTo(once.displacement, 1e-9));
    });

    test('resistance tunes the pull response', () {
      final standard = ChatRubberBandOverscroll()..pull(300, 800);
      final stiff = ChatRubberBandOverscroll(
        const ChatEdgeEffect$RubberBand(resistance: 0.3),
      )..pull(300, 800);
      expect(stiff.displacement, lessThan(standard.displacement));
    });

    test('claim consumes reverse motion before content travels', () {
      final band = ChatRubberBandOverscroll()..pull(300, 800);
      final before = band.displacement;
      expect(band.claim(-50, 800, travel: 50), 0);
      expect(band.displacement, greaterThan(0));
      expect(band.displacement, lessThan(before));
      expect(band.isSpringing, isFalse);
    });

    test('claim returns the reverse motion left past the pin', () {
      final band = ChatRubberBandOverscroll()..pull(300, 800);
      expect(band.claim(-500, 800, travel: 500), closeTo(-200, 1e-9));
      expect(band.displacement, 0);
      expect(band.isActive, isFalse);
    });

    test('claim leaves motion toward the pressed edge alone', () {
      final band = ChatRubberBandOverscroll()..pull(300, 800);
      final before = band.displacement;
      expect(band.claim(10, 800, travel: 0), 10);
      expect(band.displacement, before);
    });

    test('claim at rest is a pass-through', () {
      expect(ChatRubberBandOverscroll().claim(-10, 800, travel: 10), -10);
    });

    test('onDragEnd at rest allows the content fling', () {
      expect(ChatRubberBandOverscroll().onDragEnd(3000), isTrue);
    });

    test('a still or outward release springs back and blocks the fling', () {
      for (final velocity in [-40.0, 0.0, 3000.0]) {
        final band = ChatRubberBandOverscroll()..pull(300, 800);
        expect(band.onDragEnd(velocity), isFalse, reason: 'v=$velocity');
        expect(band.isSpringing, isTrue);
        runSpring(band);
        expect(band.displacement, 0);
        expect(band.isActive, isFalse);
      }
    });

    test('a flick toward content keeps the displacement for the fling', () {
      final band = ChatRubberBandOverscroll()..pull(300, 800);
      final pulled = band.displacement;
      expect(band.onDragEnd(-3000), isTrue);
      expect(band.isSpringing, isFalse);
      expect(band.displacement, pulled);

      expect(band.claim(-100, 800, travel: 100), 0);
      expect(band.displacement, inExclusiveRange(0, pulled));
      expect(band.claim(-1000, 800, travel: 1000), inExclusiveRange(-1000, 0));
      expect(band.isActive, isFalse);
    });

    test('an outward release launches at the layer speed, not the finger', () {
      final band = ChatRubberBandOverscroll()..pull(300, 800);
      final pulled = band.displacement;
      // Band slope at displacement b: c · ((d − b) / d)².
      final slope = 0.55 * math.pow((800 - pulled) / 800, 2);
      expect(band.onDragEnd(3000), isFalse);
      band
        ..tick(Duration.zero)
        ..tick(const Duration(milliseconds: 1));
      final launch = (band.displacement - pulled) / 0.001;
      expect(launch, closeTo(slope * 3000, slope * 3000 * 0.05));
    });

    test('a spring starts at the previous frame, never a stale one', () {
      final band = ChatRubberBandOverscroll()..pull(300, 800);
      final pulled = band.displacement;
      band
        ..tick(const Duration(milliseconds: 1000))
        ..onDragEnd(0)
        ..tick(const Duration(milliseconds: 1016));
      expect(band.displacement, lessThan(pulled), reason: 'one frame in');

      final restarted = ChatRubberBandOverscroll()..pull(300, 800);
      restarted
        ..tick(const Duration(seconds: 5))
        ..onDragEnd(0)
        ..tick(Duration.zero);
      expect(restarted.displacement, pulled, reason: 'ticker restarted');

      final idled = ChatRubberBandOverscroll()..pull(300, 800);
      idled
        ..tick(Duration.zero)
        ..onDragEnd(0)
        ..tick(const Duration(seconds: 2));
      expect(idled.displacement, pulled, reason: 'ticker idled');
    });

    test('the return from a still release is critically damped', () {
      expect(const ChatEdgeEffect$RubberBand().dampingRatio, 1);
      final band = ChatRubberBandOverscroll()..pull(300, 800);
      band.onDragEnd(0);
      var elapsed = Duration.zero;
      while (band.tick(elapsed)) {
        elapsed += const Duration(microseconds: 16667);
      }
      // (1 + ωt)·e^(−ωt) from ~146 px to 0.5 px at ω = √200.
      expect(elapsed, lessThan(const Duration(milliseconds: 600)));
    });

    test('a faster impact always bounces further', () {
      final peaks = [
        for (final v in [3000.0, 5500.0, 8000.0])
          runSpring(ChatRubberBandOverscroll()..absorbImpact(v)),
      ];
      expect(peaks[1], greaterThan(peaks[0] * 1.5));
      expect(peaks[2], greaterThan(peaks[1] * 1.3));
    });

    test('the return never crosses rest into the opposite edge', () {
      final band = ChatRubberBandOverscroll(
        const ChatEdgeEffect$RubberBand(dampingRatio: 0.3),
      )..pull(300, 800);
      band.onDragEnd(0);
      var elapsed = Duration.zero;
      while (band.tick(elapsed)) {
        expect(band.displacement, greaterThanOrEqualTo(0));
        elapsed += const Duration(microseconds: 16667);
      }
      expect(band.displacement, 0);
    });

    test('absorbImpact overshoots by leftover velocity, then settles', () {
      final slow = ChatRubberBandOverscroll()..absorbImpact(1000);
      final fast = ChatRubberBandOverscroll()..absorbImpact(4000);
      final slowPeak = runSpring(slow);
      final fastPeak = runSpring(fast);
      expect(slowPeak, greaterThan(1));
      expect(fastPeak, greaterThan(slowPeak));
      expect(fast.displacement, 0);
    });

    test('absorbImpact moves toward the pin it hit', () {
      final bottom = ChatRubberBandOverscroll()..absorbImpact(-3000);
      bottom
        ..tick(Duration.zero)
        ..tick(const Duration(milliseconds: 50));
      expect(bottom.displacement, lessThan(0));
    });

    test('absorbImpact ignores a near-zero leftover velocity', () {
      final band = ChatRubberBandOverscroll()..absorbImpact(10);
      expect(band.isActive, isFalse);
    });

    test('onDragStart during a spring freezes the displacement', () {
      final band = ChatRubberBandOverscroll()..pull(300, 800);
      band
        ..onDragEnd(0)
        ..tick(Duration.zero)
        ..tick(const Duration(milliseconds: 48));
      final frozen = band.displacement;
      band.onDragStart();
      expect(band.isSpringing, isFalse);
      expect(band.tick(const Duration(milliseconds: 240)), isFalse);
      expect(band.displacement, frozen);
      expect(band.isActive, isTrue);
    });

    test('a caught displacement resumes on the same curve', () {
      final caught = ChatRubberBandOverscroll()..pull(300, 800);
      caught
        ..onDragStart()
        ..pull(100, 800);
      final straight = ChatRubberBandOverscroll()..pull(400, 800);
      expect(caught.displacement, closeTo(straight.displacement, 1e-9));
    });

    test('reset drops the displacement and the spring', () {
      final band = ChatRubberBandOverscroll()
        ..pull(300, 800)
        ..onDragEnd(0)
        ..reset();
      expect(band.isActive, isFalse);
      expect(band.paintTransform(const Size(400, 800)), isNull);
    });

    test('paintTransform translates the message layer', () {
      final band = ChatRubberBandOverscroll()..pull(-300, 800);
      final matrix = band.paintTransform(const Size(400, 800))!;
      expect(
        MatrixUtils.transformPoint(matrix, const Offset(10, 700)),
        Offset(10, 700 + band.displacement),
      );
    });
  });

  group('stretch edge effect contract', () {
    test('a spring starts at the previous frame, never a stale one', () {
      final stretch = ChatStretchOverscroll()..pull(400, 800);
      final pulled = stretch.overscroll;
      stretch
        ..tick(const Duration(milliseconds: 1000))
        ..onDragEnd(0)
        ..tick(const Duration(milliseconds: 1016));
      expect(stretch.overscroll, lessThan(pulled), reason: 'one frame in');

      final restarted = ChatStretchOverscroll()..pull(400, 800);
      restarted
        ..tick(const Duration(seconds: 5))
        ..onDragEnd(0)
        ..tick(Duration.zero);
      expect(restarted.overscroll, pulled, reason: 'ticker restarted');
    });

    test('claim passes reverse motion through and starts the release', () {
      final stretch = ChatStretchOverscroll()..pull(400, 800);
      expect(stretch.overscroll, greaterThan(0));
      expect(stretch.claim(-10, 800, travel: 10), -10);
      expect(stretch.isSpringing, isTrue);
    });

    test('claim leaves motion toward the pressed edge alone', () {
      final stretch = ChatStretchOverscroll()..pull(400, 800);
      expect(stretch.claim(10, 800, travel: 10), 10);
      expect(stretch.isSpringing, isFalse);
    });

    test('claim does not release on sub-pixel travel into content', () {
      final stretch = ChatStretchOverscroll()..pull(400, 800);
      expect(stretch.claim(-0.5, 800, travel: 0.5), -0.5);
      expect(stretch.isSpringing, isFalse);
    });

    test('claim does not release when reverse motion spills past a pin', () {
      // Short content: no travel either way, so the reverse delta lands as
      // pull at the opposite edge instead.
      final stretch = ChatStretchOverscroll()..pull(400, 800);
      expect(stretch.claim(-10, 800, travel: 0), -10);
      expect(stretch.isSpringing, isFalse);
    });

    test('claim at rest is a pass-through', () {
      final stretch = ChatStretchOverscroll();
      expect(stretch.claim(-10, 800, travel: 10), -10);
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

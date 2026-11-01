import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:chat_wallpaper/src/motion/freeform_keyframes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'keyframes_harness.dart';

const _wallpaper = ChatWallpaper$Freeform(
  ui.Color(0xFF2D4836),
  ui.Color(0xFF172B19),
  ui.Color(0xFF364331),
  ui.Color(0xFF103231),
);

const _perStep = FreeformKeyframes.perStep;
const _ringLength = FreeformKeyframes.ringLength;

Uint8List _keyframe(int phase, int third) => FreeformGradient.pixels(
  _wallpaper,
  phase: phase,
  progress: third / _perStep,
);

FreeformKeyframes _keyframes({
  required int from,
  int steps = 0,
  bool warmsRing = true,
}) {
  final keyframes = FreeformKeyframes(
    _wallpaper,
    from: from,
    steps: steps,
    warmsRing: warmsRing,
  );
  addTearDown(keyframes.dispose);
  return keyframes;
}

Future<Uint8List> _bytes(WidgetTester tester, ui.Image image) async {
  final data = await tester.runAsync(image.toByteData);
  return data!.buffer.asUint8List();
}

/// Keyframes that land from now on, in landing order, one entry per
/// notification.
List<Set<Arrangement>> _landings(FreeformKeyframes keyframes) {
  final landings = <Set<Arrangement>>[];
  var seen = heldBy(keyframes);
  keyframes.addListener(() {
    final held = heldBy(keyframes);
    landings.add(held.difference(seen));
    seen = held;
  });
  return landings;
}

/// Ring distance of [arrangement] from phase [from] settled, in keyframes,
/// whichever way round is shorter.
int _distance(Arrangement arrangement, {required int from}) {
  final ahead =
      (_perStep * ((from - arrangement.phase) % FreeformGradient.phaseCount) -
          (_perStep - arrangement.third)) %
      _ringLength;
  return math.min(ahead, _ringLength - ahead);
}

void main() {
  group('FreeformKeyframes', () {
    test(
      'keyframe bytes are deterministic per phase and distinct within a step',
      () {
        for (var phase = 0; phase < FreeformGradient.phaseCount; phase++) {
          final frames = [
            for (var third = 0; third <= _perStep; third++)
              _keyframe(phase, third),
          ];

          for (var i = 0; i < frames.length; i++) {
            expect(
              _keyframe(phase, i),
              frames[i],
              reason: 'phase $phase, keyframe $i',
            );
            for (var j = i + 1; j < frames.length; j++) {
              expect(
                listEquals(frames[i], frames[j]),
                isFalse,
                reason: 'phase $phase, keyframes $i and $j',
              );
            }
          }
        }
      },
    );

    test('each step starts on the settled frame of the phase it leaves', () {
      for (var phase = 0; phase < FreeformGradient.phaseCount; phase++) {
        final left = (phase + 1) % FreeformGradient.phaseCount;

        expect(
          _keyframe(phase, 0),
          _keyframe(left, _perStep),
          reason: 'phase $phase',
        );
      }
    });

    testWidgets(
      'a settled strip has nothing to paint until its frame lands, then only that',
      (tester) async {
        final keyframes = _keyframes(from: 2);
        expect(keyframes.frameAt(phase: 2, progress: 1), isNull);

        await decode(
          tester,
          () => keyframes.frameAt(phase: 2, progress: 1) != null,
        );

        final frame = keyframes.frameAt(phase: 2, progress: 1)!;
        expect(frame.overlay, isNull);
        expect(
          await _bytes(tester, frame.base),
          FreeformGradient.pixels(_wallpaper, phase: 2),
        );
      },
    );

    testWidgets('a run from the held settled frame starts on that image', (
      tester,
    ) async {
      final keyframes = _keyframes(from: 0);
      await decode(
        tester,
        () => keyframes.frameAt(phase: 0, progress: 1) != null,
      );
      final settled = keyframes.frameAt(phase: 0, progress: 1)!.base;

      keyframes.run(from: 0, steps: 1);

      expect(keyframes.frameAt(phase: 7, progress: 0)?.base, same(settled));
      expect(settled.debugDisposed, isFalse);
    });

    testWidgets(
      'paints the nearest earlier frame alone until a gap in the strip lands',
      (tester) async {
        final keyframes = _keyframes(from: 0, warmsRing: false);
        await decode(
          tester,
          () => keyframes.frameAt(phase: 0, progress: 1) != null,
        );
        final settled = keyframes.frameAt(phase: 0, progress: 1)!.base;

        keyframes.run(from: 0, steps: 1);

        final frame = keyframes.frameAt(phase: 7, progress: 0.5)!;
        expect(frame.base, same(settled));
        expect(frame.overlay, isNull);
      },
    );

    testWidgets('crossfades neighbouring keyframes once the step has landed', (
      tester,
    ) async {
      final keyframes = _keyframes(from: 0);
      await decode(
        tester,
        () => keyframes.frameAt(phase: 0, progress: 1) != null,
      );
      keyframes.run(from: 0, steps: 1);
      await decode(
        tester,
        () => keyframes.frameAt(phase: 7, progress: 0.5)?.overlay != null,
      );

      final frame = keyframes.frameAt(phase: 7, progress: 0.5)!;
      expect(frame.overlayOpacity, closeTo(0.5, 1e-9));
      expect(await _bytes(tester, frame.base), _keyframe(7, 1));
      expect(await _bytes(tester, frame.overlay!), _keyframe(7, 2));
    });

    testWidgets(
      'holds every step of a run from its start and shares step boundaries',
      (tester) async {
        final keyframes = _keyframes(from: 0, steps: 4);
        await decode(
          tester,
          () => keyframes.frameAt(phase: 4, progress: 0.9)?.overlay != null,
        );

        final boundary = keyframes.frameAt(phase: 6, progress: 0)!;
        expect(boundary.overlay, isNull);
        expect(
          boundary.base,
          same(keyframes.frameAt(phase: 7, progress: 1)!.base),
        );

        final frame = keyframes.frameAt(phase: 5, progress: 0.5)!;
        expect(frame.overlayOpacity, closeTo(0.5, 1e-9));
        expect(await _bytes(tester, frame.base), _keyframe(5, 1));
        expect(await _bytes(tester, frame.overlay!), _keyframe(5, 2));
      },
    );

    testWidgets(
      'keeps the replaced frame on screen, and held, until the new strip lands',
      (tester) async {
        final keyframes = _keyframes(from: 0);
        await decode(
          tester,
          () => keyframes.frameAt(phase: 0, progress: 1) != null,
        );
        final before = keyframes.frameAt(phase: 0, progress: 1)!.base;

        keyframes.run(from: 4, steps: 0);
        expect(keyframes.frameAt(phase: 4, progress: 1)?.base, same(before));

        await decode(
          tester,
          () => !identical(
            keyframes.frameAt(phase: 4, progress: 1)?.base,
            before,
          ),
        );
        expect(before.debugDisposed, isFalse);
        expect(
          await _bytes(tester, keyframes.frameAt(phase: 4, progress: 1)!.base),
          FreeformGradient.pixels(_wallpaper, phase: 4),
        );
      },
    );

    testWidgets('keeps a frame that lands after its strip was replaced', (
      tester,
    ) async {
      final keyframes = _keyframes(from: 0, steps: 1)..run(from: 5, steps: 0);
      await decode(
        tester,
        () => keyframes.frameAt(phase: 5, progress: 1) != null,
      );

      keyframes.run(from: 0, steps: 0);

      final frame = keyframes.frameAt(phase: 0, progress: 1)!;
      expect(frame.overlay, isNull);
      expect(
        await _bytes(tester, frame.base),
        FreeformGradient.pixels(_wallpaper),
      );
    });

    testWidgets(
      'a full-ring strip crossfades through its lap boundary on one shared frame',
      (tester) async {
        const ring = FreeformGradient.phaseCount;
        final keyframes = _keyframes(from: 0, steps: ring);
        await decode(
          tester,
          () =>
              [
                for (var phase = 0; phase < ring; phase++)
                  keyframes.frameAt(phase: phase, progress: 0.5)?.overlay,
              ].nonNulls.length ==
              ring,
        );

        final lapStart = keyframes.frameAt(phase: 7, progress: 0)!;
        final lapEnd = keyframes.frameAt(phase: 0, progress: 1)!;
        expect(lapStart.overlay, isNull);
        expect(lapEnd.overlay, isNull);
        expect(lapEnd.base, same(lapStart.base));
        expect(
          await _bytes(tester, lapEnd.base),
          FreeformGradient.pixels(_wallpaper),
        );

        final lastStep = keyframes.frameAt(phase: 0, progress: 0.5)!;
        expect(lastStep.overlayOpacity, closeTo(0.5, 1e-9));
        expect(await _bytes(tester, lastStep.base), _keyframe(0, 1));
        expect(await _bytes(tester, lastStep.overlay!), _keyframe(0, 2));
      },
    );

    testWidgets('keeps every frame of the run it played after settling', (
      tester,
    ) async {
      final keyframes = _keyframes(from: 4, steps: 1);
      await decode(
        tester,
        () => keyframes.frameAt(phase: 3, progress: 0.5)?.overlay != null,
      );
      final start = keyframes.frameAt(phase: 3, progress: 0)!.base;
      final intermediate = keyframes.frameAt(phase: 3, progress: 0.5)!;
      final last = keyframes.frameAt(phase: 3, progress: 1)!.base;

      keyframes
        ..settle(phase: 3)
        ..run(from: 3, steps: FreeformGradient.phaseCount);

      for (final image in [
        start,
        intermediate.base,
        intermediate.overlay!,
        last,
      ]) {
        expect(image.debugDisposed, isFalse);
      }
      final replayed = keyframes.frameAt(phase: 3, progress: 0.5)!;
      expect(replayed.base, same(intermediate.base));
      expect(replayed.overlay, same(intermediate.overlay));
      expect(keyframes.frameAt(phase: 4, progress: 1)?.base, same(start));
    });

    testWidgets(
      'warms the whole ring one frame at a time, nearest the settled phase first',
      (tester) async {
        final keyframes = _keyframes(from: 2);
        final landings = _landings(keyframes);

        await decode(tester, () => heldBy(keyframes).length == _ringLength);

        expect(landings, everyElement(hasLength(1)));
        final order = [for (final landed in landings) landed.single];
        expect(order, hasLength(_ringLength));
        expect(order.take(3), [
          (phase: 2, third: 3),
          (phase: 1, third: 1),
          (phase: 2, third: 2),
        ]);
        final distances = [
          for (final arrangement in order) _distance(arrangement, from: 2),
        ];
        expect(distances, orderedEquals([...distances]..sort()));
      },
    );

    testWidgets(
      "moves a run's missing frames ahead of the ring, in playing order",
      (tester) async {
        const steps = ChatWallpaperMotionController.swirlSteps;
        final keyframes = _keyframes(from: 0);
        final landings = _landings(keyframes);
        // Once the settled frame lands, before anything else does.
        var started = false;
        keyframes.addListener(() {
          if (started) return;
          started = true;
          keyframes.run(from: 0, steps: steps);
        });

        await decode(tester, () => heldBy(keyframes).length == _ringLength);

        final strip = [
          for (var step = 1; step <= steps; step++)
            for (var third = 1; third <= _perStep; third++)
              (phase: -step % FreeformGradient.phaseCount, third: third),
        ];
        final afterStart = [for (final landed in landings.skip(1)) ...landed];
        expect(afterStart.take(strip.length), strip);
      },
    );

    testWidgets(
      'holds only the settled frame and warms nothing while ring warming is off',
      (tester) async {
        final keyframes = _keyframes(from: 2, warmsRing: false);
        await decode(tester, () => keyframes.holds(phase: 2, third: _perStep));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );

        expect(heldBy(keyframes), {(phase: 2, third: _perStep)});

        keyframes.warmsRing = true;
        await decode(tester, () => heldBy(keyframes).length == _ringLength);
      },
    );

    testWidgets(
      'turning ring warming off releases every frame but the resting one',
      (tester) async {
        final keyframes = _keyframes(from: 4, steps: 1);
        await decode(tester, () => heldBy(keyframes).length == _ringLength);
        final start = keyframes.frameAt(phase: 3, progress: 0)!.base;
        final last = keyframes.frameAt(phase: 3, progress: 1)!.base;

        keyframes
          ..settle(phase: 3)
          ..warmsRing = false;

        expect(heldBy(keyframes), {(phase: 3, third: _perStep)});
        expect(start.debugDisposed, isTrue);
        expect(last.debugDisposed, isFalse);
      },
    );

    group('with ring warming off', () {
      testWidgets(
        'settling a full-ring strip keeps only the frame of the phase it rests at',
        (tester) async {
          final keyframes = _keyframes(
            from: 0,
            steps: FreeformGradient.phaseCount,
            warmsRing: false,
          );
          await decode(tester, () => heldBy(keyframes).length == _ringLength);
          final origin = keyframes.frameAt(phase: 0, progress: 1)!.base;
          final rest = keyframes.frameAt(phase: 5, progress: 1)!.base;

          keyframes.settle(phase: 5);

          expect(origin.debugDisposed, isTrue);
          expect(rest.debugDisposed, isFalse);
          final frame = keyframes.frameAt(phase: 5, progress: 0.5)!;
          expect(frame.base, same(rest));
          expect(frame.overlay, isNull);
        },
      );

      testWidgets(
        'settling before the final frame lands keeps only that frame once it does',
        (tester) async {
          final keyframes = _keyframes(from: 4, steps: 1, warmsRing: false)
            ..settle(phase: 3);

          await decode(
            tester,
            () => keyframes.holds(phase: 3, third: _perStep),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );

          final last = keyframes.frameAt(phase: 3, progress: 1)!.base;
          expect(
            await _bytes(tester, last),
            FreeformGradient.pixels(_wallpaper, phase: 3),
          );
          expect(heldBy(keyframes), {(phase: 3, third: _perStep)});
          for (final progress in [0.0, 0.5]) {
            final frame = keyframes.frameAt(phase: 3, progress: progress)!;
            expect(frame.base, same(last), reason: 'progress $progress');
            expect(frame.overlay, isNull, reason: 'progress $progress');
          }
        },
      );

      testWidgets('settling releases every frame but the final one', (
        tester,
      ) async {
        final keyframes = _keyframes(from: 4, steps: 1, warmsRing: false);
        await decode(tester, () => heldBy(keyframes).length == _perStep + 1);
        final start = keyframes.frameAt(phase: 3, progress: 0)!.base;
        final intermediate = keyframes.frameAt(phase: 3, progress: 0.5)!.base;
        final last = keyframes.frameAt(phase: 3, progress: 1)!.base;

        keyframes.settle(phase: 3);

        expect(start.debugDisposed, isTrue);
        expect(intermediate.debugDisposed, isTrue);
        expect(last.debugDisposed, isFalse);
        expect(keyframes.frameAt(phase: 3, progress: 1)?.base, same(last));
      });
    });

    testWidgets('disposes every held image and ignores a second dispose', (
      tester,
    ) async {
      final keyframes = FreeformKeyframes(_wallpaper, from: 1, warmsRing: true);
      await decode(
        tester,
        () => keyframes.frameAt(phase: 1, progress: 1) != null,
      );
      final image = keyframes.frameAt(phase: 1, progress: 1)!.base;

      keyframes
        ..dispose()
        ..dispose();

      expect(image.debugDisposed, isTrue);
    });

    testWidgets(
      'disposes the frame on its way when disposed mid-warming, once it lands',
      (tester) async {
        final live = <ui.Image>{};
        var created = 0;
        void track(ObjectEvent event) {
          switch (event) {
            case ObjectCreated(object: final ui.Image image):
              live.add(image);
              created++;
            case ObjectDisposed(object: final ui.Image image):
              live.remove(image);
            default:
          }
        }

        FlutterMemoryAllocations.instance.addListener(track);
        addTearDown(
          () => FlutterMemoryAllocations.instance.removeListener(track),
        );
        final keyframes = FreeformKeyframes(
          _wallpaper,
          from: 0,
          warmsRing: true,
        );
        await decode(tester, () => heldBy(keyframes).length >= 3);
        final held = heldBy(keyframes).length;

        keyframes.dispose();
        // The frame on its way is the one image created beyond those held.
        await decode(tester, () => created > held);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );

        expect(live, isEmpty);
      },
    );
  });
}

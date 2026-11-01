import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:chat_wallpaper/src/motion/freeform_keyframes.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../motion/keyframes_harness.dart';
import 'drawn_images_harness.dart';

const _sage = ChatWallpaper$Freeform(
  Color(0xFFDBDDBB),
  Color(0xFF6BA587),
  Color(0xFFD5D88D),
  Color(0xFF88B884),
);
const _deepGreen = ChatWallpaper$Freeform(
  Color(0xFF2D4836),
  Color(0xFF172B19),
  Color(0xFF364331),
  Color(0xFF103231),
);

Widget _host(ChatWallpaper wallpaper) => Directionality(
  textDirection: TextDirection.ltr,
  child: ChatWallpaperView(wallpaper: wallpaper),
);

Finder _fill(Color color) => find.byWidgetPredicate(
  (widget) => widget is ColoredBox && widget.color == color,
);

LinearGradient _gradient(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byType(ChatWallpaperView),
      matching: find.byType(DecoratedBox),
    ),
  );
  return switch (box.decoration) {
    BoxDecoration(gradient: final LinearGradient gradient) => gradient,
    final decoration => fail('Expected a linear gradient, got $decoration'),
  };
}

/// Alternates real time for the engine's decode steps with fake-zone pumps
/// that deliver each step, until the view shows its image.
Future<void> _rasterize(WidgetTester tester) async {
  for (
    var step = 0;
    step < 20 && find.byType(RawImage).evaluate().isEmpty;
    step++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

void main() {
  group('ChatWallpaperView', () {
    testWidgets('fills its constraints behind a repaint boundary', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_sage));

      expect(
        tester.getSize(find.byType(ChatWallpaperView)),
        tester.view.physicalSize / tester.view.devicePixelRatio,
      );
      expect(
        find.descendant(
          of: find.byType(ChatWallpaperView),
          matching: find.byType(RepaintBoundary),
        ),
        findsOneWidget,
      );
    });

    testWidgets('paints the freeform average colour until the image is ready', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_sage));

      expect(_fill(_sage.averageColor), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
    });

    testWidgets(
      'draws the freeform image cover-fit with bilinear filtering once ready',
      (tester) async {
        await tester.pumpWidget(_host(_sage));
        await _rasterize(tester);

        final raw = tester.widget<RawImage>(find.byType(RawImage));
        expect(raw.image?.width, FreeformGradient.width);
        expect(raw.image?.height, FreeformGradient.height);
        expect(raw.fit, BoxFit.cover);
        expect(raw.filterQuality, FilterQuality.low);
        expect(_fill(_sage.averageColor), findsNothing);
      },
    );

    testWidgets('disposes the freeform image when removed', (tester) async {
      await tester.pumpWidget(_host(_sage));
      await _rasterize(tester);
      final image = tester.widget<RawImage>(find.byType(RawImage)).image;

      await tester.pumpWidget(const SizedBox.shrink());

      expect(image?.debugDisposed, isTrue);
    });

    testWidgets('crossfades over crossfadeDuration when the value changes', (
      tester,
    ) async {
      const oneMs = Duration(milliseconds: 1);
      await tester.pumpWidget(_host(_sage));

      await tester.pumpWidget(_host(_deepGreen));
      // First tick: the switcher's animation starts here.
      await tester.pump();
      await tester.pump(ChatWallpaperView.crossfadeDuration - oneMs);

      expect(_fill(_sage.averageColor), findsOneWidget);
      expect(_fill(_deepGreen.averageColor), findsOneWidget);

      // Controllers dismiss only once strictly past their duration.
      await tester.pump(oneMs * 2);
      await tester.pump();

      expect(_fill(_sage.averageColor), findsNothing);
      expect(_fill(_deepGreen.averageColor), findsOneWidget);
    });

    testWidgets('keeps its image when rebuilt with an equal value', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_sage));
      await _rasterize(tester);
      final image = tester.widget<RawImage>(find.byType(RawImage)).image;

      await tester.pumpWidget(
        _host(
          // Non-const: equal by value, not identical.
          ChatWallpaper.freeform(
            const Color(0xFFDBDDBB),
            const Color(0xFF6BA587),
            const Color(0xFFD5D88D),
            Color(int.parse('FF88B884', radix: 16)),
          ),
        ),
      );

      expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(image));
      expect(_fill(_sage.averageColor), findsNothing);
    });

    testWidgets('paints a solid wallpaper as its opaque colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ChatWallpaper.solid(Color(0x330A1B2C))),
      );

      expect(_fill(const Color(0xFF0A1B2C)), findsOneWidget);
      expect(find.byType(DecoratedBox), findsNothing);
    });

    testWidgets('paints a linear wallpaper as an opaque two-colour gradient', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ChatWallpaper.linear(Color(0x80FFFFFF), Color(0xFF000000))),
      );

      final gradient = _gradient(tester);
      expect(gradient.colors, const [Color(0xFFFFFFFF), Color(0xFF000000)]);
      expect(gradient.stops, isNull);
      expect(find.byType(ColoredBox), findsNothing);
    });

    group('with a motion controller', () {
      late ChatWallpaperMotionController motion;

      setUp(
        () => motion = ChatWallpaperMotionController(vsync: const TestVSync()),
      );
      tearDown(() => motion.dispose());

      // Copies of one wallpaper, like a background and a fade over it.
      Widget copies(
        ChatWallpaper wallpaper, {
        List<String> keys = const ['a', 'b'],
      }) => Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            for (final key in keys)
              Expanded(
                child: ChatWallpaperView(
                  key: Key(key),
                  wallpaper: wallpaper,
                  motion: motion,
                ),
              ),
          ],
        ),
      );
      Widget pair(ChatWallpaper wallpaper) => copies(wallpaper);

      List<DrawnImage> imagesOf(WidgetTester tester, String key) =>
          drawnImages(tester, find.byKey(Key(key)));

      /// Delivers decodes until [done] holds.
      Future<void> decode(WidgetTester tester, bool Function() done) async {
        for (var step = 0; step < 300 && !done(); step++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(done(), isTrue, reason: 'decodes did not land');
      }

      Future<Uint8List> bytesOf(WidgetTester tester, DrawnImage drawn) async {
        final data = await tester.runAsync(drawn.image.toByteData);
        return data!.buffer.asUint8List();
      }

      testWidgets(
        'paints the average colour until the settled frame is ready',
        (tester) async {
          await tester.pumpWidget(pair(_sage));

          for (final key in ['a', 'b']) {
            expect(
              find.byKey(Key(key)),
              paints..rect(color: _sage.averageColor),
            );
          }
          await decode(tester, () => imagesOf(tester, 'a').isNotEmpty);
          expect(
            find.byKey(const Key('a')),
            isNot(paints..rect(color: _sage.averageColor)),
          );
        },
      );

      testWidgets(
        'paints one shared image per copy at rest, rendered at the current phase',
        (tester) async {
          await tester.pumpWidget(pair(_sage));
          await decode(tester, () => imagesOf(tester, 'a').isNotEmpty);

          final [a] = imagesOf(tester, 'a');
          final [b] = imagesOf(tester, 'b');
          final box = tester.getSize(find.byKey(const Key('a')));
          expect(a.image, same(b.image));
          expect(a.opacity, 1);
          expect(a.filterQuality, FilterQuality.low);
          // Cover-fit: fills the whole box from a centred crop of the raster.
          expect(a.destination, Offset.zero & box);
          expect(
            a.source.width / a.source.height,
            closeTo(box.width / box.height, 1e-9),
          );
          expect(
            a.source.center,
            const Offset(
              FreeformGradient.width / 2,
              FreeformGradient.height / 2,
            ),
          );
          expect(await bytesOf(tester, a), FreeformGradient.pixels(_sage));
        },
      );

      testWidgets(
        'crossfades shared neighbouring keyframes during a shift, then settles',
        (tester) async {
          await tester.pumpWidget(pair(_sage));
          await decode(tester, () => imagesOf(tester, 'a').isNotEmpty);

          motion.advance();
          await tester.pump();
          await tester.pump(ChatWallpaperMotionController.shiftDuration ~/ 2);
          await decode(tester, () => imagesOf(tester, 'a').length == 2);

          final position = motion.progress * FreeformKeyframes.perStep;
          final segment = position.floor();
          final [aBase, aOverlay] = imagesOf(tester, 'a');
          final [bBase, bOverlay] = imagesOf(tester, 'b');
          expect(aBase.image, same(bBase.image));
          expect(aOverlay.image, same(bOverlay.image));
          expect(aBase.opacity, 1);
          expect(aOverlay.opacity, closeTo(position - segment, 1e-6));
          expect(bOverlay.opacity, aOverlay.opacity);
          expect(
            await bytesOf(tester, aOverlay),
            FreeformGradient.pixels(
              _sage,
              phase: 7,
              progress: (segment + 1) / FreeformKeyframes.perStep,
            ),
          );

          await tester.pump(ChatWallpaperMotionController.shiftDuration);
          await decode(tester, () => imagesOf(tester, 'a').length == 1);
          final [settled] = imagesOf(tester, 'a');
          expect(
            await bytesOf(tester, settled),
            FreeformGradient.pixels(_sage, phase: 7),
          );
        },
      );

      testWidgets('shows a new picture on every frame of a shift', (
        tester,
      ) async {
        Future<Uint8List> shown() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find
                .descendant(
                  of: find.byKey(const Key('a')),
                  matching: find.byType(RepaintBoundary),
                )
                .first,
          );
          final bytes = await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData();
            image.dispose();
            return data!.buffer.asUint8List();
          });
          return bytes!;
        }

        await tester.pumpWidget(copies(_sage, keys: const ['a']));
        await decode(tester, () => imagesOf(tester, 'a').isNotEmpty);
        motion.advance();
        await tester.pump();
        // Nothing lands while the screen is read back.
        await decode(tester, () => holdsRing(motion, _sage));

        const frame = Duration(milliseconds: 16);
        var previous = await shown();
        var position = motion.progress * FreeformKeyframes.perStep;
        var compared = 0;
        for (
          var elapsed = frame;
          elapsed < ChatWallpaperMotionController.shiftDuration;
          elapsed += frame
        ) {
          await tester.pump(frame);
          final current = await shown();
          final next = motion.progress * FreeformKeyframes.perStep;
          // Below this the crossfade may not move any pixel by a whole level.
          if (next - position > 0.02) {
            expect(
              current,
              isNot(previous),
              reason: 'at $elapsed, keyframe position $next',
            );
            compared++;
          }
          (previous, position) = (current, next);
        }
        expect(compared, greaterThan(10));

        await tester.pump(ChatWallpaperMotionController.shiftDuration);
      });

      testWidgets('paints every frame of a swirl from its strip of keyframes', (
        tester,
      ) async {
        const perStep = FreeformKeyframes.perStep;
        const duration = ChatWallpaperMotionController.swirlDuration;
        await tester.pumpWidget(pair(_sage));
        await decode(tester, () => imagesOf(tester, 'a').isNotEmpty);

        motion.swirl();
        await tester.pump();
        // Real time for the keyframes; fake time stays at the swirl's first
        // frame, and nothing is delivered after this.
        await decode(tester, () => holdsRing(motion, _sage));

        // Thirds of a step into the swirl each painted image shows.
        final thirdsOf = <ui.Image, int>{};
        const frame = Duration(milliseconds: 16);
        var frames = 0;
        for (var elapsed = frame; elapsed < duration; elapsed += frame) {
          await tester.pump(frame);
          final stepsIn = -motion.phase % FreeformGradient.phaseCount;
          final position = (stepsIn - 1 + motion.progress) * perStep;
          final thirds = position.floor();
          final opacity = position - thirds;
          final reason = 'at $elapsed';

          final a = imagesOf(tester, 'a');
          final b = imagesOf(tester, 'b');
          expect(a, hasLength(opacity > 0 ? 2 : 1), reason: reason);
          expect(b, hasLength(a.length), reason: reason);
          for (var i = 0; i < a.length; i++) {
            expect(a[i].image, same(b[i].image), reason: reason);
            expect(
              thirdsOf.putIfAbsent(a[i].image, () => thirds + i),
              thirds + i,
              reason: reason,
            );
          }
          if (a case [_, final overlay]) {
            expect(overlay.opacity, closeTo(opacity, 1e-6), reason: reason);
            expect(b.last.opacity, overlay.opacity, reason: reason);
          }
          frames++;
        }
        expect(frames, greaterThan(100));
        expect(
          thirdsOf.values.toSet(),
          hasLength(ChatWallpaperMotionController.swirlSteps * perStep + 1),
        );

        for (final MapEntry(key: image, value: thirds) in thirdsOf.entries) {
          final step = (thirds / perStep).ceil();
          final data = await tester.runAsync(image.toByteData);
          expect(
            data!.buffer.asUint8List(),
            FreeformGradient.pixels(
              _sage,
              phase: -step % FreeformGradient.phaseCount,
              progress: thirds / perStep - step + 1,
            ),
            reason: '$thirds thirds into the swirl',
          );
        }

        await tester.pump(duration);
      });

      testWidgets('paints a spin across its lap boundary from the ring', (
        tester,
      ) async {
        const perStep = FreeformKeyframes.perStep;
        const ring = FreeformGradient.phaseCount;
        await tester.pumpWidget(pair(_sage));
        await decode(tester, () => imagesOf(tester, 'a').isNotEmpty);

        final hold = motion.holdSpin();
        await tester.pump();
        // Real time for the keyframes; fake time stays at the spin's first
        // frame, and nothing is delivered after this.
        await decode(tester, () => holdsRing(motion, _sage));

        // Thirds of a step back from the lap start each painted image shows;
        // the ring's first and last frames are one image, counted as 0.
        final thirdsOf = <ui.Image, int>{};
        const frame = Duration(milliseconds: 40);
        final lap = ChatWallpaperMotionController.spinStepDuration * ring;
        var lapsCrossed = 0;
        for (var elapsed = frame; elapsed < lap * 1.5; elapsed += frame) {
          final phaseBefore = motion.phase;
          await tester.pump(frame);
          if (phaseBefore != 0 && motion.phase == 0) lapsCrossed++;
          final stepsIn = switch (-motion.phase % ring) {
            0 => ring,
            final steps => steps,
          };
          final position = (stepsIn - 1 + motion.progress) * perStep;
          final thirds = position.floor();
          final opacity = position - thirds;
          final reason = 'at $elapsed';

          final a = imagesOf(tester, 'a');
          final b = imagesOf(tester, 'b');
          expect(a, hasLength(opacity > 0 ? 2 : 1), reason: reason);
          expect(b, hasLength(a.length), reason: reason);
          for (var i = 0; i < a.length; i++) {
            final expected = (thirds + i) % (ring * perStep);
            expect(a[i].image, same(b[i].image), reason: reason);
            expect(
              thirdsOf.putIfAbsent(a[i].image, () => expected),
              expected,
              reason: reason,
            );
          }
          if (a case [_, final overlay]) {
            expect(overlay.opacity, closeTo(opacity, 1e-6), reason: reason);
          }
        }
        expect(lapsCrossed, 1);
        expect(thirdsOf.values.toSet(), hasLength(ring * perStep));

        for (final MapEntry(key: image, value: thirds) in thirdsOf.entries) {
          final step = (thirds / perStep).ceil();
          final data = await tester.runAsync(image.toByteData);
          expect(
            data!.buffer.asUint8List(),
            FreeformGradient.pixels(
              _sage,
              phase: -step % ring,
              progress: thirds / perStep - step + 1,
            ),
            reason: '$thirds thirds back from the lap start',
          );
        }

        hold.release();
        await tester.pump();
        await tester.pump(ChatWallpaperMotionController.spinReturnDuration);
        expect(motion.isAnimating, isFalse);
        expect(imagesOf(tester, 'a'), hasLength(1));
      });

      testWidgets(
        'starts a shift, a swirl and a spin on a warm ring with a crossfade on their first frame',
        (tester) async {
          const frame = Duration(milliseconds: 16);
          await tester.pumpWidget(pair(_sage));
          // Real time for the whole ring; nothing is delivered after this.
          await decode(tester, () => holdsRing(motion, _sage));

          /// Pumps [length] of the run just started, frame by frame. Every
          /// frame paints held keyframes: between two keyframes a base with
          /// its neighbour crossfaded over it — from the first pumped frame on
          /// — and the same images in both copies. A keyframe the ring lacked
          /// would paint its nearest landed frame alone.
          Future<void> paintsFromRing(String run, Duration length) async {
            await tester.pump();
            for (var elapsed = frame; elapsed <= length; elapsed += frame) {
              await tester.pump(frame);
              final opacity = motion.progress * FreeformKeyframes.perStep % 1;
              final reason = '$run at $elapsed';
              if (elapsed == frame)
                expect(
                  opacity,
                  greaterThan(0),
                  reason: '$reason: first frame is between keyframes',
                );

              final a = imagesOf(tester, 'a');
              final b = imagesOf(tester, 'b');
              expect(a, hasLength(opacity > 0 ? 2 : 1), reason: reason);
              expect(b, hasLength(a.length), reason: reason);
              for (var i = 0; i < a.length; i++) {
                expect(b[i].image, same(a[i].image), reason: reason);
              }
              if (a case [_, final overlay])
                expect(overlay.opacity, closeTo(opacity, 1e-6), reason: reason);
            }
          }

          expect(motion.advance(), isTrue);
          await paintsFromRing(
            'shift',
            ChatWallpaperMotionController.shiftDuration,
          );
          await tester.pump(ChatWallpaperMotionController.shiftDuration);

          expect(motion.swirl(), isTrue);
          await paintsFromRing(
            'swirl',
            ChatWallpaperMotionController.swirlDuration,
          );
          await tester.pump(ChatWallpaperMotionController.swirlDuration);

          final hold = motion.holdSpin();
          await paintsFromRing(
            'spin',
            ChatWallpaperMotionController.spinStepDuration * 2,
          );
          hold.release();
          await tester.pump();
          await tester.pump(ChatWallpaperMotionController.spinReturnDuration);
          expect(motion.isAnimating, isFalse);
        },
      );

      testWidgets(
        'a copy that starts painting mid-swirl paints the same images',
        (tester) async {
          await tester.pumpWidget(copies(_sage, keys: const ['a']));
          await decode(tester, () => imagesOf(tester, 'a').isNotEmpty);
          motion.swirl();
          await tester.pump();
          await tester.pump(ChatWallpaperMotionController.swirlDuration * 0.4);
          await decode(tester, () => imagesOf(tester, 'a').length == 2);

          await tester.pumpWidget(pair(_sage));

          final a = imagesOf(tester, 'a');
          final b = imagesOf(tester, 'b');
          expect(b, hasLength(2));
          expect(b.first.image, same(a.first.image));
          expect(b.last.image, same(a.last.image));
          expect(b.last.opacity, a.last.opacity);

          await tester.pump(ChatWallpaperMotionController.swirlDuration);
        },
      );

      testWidgets(
        'a wallpaper first painted mid-swirl crossfades through the rest of it',
        (tester) async {
          await tester.pumpWidget(const SizedBox.shrink());
          motion.swirl();
          await tester.pump();
          await tester.pump(ChatWallpaperMotionController.swirlDuration * 0.3);

          await tester.pumpWidget(pair(_sage));
          await decode(tester, () => holdsRing(motion, _sage));

          while (motion.isAnimating && motion.progress < 1) {
            expect(
              imagesOf(tester, 'a'),
              hasLength(2),
              reason: 'phase ${motion.phase}, progress ${motion.progress}',
            );
            expect(
              imagesOf(tester, 'b').last.image,
              same(imagesOf(tester, 'a').last.image),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pump(ChatWallpaperMotionController.swirlDuration);
        },
      );

      testWidgets('disposes its keyframes once no copy paints the wallpaper', (
        tester,
      ) async {
        await tester.pumpWidget(pair(_sage));
        await decode(tester, () => imagesOf(tester, 'a').isNotEmpty);
        final image = imagesOf(tester, 'a').single.image;

        await tester.pumpWidget(copies(_sage, keys: const ['a']));
        expect(
          image.debugDisposed,
          isFalse,
          reason: 'one copy still paints the shared keyframes',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        expect(image.debugDisposed, isTrue);
      });
    });

    testWidgets(
      'orients a linear wallpaper from its first colour by rotation',
      (tester) async {
        const expected = {
          WallpaperRotation.deg0: (Alignment.topCenter, Alignment.bottomCenter),
          WallpaperRotation.deg45: (Alignment.topRight, Alignment.bottomLeft),
          WallpaperRotation.deg90: (
            Alignment.centerRight,
            Alignment.centerLeft,
          ),
          WallpaperRotation.deg135: (Alignment.bottomRight, Alignment.topLeft),
          WallpaperRotation.deg180: (
            Alignment.bottomCenter,
            Alignment.topCenter,
          ),
          WallpaperRotation.deg225: (Alignment.bottomLeft, Alignment.topRight),
          WallpaperRotation.deg270: (
            Alignment.centerLeft,
            Alignment.centerRight,
          ),
          WallpaperRotation.deg315: (Alignment.topLeft, Alignment.bottomRight),
        };
        expect(expected.keys, unorderedEquals(WallpaperRotation.values));

        for (final MapEntry(key: rotation, value: (begin, end))
            in expected.entries) {
          await tester.pumpWidget(
            _host(
              ChatWallpaper.linear(
                const Color(0xFFFFFFFF),
                const Color(0xFF000000),
                rotation: rotation,
              ),
            ),
          );
          await tester.pumpAndSettle();

          final gradient = _gradient(tester);
          expect(
            (gradient.begin, gradient.end),
            (begin, end),
            reason: '$rotation',
          );
        }
      },
    );
  });
}

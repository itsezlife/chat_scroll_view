import 'dart:typed_data';

import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:chat_wallpaper/chat_wallpaper_diagnostics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'drawn_images_harness.dart';
import 'pattern_harness.dart';

const _otherSlug = 'other';

const _artwork = {patternSlug: leftHalf, _otherSlug: leftHalf};

const _light = ChatWallpaper.patterned(
  ChatWallpaper$Solid(Color(0xFF808080)),
  WallpaperPattern(patternSlug),
);

/// Shares [_light]'s slug with another fill and blend.
const _dark = ChatWallpaper.patterned(
  ChatWallpaper$Solid(Color(0xFF303030)),
  WallpaperPattern(
    patternSlug,
    intensity: 57,
    blend: WallpaperPatternBlend.mask,
  ),
);

const _otherPattern = ChatWallpaper.patterned(
  ChatWallpaper$Solid(Color(0xFF808080)),
  WallpaperPattern(_otherSlug),
);

const _sage = ChatWallpaper$Freeform(
  Color(0xFFDBDDBB),
  Color(0xFF6BA587),
  Color(0xFFD5D88D),
  Color(0xFF88B884),
);

const _patternedSage = ChatWallpaper.patterned(
  _sage,
  WallpaperPattern(patternSlug),
);

/// [wallpapers] warmed above [child], in the 800 × 600 test screen.
Widget _warmUp(
  List<ChatWallpaper> wallpapers, {
  Widget child = const SizedBox.shrink(),
}) => patternsHost(
  ChatWallpaperWarmUp(wallpapers: wallpapers, child: child),
  artwork: _artwork,
);

/// Waits until the raster a view of [slug] would resolve has landed in the
/// cache. Only a wait condition: assertions go through what views paint.
Future<void> _landed(WidgetTester tester, String slug) => settle(
  tester,
  () => PaintingBinding.instance.imageCache
      .statusForKey(
        WallpaperPatternImage(slug: slug, artwork: leftHalf, width: 600),
      )
      .keepAlive,
);

/// Evicts every cached image nothing listens to, as cache pressure from
/// other images eventually would; live images stay.
void _evictUnheldImages() => PaintingBinding.instance.imageCache.clear();

void main() {
  group('ChatWallpaperWarmUp', () {
    setUp(pinDisplay);
    tearDown(clearImageCache);
    tearDown(resetDisplay);

    testWidgets(
      'lets a view mounted after the raster landed paint the pattern on its first frame',
      (tester) async {
        await tester.pumpWidget(_warmUp([_light]));
        await _landed(tester, patternSlug);

        await tester.pumpWidget(
          _warmUp([_light], child: const ChatWallpaperView(wallpaper: _light)),
        );

        expect(composited(tester), isTrue);
      },
    );

    testWidgets('keeps the raster through image cache pressure', (
      tester,
    ) async {
      await tester.pumpWidget(_warmUp([_light]));
      await _landed(tester, patternSlug);

      _evictUnheldImages();
      await tester.pumpWidget(
        _warmUp([_light], child: const ChatWallpaperView(wallpaper: _light)),
      );

      expect(composited(tester), isTrue);
    });

    testWidgets(
      'keeps a shared raster while any wallpaper using its slug stays listed',
      (tester) async {
        await tester.pumpWidget(_warmUp([_light, _dark]));
        await _landed(tester, patternSlug);

        await tester.pumpWidget(_warmUp([_dark]));
        _evictUnheldImages();
        await tester.pumpWidget(
          _warmUp([_dark], child: const ChatWallpaperView(wallpaper: _light)),
        );

        expect(composited(tester), isTrue);
      },
    );

    testWidgets(
      'releases a raster no longer listed, so a later view waits for it again',
      (tester) async {
        await tester.pumpWidget(_warmUp([_light]));
        await _landed(tester, patternSlug);

        await tester.pumpWidget(_warmUp(const []));
        _evictUnheldImages();
        await tester.pumpWidget(
          _warmUp(const [], child: const ChatWallpaperView(wallpaper: _light)),
        );

        expect(composited(tester), isFalse);
        await settle(tester, () => composited(tester));
      },
    );

    testWidgets('swaps to the raster of a newly listed pattern', (
      tester,
    ) async {
      await tester.pumpWidget(_warmUp([_light]));
      await _landed(tester, patternSlug);

      await tester.pumpWidget(_warmUp([_otherPattern]));
      await _landed(tester, _otherSlug);
      _evictUnheldImages();

      await tester.pumpWidget(
        _warmUp([
          _otherPattern,
        ], child: const ChatWallpaperView(wallpaper: _otherPattern)),
      );
      expect(
        composited(tester),
        isTrue,
        reason: 'the newly listed raster is live',
      );

      await tester.pumpWidget(
        _warmUp(
          [_otherPattern],
          child: const ChatWallpaperView(
            key: ValueKey('fresh'),
            wallpaper: _light,
          ),
        ),
      );
      expect(
        composited(tester),
        isFalse,
        reason: 'the unlisted raster was released',
      );
    });

    testWidgets('releases every raster when it leaves the tree', (
      tester,
    ) async {
      await tester.pumpWidget(_warmUp([_light]));
      await _landed(tester, patternSlug);

      await tester.pumpWidget(
        patternsHost(const SizedBox.shrink(), artwork: _artwork),
      );
      _evictUnheldImages();
      await tester.pumpWidget(
        patternsHost(
          const ChatWallpaperView(wallpaper: _light),
          artwork: _artwork,
        ),
      );

      expect(composited(tester), isFalse);
    });

    testWidgets('waits for a size before resolving, then warms the pattern', (
      tester,
    ) async {
      Widget warmUp(Size size) => MediaQuery(
        data: MediaQueryData(size: size),
        child: const ChatWallpaperPatterns(
          artwork: _artwork,
          child: ChatWallpaperWarmUp(
            wallpapers: [_light],
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpWidget(warmUp(Size.zero));
      await deliver(tester, steps: 5);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(warmUp(const Size(800, 600)));
      await _landed(tester, patternSlug);
    });

    testWidgets(
      'ignores wallpapers without a pattern or without registered artwork',
      (tester) async {
        await tester.pumpWidget(
          _warmUp(const [
            ChatWallpaper.solid(Color(0xFF808080)),
            ChatWallpaper.patterned(
              ChatWallpaper$Solid(Color(0xFF808080)),
              WallpaperPattern('unregistered'),
            ),
          ]),
        );
        await deliver(tester, steps: 5);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'still warms the pattern of a freeform fill without a motion scope above it',
      (tester) async {
        await tester.pumpWidget(_warmUp(const [_sage, _patternedSage]));
        await _landed(tester, patternSlug);

        await tester.pumpWidget(
          _warmUp(const [
            _sage,
            _patternedSage,
          ], child: const ChatWallpaperView(wallpaper: _patternedSage)),
        );

        expect(tester.takeException(), isNull);
        expect(composited(tester), isTrue);
      },
    );

    group('under a motion scope', () {
      /// [scopeChild] under a motion scope, in the 800 × 600 test screen.
      Widget scope(Widget scopeChild) => patternsHost(
        ChatWallpaperMotionScope(child: scopeChild),
        artwork: _artwork,
      );

      /// [wallpapers] warmed under a motion scope, above [child].
      Widget scoped(
        List<ChatWallpaper> wallpapers, {
        Widget child = const SizedBox.shrink(),
      }) => scope(ChatWallpaperWarmUp(wallpapers: wallpapers, child: child));

      /// A view of [wallpaper] moving with the scope's controller.
      Widget moving(ChatWallpaper wallpaper) => Builder(
        builder: (context) => ChatWallpaperView(
          wallpaper: wallpaper,
          motion: ChatWallpaperMotionScope.of(context),
        ),
      );

      ChatWallpaperMotionController motionOf(WidgetTester tester) =>
          ChatWallpaperMotionScope.of(
            tester.element(find.byType(ChatWallpaperWarmUp)),
          );

      /// Waits until the scope holds a paintable keyframe of [fill]. Only a
      /// wait condition: assertions go through what views paint.
      Future<void> keyframesLanded(
        WidgetTester tester,
        ChatWallpaper$Freeform fill,
      ) async {
        final motion = motionOf(tester);
        final keyframes = motion.acquireKeyframes(fill);
        try {
          await settle(
            tester,
            () =>
                keyframes.frameAt(
                  phase: motion.phase,
                  progress: motion.progress,
                ) !=
                null,
          );
        } finally {
          motion.releaseKeyframes(fill);
        }
      }

      final paintsAverageColor = paints..rect(color: _sage.averageColor);

      Future<Uint8List> paintedPixels(WidgetTester tester) async {
        final [drawn] = drawnImages(tester, find.byType(ChatWallpaperView));
        final data = await tester.runAsync(drawn.image.toByteData);
        return data!.buffer.asUint8List();
      }

      testWidgets(
        'lets a freeform view mounted after the keyframes landed paint the raster on its first frame',
        (tester) async {
          await tester.pumpWidget(scoped(const [_sage]));
          await keyframesLanded(tester, _sage);

          await tester.pumpWidget(scoped(const [_sage], child: moving(_sage)));

          expect(find.byType(ChatWallpaperView), isNot(paintsAverageColor));
          expect(await paintedPixels(tester), FreeformGradient.pixels(_sage));
        },
      );

      testWidgets('holds the keyframes of a patterned freeform fill too', (
        tester,
      ) async {
        await tester.pumpWidget(scoped(const [_patternedSage]));
        await _landed(tester, patternSlug);
        await keyframesLanded(tester, _sage);
        final rasters = ChatWallpaperDiagnostics.gradientRasters;

        await tester.pumpWidget(
          scoped(const [_patternedSage], child: moving(_patternedSage)),
        );

        expect(composited(tester), isTrue);
        expect(
          ChatWallpaperDiagnostics.gradientRasters,
          rasters,
          reason: 'the view paints the keyframes the warm-up holds',
        );
      });

      testWidgets(
        'follows a shift run with no view mounted, so a later view paints the phase it settled at',
        (tester) async {
          await tester.pumpWidget(scoped(const [_sage]));
          await keyframesLanded(tester, _sage);
          final motion = motionOf(tester);

          expect(motion.advance(), isTrue);
          await tester.pump();
          // Real time for the run's keyframes; fake time stays at its first frame.
          await deliver(tester, steps: 20);
          // Controllers complete only once strictly past their duration.
          await tester.pump(
            ChatWallpaperMotionController.shiftDuration +
                const Duration(milliseconds: 1),
          );
          expect(motion.isAnimating, isFalse);

          await tester.pumpWidget(scoped(const [_sage], child: moving(_sage)));

          expect(find.byType(ChatWallpaperView), isNot(paintsAverageColor));
          expect(
            await paintedPixels(tester),
            FreeformGradient.pixels(_sage, phase: motion.phase),
          );
          expect(
            motion.advance(),
            isTrue,
            reason: 'a held fill never blocks the next run',
          );
          await tester.pump(ChatWallpaperMotionController.shiftDuration * 2);
        },
      );

      testWidgets(
        'releases the keyframes of a fill no longer listed, so a later view waits for them again',
        (tester) async {
          await tester.pumpWidget(scoped(const [_sage]));
          await keyframesLanded(tester, _sage);

          await tester.pumpWidget(scoped(const []));
          await tester.pumpWidget(scoped(const [], child: moving(_sage)));

          expect(find.byType(ChatWallpaperView), paintsAverageColor);
          expect(drawnImages(tester, find.byType(ChatWallpaperView)), isEmpty);
        },
      );

      testWidgets(
        'keeps a shared hold while any wallpaper using the fill stays listed',
        (tester) async {
          await tester.pumpWidget(scoped(const [_sage, _patternedSage]));
          await keyframesLanded(tester, _sage);

          await tester.pumpWidget(scoped(const [_patternedSage]));
          await tester.pumpWidget(
            scoped(const [_patternedSage], child: moving(_sage)),
          );

          expect(find.byType(ChatWallpaperView), isNot(paintsAverageColor));
          expect(
            drawnImages(tester, find.byType(ChatWallpaperView)),
            hasLength(1),
          );
        },
      );

      testWidgets('moves its holds to the scope it is moved under', (
        tester,
      ) async {
        final hostKey = GlobalKey();
        // The same instance before and after the move, so only the move itself
        // can tell the host its scope changed.
        final host = ChatWallpaperWarmUp(
          key: hostKey,
          wallpapers: const [_sage],
          child: const SizedBox.shrink(),
        );
        // Two scopes; [host] sits under the first until [moved], then under
        // the second, keeping its state through [hostKey].
        Widget scopes({
          required bool moved,
          required Widget host,
          Widget firstView = const SizedBox.shrink(),
        }) => patternsHost(
          Column(
            children: [
              Expanded(
                child: ChatWallpaperMotionScope(
                  child: moved ? firstView : host,
                ),
              ),
              Expanded(
                child: ChatWallpaperMotionScope(
                  child: moved ? host : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
          artwork: _artwork,
        );

        await tester.pumpWidget(scopes(moved: false, host: host));
        await tester.pumpWidget(scopes(moved: true, host: host));
        await keyframesLanded(tester, _sage);

        await tester.pumpWidget(
          scopes(
            moved: true,
            host: ChatWallpaperWarmUp(
              key: hostKey,
              wallpapers: const [_sage],
              child: moving(_sage),
            ),
            firstView: moving(_sage),
          ),
        );

        final underHost = find.descendant(
          of: find.byType(ChatWallpaperWarmUp),
          matching: find.byType(ChatWallpaperView),
        );
        final underOldScope = find.descendant(
          of: find.byType(ChatWallpaperMotionScope).first,
          matching: find.byType(ChatWallpaperView),
        );
        expect(
          drawnImages(tester, underHost),
          hasLength(1),
          reason: 'the new scope holds the keyframes',
        );
        expect(
          underOldScope,
          paintsAverageColor,
          reason: 'the old scope no longer does',
        );
      });

      testWidgets('releases every keyframe hold when it leaves the tree', (
        tester,
      ) async {
        await tester.pumpWidget(scoped(const [_sage]));
        await keyframesLanded(tester, _sage);

        await tester.pumpWidget(scope(const SizedBox.shrink()));
        await tester.pumpWidget(scope(moving(_sage)));

        expect(find.byType(ChatWallpaperView), paintsAverageColor);
        expect(drawnImages(tester, find.byType(ChatWallpaperView)), isEmpty);
      });
    });
  });
}

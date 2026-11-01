import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _sage = ChatWallpaper.freeform(
  Color(0xFFDBDDBB),
  Color(0xFF6BA587),
  Color(0xFFD5D88D),
  Color(0xFF88B884),
);
const _deepGreen = ChatWallpaper.freeform(
  Color(0xFF2D4836),
  Color(0xFF172B19),
  Color(0xFF364331),
  Color(0xFF103231),
);

void main() {
  group('ChatWallpaper.averageColor', () {
    test('folds pairwise with integer halves for the sage freeform', () {
      expect(_sage.averageColor, const Color(0xFFA1C28D));
    });

    test('folds pairwise with integer halves for the deep-green freeform', () {
      expect(_deepGreen.averageColor, const Color(0xFF1D372D));
    });

    test('is opaque even when a colour carries alpha', () {
      const solid = ChatWallpaper.solid(Color(0x33112233));

      expect(solid.averageColor, const Color(0xFF112233));
    });

    test('weighs later colours more', () {
      const linear = ChatWallpaper.linear(Color(0xFF000000), Color(0xFFFEFEFE));

      expect(linear.averageColor, const Color(0xFF7F7F7F));
    });
  });

  group('ChatWallpaper.isDark', () {
    test('is false for the sage freeform', () {
      expect(_sage.isDark, isFalse);
    });

    test('is true for the deep-green freeform', () {
      expect(_deepGreen.isDark, isTrue);
    });
  });

  group('ChatWallpaper.colors', () {
    test('lists three freeform colours when the fourth is absent', () {
      const freeform = ChatWallpaper.freeform(
        Color(0xFF111111),
        Color(0xFF222222),
        Color(0xFF333333),
      );

      expect(freeform.colors, const [
        Color(0xFF111111),
        Color(0xFF222222),
        Color(0xFF333333),
      ]);
    });

    test('lists four freeform colours in declaration order', () {
      expect(_sage.colors, const [
        Color(0xFFDBDDBB),
        Color(0xFF6BA587),
        Color(0xFFD5D88D),
        Color(0xFF88B884),
      ]);
    });
  });

  group('ChatWallpaper.patterned', () {
    const pattern = WallpaperPattern(
      'doodles',
      intensity: 30,
      blend: WallpaperPatternBlend.mask,
    );
    const patterned = ChatWallpaper.patterned(
      ChatWallpaper$Freeform(
        Color(0xFF2D4836),
        Color(0xFF172B19),
        Color(0xFF364331),
        Color(0xFF103231),
      ),
      pattern,
    );

    test('takes its colour facts from the fill', () {
      expect(patterned.colors, _deepGreen.colors);
      expect(patterned.averageColor, _deepGreen.averageColor);
      expect(patterned.isDark, isTrue);
      expect(patterned.serviceTone, _deepGreen.serviceTone);
    });

    test('differs from its bare fill and from another pattern', () {
      expect(patterned, isNot(_deepGreen));
      expect(
        patterned,
        isNot(
          const ChatWallpaper.patterned(
            ChatWallpaper$Freeform(
              Color(0xFF2D4836),
              Color(0xFF172B19),
              Color(0xFF364331),
              Color(0xFF103231),
            ),
            WallpaperPattern(
              'doodles',
              intensity: 31,
              blend: WallpaperPatternBlend.mask,
            ),
          ),
        ),
      );
    });
  });

  group('ChatWallpaper.withoutPattern', () {
    test('leaves the fill under a soft-light pattern', () {
      const patterned = ChatWallpaper.patterned(
        _sage as ChatWallpaper$ColorFill,
        WallpaperPattern('doodles'),
      );

      expect(patterned.withoutPattern, _sage);
    });

    test('leaves black under a mask pattern', () {
      const patterned = ChatWallpaper.patterned(
        _deepGreen as ChatWallpaper$ColorFill,
        WallpaperPattern('doodles', blend: WallpaperPatternBlend.mask),
      );

      expect(
        patterned.withoutPattern,
        const ChatWallpaper.solid(Color(0xFF000000)),
      );
    });

    test('returns an unpatterned wallpaper as it is', () {
      expect(_sage.withoutPattern, same(_sage));
    });
  });

  group('ChatWallpaper.freeformFill', () {
    const freeform = ChatWallpaper$Freeform(
      Color(0xFFDBDDBB),
      Color(0xFF6BA587),
      Color(0xFFD5D88D),
    );

    test('is the freeform fill itself or under a pattern', () {
      expect(freeform.freeformFill, same(freeform));
      expect(
        const ChatWallpaper.patterned(
          freeform,
          WallpaperPattern('doodles'),
        ).freeformFill,
        same(freeform),
      );
    });

    test('is null for solid and linear fills, patterned or not', () {
      const solid = ChatWallpaper$Solid(Color(0xFF808080));
      for (final wallpaper in const <ChatWallpaper>[
        solid,
        ChatWallpaper$Linear(Color(0xFF808080), Color(0xFF404040)),
        ChatWallpaper$Patterned(solid, WallpaperPattern('doodles')),
      ]) {
        expect(wallpaper.freeformFill, isNull, reason: '$wallpaper');
      }
    });
  });

  group('WallpaperPattern', () {
    test('defaults to half-intensity soft light', () {
      const pattern = WallpaperPattern('doodles');

      expect(pattern.intensity, WallpaperPattern.defaultIntensity);
      expect(pattern.blend, WallpaperPatternBlend.softLight);
    });

    test('exposes its intensity as an opacity', () {
      expect(const WallpaperPattern('a', intensity: 0).opacity, 0);
      expect(const WallpaperPattern('a', intensity: 35).opacity, 0.35);
      expect(const WallpaperPattern('a', intensity: 100).opacity, 1);
    });
  });

  group('WallpaperRotation.fromDegrees', () {
    test('keeps aligned angles', () {
      for (final rotation in WallpaperRotation.values) {
        expect(WallpaperRotation.fromDegrees(rotation.degrees), rotation);
      }
    });

    test('snaps to the nearest 45° step', () {
      expect(WallpaperRotation.fromDegrees(22), WallpaperRotation.deg0);
      expect(WallpaperRotation.fromDegrees(23), WallpaperRotation.deg45);
      expect(WallpaperRotation.fromDegrees(200), WallpaperRotation.deg180);
      expect(WallpaperRotation.fromDegrees(337), WallpaperRotation.deg315);
    });

    test('wraps into [0, 360)', () {
      expect(WallpaperRotation.fromDegrees(338), WallpaperRotation.deg0);
      expect(WallpaperRotation.fromDegrees(360), WallpaperRotation.deg0);
      expect(WallpaperRotation.fromDegrees(405), WallpaperRotation.deg45);
      expect(WallpaperRotation.fromDegrees(-45), WallpaperRotation.deg315);
      expect(WallpaperRotation.fromDegrees(-90), WallpaperRotation.deg270);
    });
  });
}

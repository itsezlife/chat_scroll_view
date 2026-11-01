import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _freeform = ChatWallpaper$Freeform(
  Color(0xFFD7EDE6),
  Color(0xFF7FBFAE),
  Color(0xFFEAF2CC),
);
const _pattern = WallpaperPattern('doodle');
const _mask = WallpaperPattern(
  'doodle',
  intensity: 100,
  blend: WallpaperPatternBlend.mask,
);

const _softLight = WallpaperServiceShade(
  saturation: 1.6,
  scale: 0.92,
  offset: -0.06,
);
const _softDark = WallpaperServiceShade(
  saturation: 1.6,
  scale: 0.97,
  offset: 0.12,
);
const _maskLight = WallpaperServiceShade(
  saturation: 1.1,
  scale: 0.8,
  offset: -0.06,
);
const _maskDark = WallpaperServiceShade(
  saturation: 1.1,
  scale: 0.4,
  offset: 0.08,
);

void main() {
  group('WallpaperServiceShade.of', () {
    test('is null without a freeform fill', () {
      for (final wallpaper in const <ChatWallpaper>[
        ChatWallpaper$Solid(Color(0xFF808080)),
        ChatWallpaper$Linear(Color(0xFF808080), Color(0xFF404040)),
        ChatWallpaper$Patterned(ChatWallpaper$Solid(Color(0xFF808080)), _mask),
      ]) {
        expect(
          WallpaperServiceShade.of(wallpaper, darkTheme: false),
          isNull,
          reason: '$wallpaper',
        );
      }
    });

    test(
      'picks the soft coefficients for a plain or soft-light freeform fill',
      () {
        for (final wallpaper in const <ChatWallpaper>[
          _freeform,
          ChatWallpaper$Patterned(_freeform, _pattern),
        ]) {
          expect(
            WallpaperServiceShade.of(wallpaper, darkTheme: false),
            _softLight,
          );
          expect(
            WallpaperServiceShade.of(wallpaper, darkTheme: true),
            _softDark,
          );
        }
      },
    );

    test('picks the darker coefficients for a mask', () {
      const wallpaper = ChatWallpaper$Patterned(_freeform, _mask);
      expect(WallpaperServiceShade.of(wallpaper, darkTheme: false), _maskLight);
      expect(WallpaperServiceShade.of(wallpaper, darkTheme: true), _maskDark);
    });
  });

  group('WallpaperServiceShade.apply', () {
    // Grey is its own luminance, so saturation leaves it: 128 · scale + offset · 255.
    test('scales and offsets grey', () {
      const grey = Color(0xFF808080);
      expect(_softLight.apply(grey), const Color(0xFF666666)); // 102.46
      expect(_softDark.apply(grey), const Color(0xFF9B9B9B)); // 154.76
      expect(_maskLight.apply(grey), const Color(0xFF575757)); // 87.1
      expect(_maskDark.apply(grey), const Color(0xFF484848)); // 71.6
    });

    // L = 0.213·107 + 0.715·165 + 0.072·135 = 150.486; each channel moves 1.6×
    // away from it, then · 0.92 − 15.3.
    test('pushes colours away from grey before scaling', () {
      expect(
        _softLight.apply(const Color(0xFF6BA587)),
        const Color(0xFF3B9164),
      );
    });

    test('clamps and returns opaque colours', () {
      expect(_softDark.apply(const Color(0xFFFFFFFF)), const Color(0xFFFFFFFF));
      expect(
        _softLight.apply(const Color(0x00000000)),
        const Color(0xFF000000),
      );
    });

    // L = 0.3086·107 + 0.6094·165 + 0.082·135 = 144.641; each channel moves
    // 3.5× away from it, then · 0.75: 9.67, 161.92, 83.17.
    test('saturates around the luminance its weights define', () {
      const shade = WallpaperServiceShade(
        saturation: 3.5,
        scale: 0.75,
        offset: 0,
        luminance: WallpaperServiceShade.linearLuminance,
      );

      expect(shade.apply(const Color(0xFF6BA587)), const Color(0xFF0AA253));
    });
  });

  group('WallpaperServiceShade equality', () {
    test('tells shades apart by their luminance weights', () {
      const linear = WallpaperServiceShade(
        saturation: 1.6,
        scale: 0.92,
        offset: -0.06,
        luminance: WallpaperServiceShade.linearLuminance,
      );

      expect(linear, isNot(_softLight));
      expect(_softLight.luminance, WallpaperServiceShade.rec709Luminance);
    });
  });

  group('WallpaperServiceShade.matrixAt', () {
    test('keeps the colour rows and multiplies alpha by the opacity', () {
      final matrix = _softLight.matrix;

      expect(_softLight.matrixAt(0.75), [...matrix.take(15), 0, 0, 0, 0.75, 0]);
      expect(matrix.skip(15), [0, 0, 0, 1, 0]);
    });

    test('is the matrix at full opacity', () {
      expect(_maskDark.matrixAt(1), _maskDark.matrix);
    });
  });
}

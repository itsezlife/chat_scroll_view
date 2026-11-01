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

/// [ChatWallpaper.averageColor] of [_sage].
const _sageAverage = Color(0xFFA1C28D);

/// One 8-bit channel step: the tone is quantised back to [Color] channels.
const _channelStep = 1 / 255;

HSVColor _hsv(Color color) => HSVColor.fromColor(color.withValues(alpha: 1));

void main() {
  group('WallpaperServiceTone.fromColor', () {
    test('draws the background at alpha 0x66', () {
      final tone = WallpaperServiceTone.fromColor(const Color(0xFFA1C28D));

      expect((tone.background.a * 255).round(), 0x66);
    });

    test('keeps the foreground white', () {
      for (final color in const [
        Color(0xFF000000),
        Color(0xFFFFFFFF),
        Color(0xFFA1C28D),
        Color(0xFF1D372D),
      ]) {
        expect(
          WallpaperServiceTone.fromColor(color).foreground,
          const Color(0xFFFFFFFF),
        );
      }
    });

    test('keeps the hue of the source colour', () {
      const source = Color(0xFFA1C28D);

      final tone = WallpaperServiceTone.fromColor(source);

      expect(_hsv(tone.background).hue, closeTo(_hsv(source).hue, 1));
    });

    test('raises saturation by 0.05 + 0.1 * (1 - s)', () {
      const source = Color(0xFFA1C28D);
      final s = _hsv(source).saturation;

      final tone = WallpaperServiceTone.fromColor(source);

      expect(
        _hsv(tone.background).saturation,
        closeTo(s + 0.05 + 0.1 * (1 - s), 2 * _channelStep),
      );
    });

    test('lifts a grey to saturation 0.15', () {
      final tone = WallpaperServiceTone.fromColor(const Color(0xFF808080));

      expect(_hsv(tone.background).saturation, closeTo(0.15, 2 * _channelStep));
    });

    test('caps saturation at 1', () {
      final tone = WallpaperServiceTone.fromColor(const Color(0xFF00FF00));

      expect(_hsv(tone.background).saturation, 1);
    });

    test('scales HSV value by 0.65', () {
      const source = Color(0xFFA1C28D);

      final tone = WallpaperServiceTone.fromColor(source);

      expect(
        _hsv(tone.background).value,
        closeTo(_hsv(source).value * 0.65, _channelStep),
      );
    });

    test('truncates channels instead of rounding them', () {
      expect(
        WallpaperServiceTone.fromColor(_sage.averageColor).background,
        const Color(0x665F7E4C),
      );
      // Value 35.75 and blue 27.84 truncate; rounding would give 0x660F241C.
      expect(
        WallpaperServiceTone.fromColor(_deepGreen.averageColor).background,
        const Color(0x660F231B),
      );
      // Fractional channels (83.2, 70.72, 70.72) truncate; rounding would give 71.
      expect(
        WallpaperServiceTone.fromColor(
          const Color(0xFF808080),
        ).background.toARGB32(),
        0x66534646,
      );
    });

    test('ignores the source alpha', () {
      expect(
        WallpaperServiceTone.fromColor(const Color(0x33A1C28D)),
        WallpaperServiceTone.fromColor(const Color(0xFFA1C28D)),
      );
    });
  });

  group('ChatWallpaper.serviceTone', () {
    test('projects the average colour', () {
      expect(
        _sage.serviceTone,
        WallpaperServiceTone.fromColor(_sage.averageColor),
      );
      expect(
        _deepGreen.serviceTone,
        WallpaperServiceTone.fromColor(_deepGreen.averageColor),
      );
    });

    test('applies one formula to every fill kind', () {
      const wallpapers = <ChatWallpaper>[
        ChatWallpaper.solid(_sageAverage),
        ChatWallpaper.linear(
          Color(0xFFDBDDBB),
          Color(0xFF6BA587),
          rotation: WallpaperRotation.deg45,
        ),
        ChatWallpaper.freeform(
          Color(0xFF2D4836),
          Color(0xFF172B19),
          Color(0xFF364331),
        ),
      ];

      for (final wallpaper in wallpapers) {
        expect(
          wallpaper.serviceTone,
          WallpaperServiceTone.fromColor(wallpaper.averageColor),
        );
      }
      expect(
        ChatWallpaper.solid(_sage.averageColor).serviceTone,
        _sage.serviceTone,
      );
    });

    test('is deeper than the wallpaper it sits on', () {
      for (final wallpaper in const [_sage, _deepGreen]) {
        expect(
          _hsv(wallpaper.serviceTone.background).value,
          lessThan(_hsv(wallpaper.averageColor).value),
        );
      }
    });
  });
}

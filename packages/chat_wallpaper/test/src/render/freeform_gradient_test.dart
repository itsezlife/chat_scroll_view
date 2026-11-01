import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _threeColour = ChatWallpaper$Freeform(
  Color(0xFFDBDDBB),
  Color(0xFF6BA587),
  Color(0xFFD5D88D),
);
const _fourColour = ChatWallpaper$Freeform(
  Color(0xFF2D4836),
  Color(0xFF172B19),
  Color(0xFF364331),
  Color(0xFF103231),
);

const _pixelCount = FreeformGradient.width * FreeformGradient.height;

void main() {
  group('FreeformGradient.pixels', () {
    for (final (label, wallpaper) in [
      ('three colours', _threeColour),
      ('four colours', _fourColour),
    ]) {
      group('with $label', () {
        test('returns RGBA bytes for the whole grid', () {
          expect(
            FreeformGradient.pixels(wallpaper),
            hasLength(_pixelCount * 4),
          );
        });

        test('is deterministic byte for byte', () {
          expect(
            FreeformGradient.pixels(wallpaper),
            FreeformGradient.pixels(wallpaper),
          );
        });

        test(
          'is opaque and mixes only the wallpaper colours at every pixel of every phase',
          () {
            final colors = wallpaper.colors;
            final low = [
              for (final c in _channels)
                colors.map(c).reduce((a, b) => a < b ? a : b),
            ];
            final high = [
              for (final c in _channels)
                colors.map(c).reduce((a, b) => a > b ? a : b),
            ];

            for (var phase = 0; phase < FreeformGradient.phaseCount; phase++) {
              final bytes = FreeformGradient.pixels(wallpaper, phase: phase);
              for (var pixel = 0; pixel < _pixelCount; pixel++) {
                for (var channel = 0; channel < 3; channel++) {
                  final value = bytes[pixel * 4 + channel];
                  expect(
                    value,
                    inInclusiveRange(low[channel], high[channel]),
                    reason: 'phase $phase, pixel $pixel, channel $channel',
                  );
                }
                expect(
                  bytes[pixel * 4 + 3],
                  0xFF,
                  reason: 'phase $phase, pixel $pixel alpha',
                );
              }
            }
          },
        );

        test('differs between every pair of phases', () {
          final phases = [
            for (var phase = 0; phase < FreeformGradient.phaseCount; phase++)
              FreeformGradient.pixels(wallpaper, phase: phase),
          ];

          for (var a = 0; a < phases.length; a++) {
            for (var b = a + 1; b < phases.length; b++) {
              expect(
                listEquals(phases[a], phases[b]),
                isFalse,
                reason: 'phases $a and $b',
              );
            }
          }
        });

        test('starts each phase from the layout of the next one', () {
          for (var phase = 0; phase < FreeformGradient.phaseCount; phase++) {
            final previous = (phase + 1) % FreeformGradient.phaseCount;

            expect(
              FreeformGradient.pixels(wallpaper, phase: phase, progress: 0),
              FreeformGradient.pixels(wallpaper, phase: previous),
              reason: 'phase $phase at progress 0',
            );
          }
        });
      });
    }

    test('three and four colours differ', () {
      const withFourth = ChatWallpaper$Freeform(
        Color(0xFFDBDDBB),
        Color(0xFF6BA587),
        Color(0xFFD5D88D),
        Color(0xFF88B884),
      );

      expect(
        listEquals(
          FreeformGradient.pixels(_threeColour),
          FreeformGradient.pixels(withFourth),
        ),
        isFalse,
      );
    });
  });

  group('FreeformGradient.imageInBackground', () {
    for (final (label, wallpaper) in [
      ('three colours', _threeColour),
      ('four colours', _fourColour),
    ]) {
      for (final (phase, thirds) in [(0, 3), (3, 0), (5, 1), (7, 2)]) {
        final progress = thirds / 3;
        testWidgets(
          'matches the synchronous pixels with $label at phase $phase, progress $thirds/3',
          (tester) async {
            final bytes = await tester.runAsync(() async {
              final image = await FreeformGradient.imageInBackground(
                wallpaper,
                phase: phase,
                progress: progress,
              );
              try {
                expect(image.width, FreeformGradient.width);
                expect(image.height, FreeformGradient.height);
                final data = await image.toByteData();
                return data!.buffer.asUint8List();
              } finally {
                image.dispose();
              }
            });

            expect(
              bytes,
              FreeformGradient.pixels(
                wallpaper,
                phase: phase,
                progress: progress,
              ),
            );
          },
        );
      }
    }
  });
}

const List<int Function(Color)> _channels = [_red, _green, _blue];

int _red(Color color) => (color.toARGB32() >> 16) & 0xFF;

int _green(Color color) => (color.toARGB32() >> 8) & 0xFF;

int _blue(Color color) => color.toARGB32() & 0xFF;

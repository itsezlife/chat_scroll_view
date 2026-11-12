import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('keyboard cell', () {
    test('decodes the cell extent at the device density', () {
      final preset = AssetPresets.keyboardCell(extent: 34, devicePixelRatio: 3);

      expect(preset.size, const Size(34, 34));
      expect(preset.spec.pixelWidth, 102);
      expect(preset.spec.pixelHeight, 102);
      expect(preset.spec.variant, AssetVariant.full);
    });

    test('plays by default and can be made a still', () {
      final playing = AssetPresets.keyboardCell(
        extent: 34,
        devicePixelRatio: 3,
      );
      final still = AssetPresets.keyboardCell(
        extent: 34,
        devicePixelRatio: 3,
        animate: false,
      );

      expect(playing.profile.animate, isTrue);
      expect(playing.profile.loop, isTrue);
      expect(still.profile.animate, isFalse);
    });
  });

  group('keyboard cell playback', () {
    test('a playing cell of up to 90 logical px plays at half rate and '
        'decodes at most 160 px', () {
      final cell = AssetPresets.keyboardCell(extent: 66, devicePixelRatio: 3);

      expect(cell.size, const Size(66, 66));
      expect(cell.spec.pixelWidth, 160);
      expect(cell.spec.pixelHeight, 160);
      expect(cell.profile.halfFrameRate, isTrue);
    });

    test('a small cell under the cap keeps its pixels', () {
      final cell = AssetPresets.keyboardCell(extent: 34, devicePixelRatio: 3);

      expect(cell.spec.pixelWidth, 102);
      expect(cell.profile.halfFrameRate, isTrue);
    });

    test('a cell of 90 logical px is still small, one above it is not', () {
      final edge = AssetPresets.keyboardCell(extent: 90, devicePixelRatio: 2);
      final above = AssetPresets.keyboardCell(extent: 91, devicePixelRatio: 2);

      expect(edge.spec.pixelWidth, 160);
      expect(edge.profile.halfFrameRate, isTrue);
      expect(above.spec.pixelWidth, 182);
      expect(above.profile.halfFrameRate, isFalse);
    });

    test('a still cell keeps its full pixels and rate', () {
      final still = AssetPresets.keyboardCell(
        extent: 66,
        devicePixelRatio: 3,
        animate: false,
      );

      expect(still.spec.pixelWidth, 198);
      expect(still.profile.halfFrameRate, isFalse);
    });

    test('takes a decode mode and a fit', () {
      final cell = AssetPresets.keyboardCell(
        extent: 40,
        devicePixelRatio: 2,
        decodeMode: AssetDecodeMode.template,
        fit: AssetFit.cover,
      );

      expect(cell.spec.decodeMode, AssetDecodeMode.template);
      expect(cell.profile.fit, AssetFit.cover);
    });

    test('the chat presets play every frame at full pixels', () {
      final inline = AssetPresets.inlineMessage(
        ascent: 15,
        descent: 4,
        devicePixelRatio: 3,
      );
      final emojiOnly = AssetPresets.emojiOnly(step: 40, devicePixelRatio: 3);
      final sticker = AssetPresets.emojiSticker(
        extent: 60,
        devicePixelRatio: 3,
      );

      expect(inline.profile.halfFrameRate, isFalse);
      expect(emojiOnly.profile.halfFrameRate, isFalse);
      expect(sticker.profile.halfFrameRate, isFalse);
      expect(sticker.spec.pixelWidth, 180);
    });
  });

  group('frame step', () {
    test('half rate shows every second frame of a source above 30 fps', () {
      const half = AssetPaintContext(halfFrameRate: true);

      expect(half.frameStepFor(60), 2);
      expect(half.frameStepFor(59.94), 2);
      expect(half.frameStepFor(30), 1);
      expect(half.frameStepFor(24), 1);
      expect(half.frameStepFor(0), 1);
    });

    test('full rate shows every frame', () {
      const full = AssetPaintContext();

      expect(full.frameStepFor(60), 1);
    });
  });

  group('inline message', () {
    // Ascent 15 and descent 4 give a line of 19 logical px, so the square is
    // 1.2 * 19 = 22.8 logical px, rounded to whole device pixels.
    for (final (dpr, pixels) in [(1.0, 23), (2.0, 46), (3.0, 68)]) {
      test('is a square of 1.2 line heights at density $dpr', () {
        final preset = AssetPresets.inlineMessage(
          ascent: 15,
          descent: 4,
          devicePixelRatio: dpr,
        );

        expect(preset.spec.pixelWidth, pixels);
        expect(preset.spec.pixelHeight, pixels);
        expect(preset.size, Size.square(pixels / dpr));
      });
    }

    test('is one preset for equal metrics, so one cache entry', () {
      final first = AssetPresets.inlineMessage(
        ascent: 15,
        descent: 4,
        devicePixelRatio: 2,
      );
      final second = AssetPresets.inlineMessage(
        ascent: 15,
        descent: 4,
        devicePixelRatio: 2,
      );
      final taller = AssetPresets.inlineMessage(
        ascent: 16,
        descent: 4,
        devicePixelRatio: 2,
      );

      expect(first, second);
      expect(first.spec, second.spec);
      expect(first.spec, isNot(taller.spec));
    });

    test('keeps the colours of the asset unless it is a template', () {
      final original = AssetPresets.inlineMessage(
        ascent: 12,
        descent: 3,
        devicePixelRatio: 2,
      );
      final template = AssetPresets.inlineMessage(
        ascent: 12,
        descent: 3,
        devicePixelRatio: 2,
        decodeMode: AssetDecodeMode.template,
      );

      expect(original.spec.decodeMode, AssetDecodeMode.original);
      expect(template.spec.decodeMode, AssetDecodeMode.template);
    });

    test('plays and loops unless it is made a still', () {
      final playing = AssetPresets.inlineMessage(
        ascent: 12,
        descent: 3,
        devicePixelRatio: 2,
      );
      final still = AssetPresets.inlineMessage(
        ascent: 12,
        descent: 3,
        devicePixelRatio: 2,
        animate: false,
      );

      expect(playing.profile, const AssetProfile(animate: true));
      expect(still.profile.animate, isFalse);
    });

    test('is a different entry from the keyboard cell of another size', () {
      final cell = AssetPresets.keyboardCell(extent: 34, devicePixelRatio: 2);
      final inline = AssetPresets.inlineMessage(
        ascent: 12,
        descent: 3,
        devicePixelRatio: 2,
      );

      expect(cell.spec, isNot(inline.spec));
    });
  });

  group('inline font size', () {
    test('is a square of 1.2 times the font size', () {
      final preset = AssetPresets.inlineFontSize(
        fontSize: 15,
        devicePixelRatio: 2,
      );

      expect(preset.size, const Size(18, 18));
      expect(preset.spec.pixelWidth, 36);
    });
  });

  group('square', () {
    test(
      'decodes an explicit extent at the density with the given profile',
      () {
        final preset = AssetPresets.square(
          extent: 40,
          devicePixelRatio: 2.5,
          profile: const AssetProfile(animate: true, loop: false),
        );

        expect(preset.size, const Size(40, 40));
        expect(preset.spec.pixelWidth, 100);
        expect(preset.spec.pixelHeight, 100);
        expect(preset.profile, const AssetProfile(animate: true, loop: false));
      },
    );
  });

  group('emoji only', () {
    // Steps are font sizes; an item box is the step plus 4 logical px.
    test('draws an item in a box of the step plus the box padding', () {
      final preset = AssetPresets.emojiOnly(step: 55.2, devicePixelRatio: 2);

      expect(preset.size, const Size(59.2, 59.2));
      expect(preset.spec.pixelWidth, 119); // 59.2 * 2 = 118.4, rounded up
      expect(preset.spec.pixelHeight, 119);
    });

    test('decodes at the extent at the density', () {
      final preset = AssetPresets.emojiOnly(step: 40, devicePixelRatio: 3);

      expect(preset.spec.pixelWidth, 132);
      expect(preset.spec.pixelHeight, 132);
    });

    test('is one spec per step and density, two for two steps', () {
      final large = AssetPresets.emojiOnly(step: 81.6, devicePixelRatio: 2);
      final again = AssetPresets.emojiOnly(step: 81.6, devicePixelRatio: 2);
      final small = AssetPresets.emojiOnly(step: 22.8, devicePixelRatio: 2);
      final denser = AssetPresets.emojiOnly(step: 81.6, devicePixelRatio: 3);

      expect(large.spec, again.spec);
      expect(large.spec, isNot(small.spec));
      expect(large.spec, isNot(denser.spec));
    });

    test('animates and loops, like a custom emoji', () {
      final preset = AssetPresets.emojiOnly(step: 40, devicePixelRatio: 2);

      expect(preset.profile.animate, isTrue);
      expect(preset.profile.loop, isTrue);
    });

    test('is a different entry from an inline embed of the same box', () {
      // Same pixels would be one entry; a step whose box differs is not.
      final inline = AssetPresets.inlineMessage(
        ascent: 15,
        descent: 4,
        devicePixelRatio: 2,
      );
      final item = AssetPresets.emojiOnly(step: 22.8, devicePixelRatio: 2);

      expect(item.spec, isNot(inline.spec));
    });
  });

  group('emoji sticker', () {
    test('decodes 112 logical px at density 3 as 336 px square', () {
      final preset = AssetPresets.emojiSticker(
        extent: 112,
        devicePixelRatio: 3,
      );

      expect(preset.size, const Size(112, 112));
      expect(preset.spec.pixelWidth, 336);
      expect(preset.spec.pixelHeight, 336);
      expect(preset.spec.variant, AssetVariant.full);
    });

    test('plays once, not in a loop', () {
      final preset = AssetPresets.emojiSticker(
        extent: 112,
        devicePixelRatio: 3,
      );

      expect(preset.profile.animate, isTrue);
      expect(preset.profile.loop, isFalse);
    });

    test('holds its first frame when the host says not to autoplay', () {
      final preset = AssetPresets.emojiSticker(
        extent: 112,
        devicePixelRatio: 3,
        autoplay: false,
      );

      expect(preset.profile.animate, isFalse);
      expect(preset.profile.autoplayFirstFrame, isTrue);
    });

    test('rests on the first frame, or on the last when the host says so', () {
      final first = AssetPresets.emojiSticker(extent: 112, devicePixelRatio: 3);
      final last = AssetPresets.emojiSticker(
        extent: 112,
        devicePixelRatio: 3,
        restFrame: AssetRestFrame.last,
      );

      expect(first.profile.restFrame, AssetRestFrame.first);
      expect(last.profile.restFrame, AssetRestFrame.last);
      expect(first.spec, last.spec);
    });

    test('is the same decode whether or not it autoplays', () {
      final playing = AssetPresets.emojiSticker(
        extent: 112,
        devicePixelRatio: 3,
      );
      final held = AssetPresets.emojiSticker(
        extent: 112,
        devicePixelRatio: 3,
        autoplay: false,
      );

      expect(playing.spec, held.spec);
    });
  });

  group('media', () {
    test('shows the box it is given and decodes it at the density', () {
      final preset = AssetPresets.media(
        size: const Size(160, 90),
        devicePixelRatio: 2,
        profile: const AssetProfile(animate: true),
      );

      expect(preset.size, const Size(160, 90));
      expect(preset.spec.pixelWidth, 320);
      expect(preset.spec.pixelHeight, 180);
      expect(preset.profile, const AssetProfile(animate: true));
    });

    test('caps the decode at the longer side, keeping the proportion', () {
      // A 206 dp sticker at density 3 is 618 px: decoded at 512.
      final square = AssetPresets.media(
        size: const Size.square(206),
        devicePixelRatio: 3,
        profile: const AssetProfile(),
        maxPixelExtent: 512,
      );
      final wide = AssetPresets.media(
        size: const Size(288, 162),
        devicePixelRatio: 3,
        profile: const AssetProfile(),
        maxPixelExtent: 512,
      );

      expect(square.size, const Size.square(206));
      expect((square.spec.pixelWidth, square.spec.pixelHeight), (512, 512));
      expect((wide.spec.pixelWidth, wide.spec.pixelHeight), (512, 288));
    });

    test('a decode under the cap is not enlarged to it', () {
      final preset = AssetPresets.media(
        size: const Size.square(112),
        devicePixelRatio: 3,
        profile: const AssetProfile(),
        maxPixelExtent: 512,
      );

      expect((preset.spec.pixelWidth, preset.spec.pixelHeight), (336, 336));
    });
  });

  group('AssetPreset', () {
    test('is equal to a preset of the same size, spec and profile', () {
      const spec = AssetSpec(pixelWidth: 4, pixelHeight: 4);
      const a = AssetPreset(
        size: Size(2, 2),
        spec: spec,
        profile: AssetProfile(),
      );
      const b = AssetPreset(
        size: Size(2, 2),
        spec: spec,
        profile: AssetProfile(),
      );
      const c = AssetPreset(
        size: Size(3, 3),
        spec: spec,
        profile: AssetProfile(),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}

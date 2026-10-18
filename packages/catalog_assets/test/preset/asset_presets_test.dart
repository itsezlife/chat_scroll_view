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

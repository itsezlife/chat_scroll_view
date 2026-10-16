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
    test('is as tall as the font size times the extent factor', () {
      final preset = AssetPresets.inlineMessage(
        fontSize: 15,
        devicePixelRatio: 2,
      );

      expect(preset.size, const Size(18, 18));
      expect(preset.spec.pixelWidth, 36);
    });

    test('takes another extent factor', () {
      final preset = AssetPresets.inlineMessage(
        fontSize: 10,
        devicePixelRatio: 1,
        extentPerFontSize: 1.5,
      );

      expect(preset.size, const Size(15, 15));
    });

    test('keeps the colours of the asset unless it is a template', () {
      final original = AssetPresets.inlineMessage(
        fontSize: 15,
        devicePixelRatio: 2,
      );
      final template = AssetPresets.inlineMessage(
        fontSize: 15,
        devicePixelRatio: 2,
        decodeMode: AssetDecodeMode.template,
      );

      expect(original.spec.decodeMode, AssetDecodeMode.original);
      expect(template.spec.decodeMode, AssetDecodeMode.template);
    });

    test('is a different entry from the keyboard cell of another size', () {
      final cell = AssetPresets.keyboardCell(extent: 34, devicePixelRatio: 2);
      final inline = AssetPresets.inlineMessage(
        fontSize: 15,
        devicePixelRatio: 2,
      );

      expect(cell.spec, isNot(inline.spec));
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

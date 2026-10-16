import 'package:catalog_assets/catalog_assets.dart';
import 'package:test/test.dart';

void main() {
  group('AssetSpec', () {
    test('is equal by value, so equal specs share one cache entry', () {
      const a = AssetSpec(pixelWidth: 64, pixelHeight: 64);
      const b = AssetSpec(pixelWidth: 64, pixelHeight: 64);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('size, decode mode and variant each tell two specs apart', () {
      const base = AssetSpec(pixelWidth: 64, pixelHeight: 64);

      expect(base, isNot(const AssetSpec(pixelWidth: 65, pixelHeight: 64)));
      expect(base, isNot(const AssetSpec(pixelWidth: 64, pixelHeight: 65)));
      expect(
        base,
        isNot(
          const AssetSpec(
            pixelWidth: 64,
            pixelHeight: 64,
            decodeMode: AssetDecodeMode.template,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const AssetSpec(
            pixelWidth: 64,
            pixelHeight: 64,
            variant: AssetVariant.firstFrame,
          ),
        ),
      );
    });

    test('defaults to the original colours and the full asset', () {
      const spec = AssetSpec(pixelWidth: 8, pixelHeight: 8);

      expect(spec.decodeMode, AssetDecodeMode.original);
      expect(spec.variant, AssetVariant.full);
    });

    test('atDensity rounds a logical size up to whole pixels', () {
      final spec = AssetSpec.atDensity(
        logicalWidth: 34,
        logicalHeight: 34,
        devicePixelRatio: 2.75,
      );

      // 34 * 2.75 = 93.5 -> 94: never smaller than the box it fills.
      expect(spec.pixelWidth, 94);
      expect(spec.pixelHeight, 94);
    });

    test('atDensity keeps the same logical size at two densities apart', () {
      final low = AssetSpec.atDensity(
        logicalWidth: 34,
        logicalHeight: 34,
        devicePixelRatio: 1,
      );
      final high = AssetSpec.atDensity(
        logicalWidth: 34,
        logicalHeight: 34,
        devicePixelRatio: 3,
      );

      expect(low, isNot(high));
      expect(high.pixelWidth, 102);
    });

    test('estimatedBytes is the decoded RGBA size', () {
      const spec = AssetSpec(pixelWidth: 64, pixelHeight: 32);

      expect(spec.estimatedBytes, 64 * 32 * 4);
    });
  });

  group('AssetProfile', () {
    test('is equal by value and defaults to a still, looping surface', () {
      expect(const AssetProfile(), const AssetProfile());
      expect(const AssetProfile().animate, isFalse);
      expect(const AssetProfile().autoplayFirstFrame, isTrue);
      expect(const AssetProfile().cornerRadius, 0);
      expect(const AssetProfile(animate: true), isNot(const AssetProfile()));
    });
  });

  group('AssetReadiness', () {
    test('stages are ordered none < placeholder < firstFrame < full', () {
      expect(AssetStage.none.index, lessThan(AssetStage.placeholder.index));
      expect(
        AssetStage.placeholder.index,
        lessThan(AssetStage.firstFrame.index),
      );
      expect(AssetStage.firstFrame.index, lessThan(AssetStage.full.index));
    });

    test('is equal by stage and finality', () {
      expect(
        const AssetReadiness(AssetStage.full, isFinal: true),
        const AssetReadiness(AssetStage.full, isFinal: true),
      );
      expect(
        const AssetReadiness(AssetStage.full, isFinal: true),
        isNot(const AssetReadiness(AssetStage.full)),
      );
    });

    test('has no failed stage', () {
      expect(AssetStage.values.map((stage) => stage.name), [
        'none',
        'placeholder',
        'firstFrame',
        'full',
      ]);
    });
  });
}

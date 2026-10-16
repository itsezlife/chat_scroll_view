import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/src/glass/strategy/glass_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

const _impeller = GlassCapabilities.all;
const _skiaLike = GlassCapabilities(
  sampledBackdrop: false,
  shaderFilter: false,
  backdropFilter: true,
);
const _noFilters = GlassCapabilities.none;

GlassStrategy _select(
  GlassQuality quality,
  GlassCapabilities capabilities, {
  bool source = false,
  bool moving = false,
  bool lite = false,
}) => selectGlassStrategy(
  quality: quality,
  liteMode: lite,
  capabilities: capabilities,
  hasSource: source,
  routeMoving: moving,
);

void main() {
  group('quality x capabilities x source x route motion', () {
    // (quality, capabilities, hasSource, routeMoving) -> strategy
    final table =
        <(GlassQuality, GlassCapabilities, bool, bool, GlassStrategy)>[
          // A source on a capable backend samples; route motion never matters.
          (
            GlassQuality.fullLiquid,
            _impeller,
            true,
            false,
            GlassStrategy.sampledLiquid,
          ),
          (
            GlassQuality.fullLiquid,
            _impeller,
            true,
            true,
            GlassStrategy.sampledLiquid,
          ),
          (
            GlassQuality.frosted,
            _impeller,
            true,
            false,
            GlassStrategy.sampledFrost,
          ),
          (
            GlassQuality.frosted,
            _impeller,
            true,
            true,
            GlassStrategy.sampledFrost,
          ),
          // No source: the scene is filtered, but flat while the route moves.
          (
            GlassQuality.fullLiquid,
            _impeller,
            false,
            false,
            GlassStrategy.backdropFilter,
          ),
          (GlassQuality.fullLiquid, _impeller, false, true, GlassStrategy.flat),
          (
            GlassQuality.frosted,
            _impeller,
            false,
            false,
            GlassStrategy.backdropFilter,
          ),
          (GlassQuality.frosted, _impeller, false, true, GlassStrategy.flat),
          // A source the backend cannot capture falls back to the scene filter.
          (
            GlassQuality.fullLiquid,
            _skiaLike,
            true,
            false,
            GlassStrategy.backdropFilter,
          ),
          (GlassQuality.fullLiquid, _skiaLike, true, true, GlassStrategy.flat),
          (
            GlassQuality.frosted,
            _skiaLike,
            false,
            false,
            GlassStrategy.backdropFilter,
          ),
          // No filter at all: flat.
          (
            GlassQuality.fullLiquid,
            _noFilters,
            true,
            false,
            GlassStrategy.flat,
          ),
          (GlassQuality.frosted, _noFilters, false, false, GlassStrategy.flat),
          // The host can ask for flat or none whatever the backend offers.
          (GlassQuality.flat, _impeller, true, false, GlassStrategy.flat),
          (GlassQuality.flat, _impeller, false, false, GlassStrategy.flat),
          (GlassQuality.off, _impeller, true, false, GlassStrategy.none),
          (GlassQuality.off, _noFilters, false, true, GlassStrategy.none),
        ];

    for (final (quality, caps, source, moving, expected) in table) {
      test(
        '$quality source=$source moving=$moving -> $expected '
        '(sampled=${caps.sampledBackdrop} filter=${caps.backdropFilter})',
        () {
          expect(
            _select(quality, caps, source: source, moving: moving),
            expected,
          );
        },
      );
    }
  });

  group('lite mode', () {
    test('caps every glass quality at flat', () {
      for (final quality in [GlassQuality.fullLiquid, GlassQuality.frosted]) {
        expect(
          _select(quality, _impeller, source: true, lite: true),
          GlassStrategy.flat,
        );
      }
    });

    test('keeps off as off', () {
      expect(
        _select(GlassQuality.off, _impeller, lite: true),
        GlassStrategy.none,
      );
    });
  });
}

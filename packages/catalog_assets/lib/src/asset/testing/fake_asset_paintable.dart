import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/atlas/atlas_sprite.dart';

/// An [AssetPaintable] that records what is done to it.
final class FakeAssetPaintable implements AssetPaintable {
  /// Creates a paintable called [label] (shown in failures).
  FakeAssetPaintable({
    this.label = 'paintable',
    this.isAnimated = false,
    this.sprite,
  });

  /// Names this paintable in test output.
  final String label;

  @override
  final bool isAnimated;

  @override
  final AtlasSprite? sprite;

  /// Every [paint] call, in order.
  final List<({Rect rect, AssetPaintContext context})> paints = [];

  /// How many times [dispose] was called.
  int disposals = 0;

  /// Whether the cache disposed it.
  bool get isDisposed => disposals > 0;

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) {
    assert(!isDisposed, '$label painted after dispose');
    paints.add((rect: rect, context: context));
  }

  @override
  void dispose() => disposals++;

  @override
  String toString() => 'FakeAssetPaintable($label)';
}

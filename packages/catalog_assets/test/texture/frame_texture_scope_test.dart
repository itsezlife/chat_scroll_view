import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Still extends AssetPaintable {
  const _Still();

  @override
  AtlasSprite? get sprite => null;

  @override
  bool get isAnimated => false;

  @override
  bool get isHolding => false;

  @override
  bool restart() => false;

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) {}

  @override
  void dispose() {}
}

void main() {
  late FakeFrameTextureHost host;
  late FrameTexturePool pool;

  setUp(() {
    host = FakeFrameTextureHost();
    pool = FrameTexturePool(host: host);
  });

  tearDown(() => pool.dispose());

  test('a paintable has no texture unless it says so', () {
    expect(const _Still().texture, isNull);
  });

  test('the fake paintable exposes its texture once it was advanced', () {
    const texture = AssetTexture(id: 7, width: 128, height: 128);
    final paintable = FakeAssetPaintable(isAnimated: true)
      ..textureOnAdvance = texture;

    expect(paintable.texture, isNull);
    paintable.advancePlayback(const AssetPaintContext());
    expect(paintable.texture, texture);
  });

  test('the scope hands surfaces and decoders the registered pool', () {
    final scope = AssetCacheScope(textures: pool);
    addTearDown(scope.dispose);

    expect(scope.textures, same(pool));
    expect(AssetCacheScope().textures, isNull, reason: 'none by default');
  });

  test('memory pressure destroys the idle textures, not leased ones', () async {
    final pressure = ManualMemoryPressure();
    final scope = AssetCacheScope(textures: pool, memoryPressure: pressure);
    addTearDown(scope.dispose);
    await pool.warm(128, 2);
    final held = pool.lease(100, 100)!;

    pressure.raise();

    expect(host.liveIds, [held.texture.id]);
  });

  test('the scope does not dispose a pool it was handed', () async {
    await pool.warm(128, 1);
    AssetCacheScope(textures: pool).dispose();

    expect(pool.lease(100, 100), isNotNull);
  });
}

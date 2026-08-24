import 'package:catalog_assets/catalog_assets.dart';
import 'package:test/test.dart';

void main() {
  group('CatalogAssetCache', () {
    late MemoryCatalogAssetCache cache;

    setUp(() {
      cache = MemoryCatalogAssetCache();
    });

    test('attach returns loading readiness for a new key and cache type', () {
      final binding = cache.attach(
        const CatalogAssetKey.unicode('😀'),
        CatalogAssetCacheType.keyboard,
      );

      expect(binding.readiness, CatalogAssetReadiness.loading);
      expect(binding.key, const CatalogAssetKey.unicode('😀'));
      expect(binding.cacheType, CatalogAssetCacheType.keyboard);
    });

    test('markReady updates binding readiness and notifies listeners', () {
      const key = CatalogAssetKey.unicode('😀');
      final binding = cache.attach(key, CatalogAssetCacheType.keyboard);
      var notifications = 0;
      binding.addListener(() => notifications += 1);

      cache.markReady(key, CatalogAssetCacheType.keyboard);

      expect(binding.readiness, CatalogAssetReadiness.ready);
      expect(notifications, 1);
    });

    test('entry stays retained until the last attached surface detaches', () {
      const key = CatalogAssetKey.unicode('😀');
      final first = cache.attach(key, CatalogAssetCacheType.keyboard);
      final second = cache.attach(key, CatalogAssetCacheType.keyboard);

      expect(cache.isRetained(key, CatalogAssetCacheType.keyboard), isTrue);

      first.detach();
      expect(cache.isRetained(key, CatalogAssetCacheType.keyboard), isTrue);

      second.detach();
      expect(cache.isRetained(key, CatalogAssetCacheType.keyboard), isFalse);
    });

    test('detaching the last surface evicts readiness for a later attach', () {
      const key = CatalogAssetKey.document('doc-42');
      final binding = cache.attach(key, CatalogAssetCacheType.messages);
      cache.markReady(key, CatalogAssetCacheType.messages);
      binding.detach();

      final rebound = cache.attach(key, CatalogAssetCacheType.messages);

      expect(rebound.readiness, CatalogAssetReadiness.loading);
    });

    test('cache type isolates readiness for the same key', () {
      const key = CatalogAssetKey.document('doc-42');
      final keyboard = cache.attach(key, CatalogAssetCacheType.keyboard);
      final messages = cache.attach(key, CatalogAssetCacheType.messages);

      cache.markReady(key, CatalogAssetCacheType.keyboard);
      cache.markFailed(key, CatalogAssetCacheType.messages);

      expect(keyboard.readiness, CatalogAssetReadiness.ready);
      expect(messages.readiness, CatalogAssetReadiness.failed);
    });

    test('FakeCatalogAssetCache drives readiness for deterministic tests', () {
      final fake = FakeCatalogAssetCache();
      const key = CatalogAssetKey.unicode('👍');
      final binding = fake.attach(key, CatalogAssetCacheType.keyboard);

      fake.markFailed(key, CatalogAssetCacheType.keyboard);

      expect(binding.readiness, CatalogAssetReadiness.failed);
    });

    test('detach stops readiness notifications for that binding', () {
      const key = CatalogAssetKey.unicode('😀');
      final first = cache.attach(key, CatalogAssetCacheType.keyboard);
      final second = cache.attach(key, CatalogAssetCacheType.keyboard);
      var firstNotifications = 0;
      var secondNotifications = 0;
      first.addListener(() => firstNotifications += 1);
      second.addListener(() => secondNotifications += 1);

      first.detach();
      cache.markReady(key, CatalogAssetCacheType.keyboard);

      expect(firstNotifications, 0);
      expect(secondNotifications, 1);
    });
  });
}

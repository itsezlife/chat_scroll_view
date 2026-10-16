import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = ContentKey.document('sticker-1');
const _spec = AssetSpec(pixelWidth: 64, pixelHeight: 64);
const _profile = AssetProfile();

void main() {
  late FakeAssetProducer producer;
  late AssetCacheScope scope;

  setUp(() {
    producer = FakeAssetProducer();
    scope = AssetCacheScope(
      producer: producer,
      clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
    );
  });
  tearDown(() => scope.dispose());

  group('demand', () {
    test('is visible while a binding shows the entry', () {
      scope.attach(_key, _spec, _profile);

      expect(producer.last.demand.priority, AssetPriority.visible);
    });

    test('drops to preload when every binding is hidden', () {
      final binding = scope.attach(_key, _spec, _profile);

      binding.visible = false;

      expect(producer.last.demand.priority, AssetPriority.preload);
    });

    test('stays visible while one of several bindings shows the entry', () {
      final hidden = scope.attach(_key, _spec, _profile);
      scope.attach(_key, _spec, _profile);

      hidden.visible = false;

      expect(producer.last.demand.priority, AssetPriority.visible);
    });

    test('rises again when a hidden entry is shown', () {
      final binding = scope.attach(_key, _spec, _profile)..visible = false;

      binding.visible = true;

      expect(producer.last.demand.priority, AssetPriority.visible);
    });

    test('follows the bindings that remain after one detaches', () {
      final shown = scope.attach(_key, _spec, _profile);
      scope.attach(_key, _spec, _profile).visible = false;

      shown.detach();

      expect(producer.last.demand.priority, AssetPriority.preload);
    });

    test('is one object for the entry across its attempts', () {
      final binding = scope.attach(_key, _spec, _profile);
      final first = producer.last.demand;
      producer.last.fail('offline');

      binding.retry();

      expect(producer.attempts, hasLength(2));
      expect(producer.last.demand, same(first));
    });
  });
}

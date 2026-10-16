/// The composition root: what it builds, in which order, and who frees what.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_services.dart';

/// A key-value store that logs each read into [log] with the others' reads.
final class _LoggingStore implements KeyValueStore {
  _LoggingStore(this.log);

  final List<String> log;
  final _inner = FakeKeyValueStore();

  @override
  Future<StoredValue?> read(String namespace, String key) {
    log.add('kv:$namespace');
    return _inner.read(namespace, key);
  }

  @override
  Future<void> write(String namespace, String key, StoredValue value) =>
      _inner.write(namespace, key, value);

  @override
  Future<void> remove(String namespace, String key) =>
      _inner.remove(namespace, key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('composition order', () {
    test('the key-value store is read before any data source reads the '
        'catalogue', () async {
      final log = <String>[];

      final services = await AppServices.create(
        keyValueStore: _LoggingStore(log),
        assetLoader: (key) {
          log.add('asset:${key.split('/').last}');
          return rootBundle.loadString(key);
        },
      );
      addTearDown(services.dispose);

      final firstAsset = log.indexWhere((entry) => entry.startsWith('asset:'));
      final lastRead = log.lastIndexWhere((entry) => entry.startsWith('kv:'));
      expect(firstAsset, isPositive, reason: 'the stores read first: $log');
      expect(lastRead, lessThan(firstAsset), reason: '$log');
      expect(
        log.where((entry) => entry.startsWith('kv:')).toSet(),
        containsAll(<String>{
          'kv:${AppServices.recentsNamespace}',
          'kv:${AppServices.preferencesNamespace}',
          'kv:panel_presentation',
        }),
      );
    });

    test('the stores arrive loaded: what an earlier launch saved is there '
        'when the sources are', () async {
      final storage = FakeKeyValueStore();
      final first = await createTestServices(storage: storage);
      await first.recents.record(
        const ContentKey.unicode('\u{1F44D}'),
        kind: SemanticKind.unicodeEmoji,
      );
      first.dispose();

      final second = await createTestServices(storage: storage);
      addTearDown(second.dispose);

      expect(second.recents.recents(SemanticKind.unicodeEmoji), [
        const ContentKey.unicode('\u{1F44D}'),
      ]);
      await second.emojiSource.load(CollectionId.recent);
      await Future<void>.value();
      final recent = second.emojiSource.collections.value.firstWhere(
        (collection) => collection.id == CollectionId.recent,
      );
      expect(recent.contents, isA<CollectionContents$Loaded>());
    });
  });

  group('the atlas plan', () {
    Future<(AppServices, List<Collection>)> loaded() async {
      final services = await createTestServices();
      addTearDown(services.dispose);
      for (final collection in services.emojiSource.collections.value) {
        await services.emojiSource.load(collection.id);
      }
      // Loaded is published a microtask after the ask.
      await Future<void>.delayed(Duration.zero);
      return (services, services.emojiSource.collections.value);
    }

    test('lists every catalogue entry once, in palette order', () async {
      final (services, collections) = await loaded();

      final plan = services.planGlyphs(collections);

      expect(plan, isNotNull);
      expect(plan!.glyphs, [
        for (final entry in services.catalog.entries) entry.base.sequence,
      ]);
    });

    test('plans a chosen skin tone in the place of its emoji', () async {
      final (services, _) = await loaded();
      final entry = services.catalog.entries.firstWhere(
        (entry) => entry.hasToneVariants,
      );
      final place = services.catalog.entries.indexOf(entry);

      await services.emojiSource.chooseVariant(entry, entry.variants.first.key);
      final plan = services.planGlyphs(services.emojiSource.collections.value);

      expect(plan!.glyphs[place], entry.variants.first.key.sequence);
      expect(plan.glyphs, isNot(contains(entry.base.sequence)));
      expect(plan.glyphs.length, services.catalog.entries.length);
    });

    test('there is none while a collection is still loading', () async {
      final services = await createTestServices();
      addTearDown(services.dispose);

      expect(
        services.planGlyphs(services.emojiSource.collections.value),
        isNull,
      );
    });
  });

  group('disposal', () {
    test('it frees what it made and is idempotent', () async {
      final services = await createTestServices();
      var notified = 0;
      services.recents.changes.addListener(() => notified++);

      services
        ..dispose()
        ..dispose();

      expect(services.isDisposed, isTrue);
      expect(
        () => services.assets.attach(
          const ContentKey.document('1'),
          const AssetSpec(pixelWidth: 8, pixelHeight: 8),
          const AssetProfile(),
        ),
        throwsStateError,
        reason: 'the asset cache is closed',
      );
      await services.recents.record(
        const ContentKey.unicode('\u{1F44D}'),
        kind: SemanticKind.unicodeEmoji,
      );
      expect(notified, 0, reason: 'the stores are closed');
    });

    test('what a host hands in is left alone', () async {
      final storage = FakeKeyValueStore();
      final services = await createTestServices(storage: storage);
      await services.preferences.setSelectedPageId('emoji');

      services.dispose();

      expect(storage.entries, isNotEmpty);
      expect(
        await storage.read(AppServices.preferencesNamespace, 'preferences'),
        isNotNull,
      );
    });
  });
}

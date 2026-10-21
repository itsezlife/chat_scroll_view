/// The composition root: what it builds, in which order, and who frees what.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import '../support/disposal_watch.dart';
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

/// A store whose reads fail.
final class _FailingStore implements KeyValueStore {
  @override
  Future<StoredValue?> read(String namespace, String key) =>
      Future.error(StateError('unreadable'));

  @override
  Future<void> write(String namespace, String key, StoredValue value) async {}

  @override
  Future<void> remove(String namespace, String key) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the panel\'s collections are loaded before it first opens', () async {
    // Loaded on the first open, every section showed a row of placeholders
    // and then jumped to its size.
    final services = await createTestServices();
    addTearDown(services.dispose);

    final source = services.emojiPageSource;
    expect(source.collections.value, isNotEmpty);
    for (final collection in source.collections.value) {
      expect(
        collection.contents,
        isNot(isA<CollectionContents$Idle>()),
        reason: '${collection.id} waits for the panel',
      );
    }
    // A load in flight answers with its own future.
    await Future.wait([
      for (final collection in source.collections.value)
        source.load(collection.id),
    ]);
    for (final collection in source.collections.value) {
      expect(
        collection.contents,
        isA<CollectionContents$Loaded>(),
        reason: '${collection.id}',
      );
    }
  });

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

  group('a step that fails', () {
    test('frees what the earlier steps made and rethrows', () async {
      final watch = DisposalWatch();
      addTearDown(watch.stop);

      await expectLater(
        AppServices.create(
          keyValueStore: FakeKeyValueStore(),
          assetLoader: (key) async => throw StateError('no catalogue'),
        ),
        throwsStateError,
      );

      expect(watch.undisposed, isEmpty);
    });

    test(
      'is the same whichever step it is: a store that cannot be read',
      () async {
        final watch = DisposalWatch();
        addTearDown(watch.stop);

        await expectLater(
          AppServices.create(
            keyValueStore: _FailingStore(),
            assetLoader: rootBundle.loadString,
          ),
          throwsA(isA<ParallelWaitError<Object?, Object?>>()),
        );

        expect(watch.undisposed, isEmpty);
      },
    );
  });

  group('the pause policies', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();

    // The binding's lifecycle is process-wide state, and `hidden` turns its
    // frames off: give it back as found.
    tearDown(() {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    Set<PlaybackPauseLayer> layers(AppServices services) =>
        services.assets.clock.pausedLayers;

    test('the window losing focus pauses the shared clock and getting it '
        'back resumes', () async {
      final services = await createTestServices();
      addTearDown(services.dispose);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(layers(services), isEmpty);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(layers(services), {PlaybackPauseLayer.appInactive});
      expect(services.assets.clock.isPaused, isTrue);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(layers(services), isEmpty);
    });

    test(
      'minimising pauses it twice over, and restoring clears both',
      () async {
        final services = await createTestServices();
        addTearDown(services.dispose);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

        binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        expect(layers(services), {
          PlaybackPauseLayer.appInactive,
          PlaybackPauseLayer.surfaceHidden,
        });

        binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        expect(layers(services), isEmpty);
      },
    );

    test('the low power switch drives its layer: nothing in the example '
        'detects battery saving', () async {
      final services = await createTestServices();
      addTearDown(services.dispose);
      expect(services.lowPower.value, isFalse);

      services.lowPower.value = true;
      expect(layers(services), {PlaybackPauseLayer.lowPower});

      services.lowPower.value = false;
      expect(layers(services), isEmpty);
    });

    test('the system reduced-motion setting is reported on its layer but '
        'does not stop playback', () async {
      final services = await createTestServices();
      addTearDown(services.dispose);
      addTearDown(
        binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      binding.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures.allOn;
      expect(layers(services), {PlaybackPauseLayer.reducedMotion});
      expect(services.assets.clock.isPaused, isFalse);

      binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
      expect(layers(services), isEmpty);
    });

    test('disposing the services gives the clock back running', () async {
      final services = await createTestServices();
      final clock = services.assets.clock;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      services.lowPower.value = true;
      services.activity.holdOverlay();
      expect(clock.pausedLayers, hasLength(3));

      services.dispose();

      expect(clock.pausedLayers, isEmpty);
    });
  });

  group('what a screen reader says', () {
    test('every emoji the grid shows carries a spoken name in the app '
        'language', () async {
      final services = await createTestServices();
      addTearDown(services.dispose);
      // The first section after the recents.
      final first = services.emojiSource.collections.value[1].id;
      await services.emojiSource.load(first);

      final loaded =
          services.emojiSource.collections.value
                  .firstWhere((c) => c.id == first)
                  .contents
              as CollectionContents$Loaded;
      final spoken = [
        for (final item in loaded.items) item.descriptor?.spokenName,
      ];
      expect(
        spoken.first,
        'широко улыбается',
        reason: 'ru is the first language',
      );
      expect(spoken, everyElement(isNotNull));
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

  group('the emoji page source', () {
    test(
      'lists the animated emoji pack after the catalogue\'s categories',
      () async {
        final services = await createTestServices();
        addTearDown(services.dispose);

        final ids = [
          for (final collection in services.emojiPageSource.collections.value)
            collection.id,
        ];
        expect(ids.first, CollectionId.recent);
        expect(ids.last, AnimatedEmojiPack.id);
        expect(ids.whereType<CollectionId$Category>(), isNotEmpty);
      },
    );

    test('lists an animated emoji in the recents, described, beside the '
        'unicode ones', () async {
      final services = await createTestServices();
      addTearDown(services.dispose);
      final rocket = AnimatedEmojiPack.emoji.last;
      await services.recents.record(
        const ContentKey.unicode('😀'),
        kind: SemanticKind.unicodeEmoji,
      );
      await services.recents.record(
        rocket.key,
        kind: SemanticKind.unicodeEmoji,
      );
      services.recentsShown.commit();

      await services.emojiPageSource.load(CollectionId.recent);
      await Future<void>.delayed(Duration.zero);

      final recents = services.emojiPageSource.collections.value.first;
      final items = (recents.contents as CollectionContents$Loaded).items;
      expect(items.map((item) => item.key), [
        rocket.key,
        const ContentKey.unicode('😀'),
      ]);
      expect(items.first.descriptor, rocket.descriptor);
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

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _spec = AssetSpec(pixelWidth: 64, pixelHeight: 64);
const _profile = AssetProfile();

ContentKey _id(int n) => ContentKey.document('doc-$n');

void main() {
  late FakeAssetProducer producer;
  late ManualMemoryPressure pressure;
  late AssetCacheScope scope;

  setUp(() {
    producer = FakeAssetProducer();
    pressure = ManualMemoryPressure();
    scope = AssetCacheScope(
      producer: producer,
      budgets: const AssetCacheBudgets(stillBytes: 300, animatedBytes: 300),
      memoryPressure: pressure,
      clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
    );
  });
  tearDown(() {
    scope.dispose();
    pressure.dispose();
  });

  /// Attaches content [n], makes it full at [bytes] and detaches it.
  FakeAssetPaintable cached(
    int n, {
    int bytes = 100,
    AssetTier tier = AssetTier.still,
  }) {
    final binding = scope.attach(_id(n), _spec, _profile);
    final paintable = producer.last.advance(
      AssetStage.full,
      bytes: bytes,
      tier: tier,
      animated: tier == AssetTier.animated,
    );
    binding.detach();
    return paintable;
  }

  group('defaults', () {
    test('are 24 MiB of stills and 32 MiB of animations', () {
      expect(AssetCacheBudgets.defaults.stillBytes, 24 * 1024 * 1024);
      expect(AssetCacheBudgets.defaults.animatedBytes, 32 * 1024 * 1024);
      expect(AssetCacheBudgets.defaults.of(AssetTier.still), 24 * 1024 * 1024);
    });
  });

  // Ticket 100: a kept panel pins the attach windows of its sticker page
  // (35 cells of a 181 KB Lottie at 160 px: one still plus the file) and of
  // its emoji page (64 playing WebP emoji at 99 px: three frames plus the
  // file); a screen of stickers scrolled out on top of that must stay, with
  // its position, for the scroll back.
  group('the default animated budget', () {
    const sticker = 160 * 160 * 4 + 181000;
    const emoji = 99 * 99 * 4 * 3 + 8000;

    test('keeps a scrolled-out sticker screen beside a kept panel', () {
      final defaults = AssetCacheScope(
        producer: producer,
        clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
      );
      addTearDown(defaults.dispose);
      AssetBinding cell(int n, int bytes) {
        final binding = defaults.attach(_id(n), _spec, _profile);
        if (!binding.readiness.isFinal) {
          producer.last.advance(
            AssetStage.full,
            bytes: bytes,
            tier: AssetTier.animated,
            animated: true,
          );
        }
        return binding;
      }

      for (var n = 0; n < 35; n++) {
        cell(n, sticker);
      }
      for (var n = 100; n < 164; n++) {
        cell(n, emoji);
      }
      final scrolledOut = [for (var n = 200; n < 235; n++) cell(n, sticker)];
      final shown = [for (final b in scrolledOut) b.paintable];
      for (final binding in scrolledOut) {
        binding.detach();
      }

      for (var i = 0; i < 35; i++) {
        final back = defaults.attach(_id(200 + i), _spec, _profile);
        expect(back.paintable, same(shown[i]), reason: 'cell ${200 + i}');
      }
      expect(producer.attempts, hasLength(35 + 64 + 35));
    });
  });

  group('unattached entries are kept until the budget needs the room', () {
    test('everything within the budget stays', () {
      cached(1);
      cached(2);
      cached(3);

      expect(scope.bytesIn(AssetTier.still), 300);
      for (final n in [1, 2, 3]) {
        expect(scope.contains(_id(n), _spec), isTrue);
      }
    });

    test('over the budget the least recently used goes first', () {
      final oldest = cached(1);
      cached(2);
      cached(3);

      cached(4);

      expect(scope.contains(_id(1), _spec), isFalse);
      expect(oldest.disposals, 1);
      expect(scope.contains(_id(2), _spec), isTrue);
      expect(scope.bytesIn(AssetTier.still), 300);
    });

    test('using an entry again makes it the most recent', () {
      cached(1);
      cached(2);
      cached(3);
      scope.attach(_id(1), _spec, _profile).detach();

      cached(4);

      expect(scope.contains(_id(1), _spec), isTrue);
      expect(scope.contains(_id(2), _spec), isFalse);
    });

    test('a large entry may push out several small ones', () {
      cached(1);
      cached(2);
      cached(3);

      cached(4, bytes: 250);

      expect(scope.contains(_id(1), _spec), isFalse);
      expect(scope.contains(_id(2), _spec), isFalse);
      expect(scope.contains(_id(3), _spec), isFalse);
      expect(scope.bytesIn(AssetTier.still), 250);
    });

    test('lowering the budget trims at once', () {
      cached(1);
      cached(2);
      cached(3);

      scope.budgets = const AssetCacheBudgets(stillBytes: 100);

      expect(scope.bytesIn(AssetTier.still), 100);
      expect(scope.contains(_id(3), _spec), isTrue);
    });
  });

  group('tiers', () {
    test('stills and animations are budgeted apart', () {
      cached(1, tier: AssetTier.animated);
      cached(2, tier: AssetTier.animated);
      cached(3, tier: AssetTier.animated);
      cached(4);
      cached(5);
      cached(6);

      expect(scope.bytesIn(AssetTier.animated), 300);
      expect(scope.bytesIn(AssetTier.still), 300);
    });

    test('a full tier evicts only its own entries', () {
      cached(1);
      cached(2, tier: AssetTier.animated);
      cached(3, tier: AssetTier.animated);
      cached(4, tier: AssetTier.animated);

      cached(5, tier: AssetTier.animated);

      expect(scope.contains(_id(1), _spec), isTrue, reason: 'a still');
      expect(scope.contains(_id(2), _spec), isFalse);
    });
  });

  group('pinned entries', () {
    test('a bound entry survives any pressure of the budget', () {
      final held = scope.attach(_id(1), _spec, _profile);
      final paintable = producer.last.advance(AssetStage.full);

      cached(2);
      cached(3);
      cached(4);
      cached(5);

      expect(scope.contains(_id(1), _spec), isTrue);
      expect(held.paintable, same(paintable));
      expect(paintable.disposals, 0);
    });

    test('pinned bytes come out of the budget before unattached ones', () {
      scope.attach(_id(1), _spec, _profile);
      producer.last.advance(AssetStage.full, bytes: 250);

      cached(2);

      expect(scope.contains(_id(2), _spec), isFalse);
      expect(scope.bytesIn(AssetTier.still), 250);
    });

    test('once detached it becomes the most recent and evictable', () {
      final held = scope.attach(_id(1), _spec, _profile);
      producer.last.advance(AssetStage.full);
      cached(2);
      cached(3);
      held.detach();

      cached(4);

      expect(scope.contains(_id(2), _spec), isFalse);
      expect(scope.contains(_id(1), _spec), isTrue);
    });
  });

  group('clearAll and memory pressure', () {
    test('clearAll drops every unattached entry and keeps the bound ones', () {
      final held = scope.attach(_id(1), _spec, _profile);
      final kept = producer.last.advance(AssetStage.full);
      final gone = cached(2);
      cached(3);

      scope.clearAll();

      expect(scope.contains(_id(1), _spec), isTrue);
      expect(scope.contains(_id(2), _spec), isFalse);
      expect(gone.disposals, 1);
      expect(kept.disposals, 0);
      expect(held.paintable, same(kept));
      expect(scope.bytesIn(AssetTier.still), 100);
    });

    test('the memory-pressure signal does the same', () {
      cached(1);
      cached(2);

      pressure.raise();

      expect(scope.entryCount, 0);
      expect(scope.bytesIn(AssetTier.still), 0);
    });

    test('after dispose the signal is no longer listened to', () {
      cached(1);
      scope.dispose();

      expect(pressure.isListened, isFalse);
    });
  });

  group('eviction never corrupts the counts of a live binding', () {
    // The audit defect (B1): a binding released its count by looking its key
    // up, so after an evict it decremented whichever entry now had that key.
    test('clearAll with live bindings leaves them attached', () {
      final a = scope.attach(_id(1), _spec, _profile);
      final b = scope.attach(_id(1), _spec, _profile);
      producer.last.advance(AssetStage.full);

      scope.clearAll();
      expect(scope.isAttached(_id(1), _spec), isTrue);

      a.detach();
      expect(scope.isAttached(_id(1), _spec), isTrue);
      b.detach();
      expect(scope.isAttached(_id(1), _spec), isFalse);
    });

    test('a binding made after clearAll shares the entry of the old one', () {
      final old = scope.attach(_id(1), _spec, _profile);
      producer.last.advance(AssetStage.full);
      scope.clearAll();
      final fresh = scope.attach(_id(1), _spec, _profile);

      old.detach();

      expect(scope.isAttached(_id(1), _spec), isTrue);
      expect(fresh.readiness.isFinal, isTrue);
      fresh.detach();
      expect(scope.isAttached(_id(1), _spec), isFalse);
    });

    test('detaching twice gives back one count', () {
      final a = scope.attach(_id(1), _spec, _profile);
      scope.attach(_id(1), _spec, _profile);

      a
        ..detach()
        ..detach();

      expect(scope.isAttached(_id(1), _spec), isTrue);
    });

    test('byte accounting is exact through attach, clear and detach churn', () {
      final live = scope.attach(_id(1), _spec, _profile);
      producer.last.advance(AssetStage.full);
      cached(2);
      scope.clearAll();
      cached(3);
      scope.clearAll();
      live.detach();
      scope.clearAll();

      expect(scope.bytesIn(AssetTier.still), 0);
      expect(scope.entryCount, 0);
    });
  });
}

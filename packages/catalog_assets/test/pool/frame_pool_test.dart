import 'package:catalog_assets/frame_pool.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two 256 px pages (512 KiB): eight 128 px cells, or two 256 px cells.
const _budget = 2 * 256 * 256 * 4;

void main() {
  late List<String> evicted;
  late FramePool<String> pool;

  setUp(() {
    evicted = <String>[];
    pool = FramePool<String>(
      pageSideFor: (_) => 256,
      budgetBytes: _budget,
      sizeClasses: const [128, 256],
      onEvict: evicted.add,
    );
  });

  /// Fills the pool with eight 128 px entries `a0`..`a7`, all released.
  void fillUnpinned() {
    for (var i = 0; i < 8; i++) {
      pool.acquire('a$i', 100, 100)!.release();
    }
  }

  group('pinning', () {
    test('acquire gives a pinned slot', () {
      final lease = pool.acquire('a', 100, 100)!;

      expect(lease.isReleased, isFalse);
      expect(pool.pinnedEntries, 1);
      expect(pool.residentEntries, 1);
    });

    test('two leases on one entry share a slot and pin until both end', () {
      final first = pool.acquire('a', 100, 100)!;
      final second = pool.acquire('a', 100, 100)!;

      expect(second.slot, first.slot);
      first.release();
      expect(pool.pinnedEntries, 1);
      second.release();
      expect(pool.pinnedEntries, 0);
    });

    test('releasing a lease twice releases it once', () {
      final first = pool.acquire('a', 100, 100)!;
      final second = pool.acquire('a', 100, 100)!;

      first
        ..release()
        ..release();

      expect(pool.pinnedEntries, 1, reason: 'the second lease still holds it');
      second.release();
    });

    test('a released entry stays resident and is found again', () {
      final first = pool.acquire('a', 100, 100)!;
      final slot = first.slot;
      first.release();

      expect(pool.residentEntries, 1);
      expect(pool.pinnedEntries, 0);
      expect(pool.acquire('a', 100, 100)!.slot, slot);
      expect(evicted, isEmpty);
    });
  });

  group('eviction', () {
    test('a full pool evicts the least recently used unpinned entry', () {
      fillUnpinned();

      final lease = pool.acquire('b', 100, 100);

      expect(lease, isNotNull);
      expect(evicted, ['a0']);
      expect(pool.residentEntries, 8);
    });

    test('using an entry again makes it the most recent', () {
      fillUnpinned();
      pool.acquire('a0', 100, 100)!.release();

      pool.acquire('b', 100, 100);

      expect(evicted, ['a1']);
    });

    test('a pinned entry is never evicted', () {
      final held = <FrameLease>[
        for (var i = 0; i < 8; i++) pool.acquire('a$i', 100, 100)!,
      ];

      expect(pool.acquire('b', 100, 100), isNull);
      expect(evicted, isEmpty);
      expect(held.every((l) => !l.isReleased), isTrue);
    });

    test('a pool of pinned entries but one still serves from that one', () {
      for (var i = 0; i < 7; i++) {
        pool.acquire('a$i', 100, 100);
      }
      pool.acquire('last', 100, 100)!.release();

      expect(pool.acquire('b', 100, 100), isNotNull);
      expect(evicted, ['last']);
    });

    test('eviction goes on until a cell of the wanted class is free', () {
      // Four 128 px cells fill page 0, four more fill page 1; a 256 px entry
      // needs a whole page, so one page's worth of entries goes.
      fillUnpinned();

      final lease = pool.acquire('wide', 200, 200);

      expect(lease, isNotNull);
      expect(evicted, ['a0', 'a1', 'a2', 'a3']);
    });

    test('a size above the largest class is an error', () {
      expect(() => pool.acquire('huge', 300, 10), throwsArgumentError);
    });
  });

  group('memory pressure', () {
    test('releaseUnpinned drops every unpinned entry and keeps the pinned', () {
      final held = pool.acquire('held', 100, 100)!;
      pool.acquire('idle1', 100, 100)!.release();
      pool.acquire('idle2', 100, 100)!.release();

      pool.releaseUnpinned();

      expect(evicted, unorderedEquals(['idle1', 'idle2']));
      expect(pool.residentEntries, 1);
      expect(pool.pinnedEntries, 1);
      held.release();
    });

    test('a lease released after its entry went is harmless', () {
      final lease = pool.acquire('a', 100, 100)!;
      lease.release();
      pool.releaseUnpinned();

      expect(lease.release, returnsNormally);
    });
  });

  group('budget', () {
    test('the pool reports the byte budget it was given', () {
      expect(pool.budgetBytes, _budget);
    });

    test('pages sized by class are paid for in bytes', () {
      // A 128 class opens a 256 px page (256 KiB), a 64 class a 128 px page
      // (64 KiB): 384 KiB pays for one page of the first and two of the
      // second, not for a second page of the first.
      final sized = FramePool<String>(
        pageSideFor: (c) => 2 * c,
        budgetBytes: 384 * 1024,
        sizeClasses: const [64, 128],
      );
      for (var i = 0; i < 4; i++) {
        sized.acquire('big$i', 100, 100);
      }
      for (var i = 0; i < 8; i++) {
        sized.acquire('small$i', 50, 50);
      }

      expect(sized.residentEntries, 12);
      expect(sized.acquire('big', 100, 100), isNull);
      expect(sized.acquire('small', 50, 50), isNull);
    });

    test('a budget under one page is an error', () {
      expect(
        () => FramePool<String>(pageSideFor: (_) => 256, budgetBytes: 1000),
        throwsArgumentError,
      );
    });
  });

  group('pages', () {
    test('a page is announced when its last entry is evicted', () {
      final pages = <int>[];
      final watched = FramePool<String>(
        pageSideFor: (_) => 256,
        budgetBytes: _budget,
        sizeClasses: const [128, 256],
        onPageReleased: pages.add,
      );
      for (var i = 0; i < 4; i++) {
        watched.acquire('a$i', 100, 100)!.release();
      }
      expect(pages, isEmpty);

      watched.releaseUnpinned();

      expect(pages, [0]);
    });
  });
}

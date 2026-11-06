import 'dart:ui';

import 'package:catalog_assets/frame_pool.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two pages' worth of bytes at 256 px a page.
const _twoPages = 2 * 256 * 256 * 4;

/// A 256 px page holds sixteen 64 px cells or four 128 px cells; two pages in
/// all, so every limit is reached with a handful of allocations.
FrameSlotAllocator _allocator() => FrameSlotAllocator(
  pageSideFor: (_) => 256,
  budgetBytes: _twoPages,
  sizeClasses: const [64, 128],
);

bool _overlaps(FrameSlot a, FrameSlot b) =>
    a.pageIndex == b.pageIndex && a.rect.overlaps(b.rect);

void main() {
  late FrameSlotAllocator allocator;

  setUp(() => allocator = _allocator());

  group('size classes', () {
    test('a slot is the smallest class cell that holds the size', () {
      final slot = allocator.allocate(50, 60)!;

      expect(slot.rect, const Rect.fromLTWH(0, 0, 64, 64));
    });

    test('the longer side picks the class', () {
      final slot = allocator.allocate(64, 100)!;

      expect(slot.rect.size, const Size(128, 128));
    });

    test('a size above the largest class is an error, not a null', () {
      expect(() => allocator.allocate(129, 10), throwsArgumentError);
    });

    test('a size without pixels is an error', () {
      expect(() => allocator.allocate(0, 10), throwsArgumentError);
      expect(() => allocator.allocate(10, -1), throwsArgumentError);
    });
  });

  group('packing', () {
    test('slots on one page never overlap and stay inside it', () {
      final slots = [for (var i = 0; i < 16; i++) allocator.allocate(64, 64)!];

      for (final slot in slots) {
        expect(slot.pageIndex, 0);
        expect(
          slot.rect,
          predicate<Rect>(
            (r) =>
                r.left >= 0 && r.top >= 0 && r.right <= 256 && r.bottom <= 256,
          ),
        );
      }
      for (var i = 0; i < slots.length; i++) {
        for (var j = i + 1; j < slots.length; j++) {
          expect(_overlaps(slots[i], slots[j]), isFalse, reason: '$i vs $j');
        }
      }
    });

    test('a full page opens the next one of the same class', () {
      for (var i = 0; i < 16; i++) {
        allocator.allocate(64, 64);
      }

      final next = allocator.allocate(64, 64)!;

      expect(next.pageIndex, 1);
      expect(allocator.pageCount, 2);
    });

    test('a page serves one class: another class opens a page of its own', () {
      allocator.allocate(64, 64);

      final big = allocator.allocate(128, 128)!;

      expect(big.pageIndex, 1);
    });
  });

  group('budget', () {
    test('no free cell and no page left answers null', () {
      for (var i = 0; i < 16; i++) {
        allocator.allocate(64, 64);
      }
      for (var i = 0; i < 4; i++) {
        allocator.allocate(128, 128);
      }

      expect(allocator.allocate(64, 64), isNull);
      expect(allocator.allocate(128, 128), isNull);
    });

    test('a released cell is handed out again', () {
      final first = allocator.allocate(64, 64)!;
      allocator.allocate(64, 64);

      allocator.release(first);

      expect(allocator.allocate(64, 64)!.rect, first.rect);
    });

    test('a page left with no slot goes back to the budget', () {
      final small = allocator.allocate(64, 64)!;
      allocator.allocate(128, 128);
      expect(allocator.pageCount, 2);

      allocator.release(small);

      expect(allocator.pageCount, 1);
      // The budget is two pages again: seven 128 px cells fit (three beside
      // the slot already held, four on a new page) and the eighth does not.
      for (var i = 0; i < 7; i++) {
        expect(allocator.allocate(128, 128), isNotNull, reason: 'cell $i');
      }
      expect(allocator.allocate(128, 128), isNull);
    });

    test('a page index is never reused, so a stale slot cannot alias', () {
      final first = allocator.allocate(64, 64)!;
      allocator.release(first);

      final second = allocator.allocate(64, 64)!;

      expect(second.pageIndex, isNot(first.pageIndex));
    });
  });

  group('release', () {
    test('releasing a slot twice is a state error', () {
      final slot = allocator.allocate(64, 64)!;
      allocator.release(slot);

      expect(() => allocator.release(slot), throwsStateError);
    });

    test('releasing a slot of another allocator is a state error', () {
      final foreign = _allocator().allocate(64, 64)!;

      expect(() => allocator.release(foreign), throwsStateError);
    });

    test('usedSlots counts what is held', () {
      final a = allocator.allocate(64, 64)!;
      allocator.allocate(128, 128);
      expect(allocator.usedSlots, 2);

      allocator.release(a);

      expect(allocator.usedSlots, 1);
    });
  });

  group('page release', () {
    test('the page of the last released slot is announced once', () {
      final pages = <int>[];
      final watched = FrameSlotAllocator(
        pageSideFor: (_) => 256,
        budgetBytes: _twoPages,
        sizeClasses: const [64, 128],
        onPageReleased: pages.add,
      );
      final a = watched.allocate(64, 64)!;
      final b = watched.allocate(64, 64)!;

      watched.release(a);
      expect(pages, isEmpty, reason: 'b still holds the page');
      watched.release(b);

      expect(pages, [0]);
    });
  });

  group('page size by class', () {
    // Twice the class edge: at most four cells a page, so a playing sticker
    // uploads at most four times what changed.
    FrameSlotAllocator bySize({int budgetBytes = 48 * 1024 * 1024}) =>
        FrameSlotAllocator(pageSideFor: (c) => 2 * c, budgetBytes: budgetBytes);

    test('class 64 opens a 128 px page and class 512 a 1024 px one', () {
      final allocator = bySize();

      final small = allocator.allocate(50, 50)!;
      final large = allocator.allocate(500, 500)!;

      expect(small.pageSide, 128);
      expect(large.pageSide, 1024);
      expect(small.rect, const Rect.fromLTWH(0, 0, 64, 64));
      expect(large.rect, const Rect.fromLTWH(0, 0, 512, 512));
    });

    test('a page holds four cells, the fifth opens a new page', () {
      final allocator = bySize();
      final slots = [for (var i = 0; i < 5; i++) allocator.allocate(64, 64)!];

      expect(slots.take(4).map((s) => s.pageIndex), everyElement(0));
      expect(slots[4].pageIndex, 1);
      expect(
        slots.take(4).map((s) => s.rect.topLeft),
        containsAll(const <Offset>[
          Offset.zero,
          Offset(64, 0),
          Offset(0, 64),
          Offset(64, 64),
        ]),
      );
    });

    test('page bytes count against the budget', () {
      final allocator = bySize();

      allocator.allocate(64, 64);
      expect(allocator.pageBytes, 128 * 128 * 4);
      allocator.allocate(512, 512);

      expect(allocator.pageBytes, 128 * 128 * 4 + 1024 * 1024 * 4);
      expect(
        allocator.usedBytes,
        64 * 64 * 4 + 512 * 512 * 4,
        reason: 'one cell of each is held',
      );
    });

    test('a budget of three 128 px pages opens exactly three of them', () {
      final allocator = bySize(budgetBytes: 3 * 128 * 128 * 4);

      final slots = [for (var i = 0; i < 12; i++) allocator.allocate(64, 64)!];

      expect(slots.map((s) => s.pageIndex).toSet(), {0, 1, 2});
      expect(allocator.allocate(64, 64), isNull);
      // 128 px page = 64 KiB, so no 256-class page (256 KiB) fits either.
      expect(allocator.allocate(128, 128), isNull);
    });

    test('a class whose page is above the budget answers null', () {
      final allocator = bySize(budgetBytes: 1024 * 1024);

      expect(allocator.allocate(512, 512), isNull);
      expect(allocator.allocate(256, 256), isNotNull);
    });

    test('a released page gives its bytes back', () {
      final allocator = bySize();
      final slot = allocator.allocate(256, 256)!;
      expect(allocator.pageBytes, 512 * 512 * 4);

      allocator.release(slot);

      expect(allocator.pageBytes, 0);
      expect(allocator.usedBytes, 0);
    });

    test('a budget below the smallest page is an argument error', () {
      expect(
        () => FrameSlotAllocator(
          pageSideFor: (c) => 2 * c,
          budgetBytes: 128 * 128 * 4 - 1,
        ),
        throwsArgumentError,
      );
    });

    test('a class that does not divide its page is an argument error', () {
      expect(
        () => FrameSlotAllocator(pageSideFor: (_) => 200, budgetBytes: 1 << 20),
        throwsArgumentError,
      );
    });

    test('the slot carries its page side in its value', () {
      final allocator = bySize();
      final slot = allocator.allocate(64, 64)!;

      expect(slot.pageSide, 128);
      expect(slot.toString(), contains('128'));
    });
  });
}

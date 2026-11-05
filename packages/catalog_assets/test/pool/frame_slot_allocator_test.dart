import 'dart:ui';

import 'package:catalog_assets/frame_pool.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 256 px page holds sixteen 64 px cells or four 128 px cells; two pages in
/// all, so every limit is reached with a handful of allocations.
FrameSlotAllocator _allocator() => FrameSlotAllocator(
  pageSide: 256,
  maxPages: 2,
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
}

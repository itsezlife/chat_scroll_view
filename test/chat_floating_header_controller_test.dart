import 'package:chatscrollview/src/chat_scroll/chat_floating_header_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dividerOpacityFor', () {
    test('full opacity below fade band', () {
      final controller = ChatFloatingHeaderController();
      // topPad=10, headerHeight=32 → fadeEnd=42; topY=62 → (20/20+1) clamped to 1
      expect(
        controller.dividerOpacityFor(
          topY: 62,
          topPad: 10,
          floatingHeaderHeight: 32,
        ),
        1.0,
      );
    });

    test('zero opacity at fade end minus band', () {
      final controller = ChatFloatingHeaderController();
      // fadeEnd=42; topY=22 → (-20/20+1)=0
      expect(
        controller.dividerOpacityFor(
          topY: 22,
          topPad: 10,
          floatingHeaderHeight: 32,
        ),
        0.0,
      );
    });
  });

  group('evaluateLayoutRebuild', () {
    test('rebuilds when bucket changes', () {
      final controller = ChatFloatingHeaderController();
      final day = DateTime(2026, 1, 2);

      final first = controller.evaluateLayoutRebuild(
        scan: (bucket: 'a', id: 1),
        groupBy: (_) => 'a',
        createdAtOf: (_) => day,
      );
      expect(first.needsRebuild, isTrue);
      expect(first.buildDate, day);
      expect(controller.headerBucket, 'a');

      final second = controller.evaluateLayoutRebuild(
        scan: (bucket: 'a', id: 1),
        groupBy: (_) => 'a',
        createdAtOf: (_) => day,
      );
      expect(second.needsRebuild, isFalse);
    });

    test('rebuilds when headerDirty', () {
      final controller = ChatFloatingHeaderController()
        ..headerBucket = 'a'
        ..headerDirty = true;

      final result = controller.evaluateLayoutRebuild(
        scan: (bucket: 'a', id: 1),
        groupBy: (_) => 'a',
        createdAtOf: (_) => DateTime(2026),
      );
      expect(result.needsRebuild, isTrue);
      expect(controller.headerDirty, isFalse);
    });

    test('no header when groupBy is null', () {
      final controller = ChatFloatingHeaderController()
        ..headerBucket = 'a'
        ..headerDate = DateTime(2026);

      final result = controller.evaluateLayoutRebuild(
        scan: (bucket: 'a', id: 1),
        groupBy: null,
        createdAtOf: (_) => DateTime(2026),
      );
      expect(result.needsRebuild, isTrue);
      expect(result.buildDate, isNull);
      expect(controller.headerBucket, isNull);
    });
  });

  group('tickForDayChange', () {
    test('returns true when bucket changes', () {
      final controller = ChatFloatingHeaderController()..headerBucket = 'a';
      expect(
        controller.tickForDayChange(
          scan: (bucket: 'b', id: 2),
          groupBy: (_) => 'b',
          hasFloatingHeader: true,
        ),
        isTrue,
      );
    });

    test('returns false when bucket unchanged', () {
      final controller = ChatFloatingHeaderController()..headerBucket = 'a';
      expect(
        controller.tickForDayChange(
          scan: (bucket: 'a', id: 1),
          groupBy: (_) => 'a',
          hasFloatingHeader: true,
        ),
        isFalse,
      );
    });
  });

  group('lifecycle', () {
    test('resetOnDataSourceChange clears bucket and sets dirty', () {
      final controller = ChatFloatingHeaderController()
        ..headerBucket = 'x'
        ..headerDate = DateTime(2026)
        ..headerDirty = false;

      controller.resetOnDataSourceChange();
      expect(controller.headerBucket, isNull);
      expect(controller.headerDate, isNull);
      expect(controller.headerDirty, isTrue);
    });

    test('clearForOverlay clears without dirty flag', () {
      final controller = ChatFloatingHeaderController()
        ..headerBucket = 'x'
        ..headerDirty = true;

      controller.clearForOverlay();
      expect(controller.headerBucket, isNull);
      expect(controller.headerDirty, isFalse);
    });
  });

  group('floatingHeaderHeight', () {
    test('uses fallback when header has no size', () {
      final controller = ChatFloatingHeaderController();
      expect(controller.floatingHeaderHeight(null), kHeaderFallbackHeight);
    });
  });

  group('placeHeaderOffset', () {
    test('returns topPad', () {
      final controller = ChatFloatingHeaderController();
      expect(controller.placeHeaderOffset(topPad: 24), 24);
    });
  });
}

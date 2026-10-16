import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/src/viewport/catalog_scroll_position.dart';

/// What a [CatalogScrollPosition] contract run needs besides the position.
final class CatalogScrollPositionHarness {
  /// Creates a harness around [position].
  const CatalogScrollPositionHarness({
    required this.position,
    required this.sectionCount,
    required this.settle,
  });

  /// The position under test, laid out with a content extent larger than its
  /// viewport and `pixels == 0`.
  final CatalogScrollPosition position;

  /// How many sections the position has (at least three).
  final int sectionCount;

  /// Lets every motion in flight run to its end (pumping frames for a real
  /// viewport).
  final Future<void> Function() settle;
}

/// The contract every [CatalogScrollPosition] meets; see its documentation.
///
/// [create] builds a fresh harness for each test. Offsets used stay inside
/// the valid range, so positions that clamp and positions that do not behave
/// alike.
void runCatalogScrollPositionContract(
  Future<CatalogScrollPositionHarness> Function(WidgetTester tester) create,
) {
  group('CatalogScrollPosition contract', () {
    testWidgets('keeps the max extent consistent with the other two', (
      tester,
    ) async {
      final harness = await create(tester);
      final position = harness.position;

      expect(position.contentExtent, greaterThan(position.viewportExtent));
      expect(
        position.maxScrollExtent,
        position.contentExtent - position.viewportExtent,
      );
    });

    testWidgets('jumpTo moves to the offset and repeating it is a no-op', (
      tester,
    ) async {
      final harness = await create(tester);
      final position = harness.position;

      position.jumpTo(120);
      expect(position.pixels, 120);

      position.jumpTo(120);
      expect(position.pixels, 120);
    });

    testWidgets('scrollBy adds to the offset and a zero delta does nothing', (
      tester,
    ) async {
      final harness = await create(tester);
      final position = harness.position;
      position.jumpTo(100);

      position
        ..scrollBy(30)
        ..scrollBy(-10)
        ..scrollBy(0);

      expect(position.pixels, 120);
    });

    testWidgets('animateTo arrives at the target and its future completes', (
      tester,
    ) async {
      final harness = await create(tester);
      final position = harness.position;

      final done = position.animateTo(
        200,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
      await harness.settle();
      await done;

      expect(position.pixels, 200);
    });

    testWidgets('a jump to a section is active until it ends', (tester) async {
      final harness = await create(tester);
      final position = harness.position;
      expect(position.isSectionJumpActive, isFalse);

      final done = position.jumpToSection(2);
      expect(position.isSectionJumpActive, isTrue);

      await harness.settle();
      await done;
      expect(position.isSectionJumpActive, isFalse);
      expect(position.pixels, greaterThan(0));
    });

    testWidgets('a second jump to a section while one is active is the same', (
      tester,
    ) async {
      final harness = await create(tester);
      final position = harness.position;

      final first = position.jumpToSection(1);
      final second = position.jumpToSection(2);

      expect(identical(first, second), isTrue);
      await harness.settle();
      await first;
    });

    testWidgets('a section out of range completes without moving', (
      tester,
    ) async {
      final harness = await create(tester);
      final position = harness.position;

      await position.jumpToSection(harness.sectionCount);
      await position.jumpToSection(-1);

      expect(position.pixels, 0);
      expect(position.isSectionJumpActive, isFalse);
    });
  });
}

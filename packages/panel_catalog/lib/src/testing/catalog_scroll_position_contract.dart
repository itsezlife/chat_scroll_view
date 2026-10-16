import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/src/model/catalog_leaf_hit.dart';
import 'package:panel_catalog/src/viewport/catalog_focus.dart';
import 'package:panel_catalog/src/viewport/catalog_scroll_position.dart';

/// What a [CatalogScrollPosition] contract run needs besides the position.
final class CatalogScrollPositionHarness {
  /// Creates a harness around [position].
  const CatalogScrollPositionHarness({
    required this.position,
    required this.sectionCount,
    required this.settle,
    required this.leafCounts,
    required this.activations,
  });

  /// The position under test, laid out with a content extent larger than its
  /// viewport and `pixels == 0`.
  final CatalogScrollPosition position;

  /// How many sections the position has (at least three).
  final int sectionCount;

  /// Leaves per section: section `s<i>` holds `leafCounts[i]` leaves, laid out
  /// in a grid of at least two columns. At least two sections of two leaves.
  final List<int> leafCounts;

  /// Every cell the shell's tap received so far, in order: what the position
  /// reports when it activates the focused cell.
  final List<CatalogLeafHit> Function() activations;

  /// Lets every motion in flight run to its end (pumping frames for a real
  /// viewport).
  final Future<void> Function() settle;
}

/// The contract every [CatalogScrollPosition] meets; see its documentation.
abstract final class CatalogScrollPositionContract {
  /// Registers the contract's tests against the positions [create] builds.
  ///
  /// [create] builds a fresh harness for each test. Offsets used stay inside
  /// the valid range, so positions that clamp and positions that do not behave
  /// alike.
  static void run(
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

      testWidgets('a jump to a section is active until it ends', (
        tester,
      ) async {
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

      testWidgets(
        'a second jump to a section while one is active is the same',
        (tester) async {
          final harness = await create(tester);
          final position = harness.position;

          final first = position.jumpToSection(1);
          final second = position.jumpToSection(2);

          expect(identical(first, second), isTrue);
          await harness.settle();
          await first;
        },
      );

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

      group('focus', () {
        testWidgets('starts with nothing focused', (tester) async {
          final harness = await create(tester);

          expect(harness.position.focusedLeaf, isNull);
          expect(harness.position.activateFocusedLeaf(), isFalse);
        });

        testWidgets('focusing a cell names it', (tester) async {
          final harness = await create(tester);
          final position = harness.position;

          expect(position.focusLeaf('s1', 1, reveal: true), isTrue);

          expect(position.focusedLeaf?.sectionId, 's1');
          expect(position.focusedLeaf?.index, 1);
        });

        testWidgets('a cell that does not exist is refused', (tester) async {
          final harness = await create(tester);
          final position = harness.position;
          position.focusLeaf('s0', 0, reveal: true);

          expect(position.focusLeaf('nope', 0, reveal: true), isFalse);
          expect(position.focusLeaf('s0', -1, reveal: true), isFalse);
          expect(
            position.focusLeaf('s0', harness.leafCounts[0], reveal: true),
            isFalse,
          );

          expect(position.focusedLeaf?.sectionId, 's0');
          expect(position.focusedLeaf?.index, 0);
        });

        testWidgets('next and previous follow reading order across sections', (
          tester,
        ) async {
          final harness = await create(tester);
          final position = harness.position;
          final last = harness.leafCounts[0] - 1;
          position.focusLeaf('s0', last, reveal: true);

          expect(position.moveFocus(CatalogFocusMove.next), isTrue);
          expect(position.focusedLeaf?.sectionId, 's1');
          expect(position.focusedLeaf?.index, 0);

          expect(position.moveFocus(CatalogFocusMove.previous), isTrue);
          expect(position.focusedLeaf?.sectionId, 's0');
          expect(position.focusedLeaf?.index, last);
        });

        testWidgets('first and last go to the ends and stay there', (
          tester,
        ) async {
          final harness = await create(tester);
          final position = harness.position;
          final lastSection = harness.leafCounts.length - 1;

          expect(position.moveFocus(CatalogFocusMove.last), isTrue);
          expect(position.focusedLeaf?.sectionId, 's$lastSection');
          expect(position.focusedLeaf?.index, harness.leafCounts.last - 1);
          expect(position.moveFocus(CatalogFocusMove.next), isFalse);

          expect(position.moveFocus(CatalogFocusMove.first), isTrue);
          expect(position.focusedLeaf?.sectionId, 's0');
          expect(position.focusedLeaf?.index, 0);
          expect(position.moveFocus(CatalogFocusMove.previous), isFalse);
          expect(position.focusedLeaf?.index, 0);
        });

        testWidgets('activating reports the focused cell to the shell', (
          tester,
        ) async {
          final harness = await create(tester);
          final position = harness.position;
          position.focusLeaf('s1', 1, reveal: true);

          expect(position.activateFocusedLeaf(), isTrue);

          final hit = harness.activations().single;
          expect(hit.sectionId, 's1');
          expect(hit.index, 1);
          expect(hit, position.focusedLeaf);
        });

        testWidgets('clearing ends focus and is repeatable', (tester) async {
          final harness = await create(tester);
          final position = harness.position;
          position.focusLeaf('s0', 1, reveal: true);

          position
            ..clearFocus()
            ..clearFocus();

          expect(position.focusedLeaf, isNull);
          expect(position.activateFocusedLeaf(), isFalse);
        });
      });
    });
  }
}

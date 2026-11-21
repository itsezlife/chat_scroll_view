import 'package:flutter_test/flutter_test.dart';
import 'package:viewport_scroll/src/fast_scroll_target.dart';

/// One [FastScrollTarget] under test, made fresh for each contract test.
final class FastScrollTargetHarness {
  /// A harness around [target].
  const FastScrollTargetHarness({
    required this.target,
    required this.settle,
    this.tolerance = 0.01,
  });

  /// The target, on content longer than its view, at the content's start.
  final FastScrollTarget target;

  /// Lets the engine apply what it was asked (pumps frames for a real
  /// viewport).
  final Future<void> Function() settle;

  /// How far a reached [FastScrollTarget.progress] may be from the asked
  /// one: an engine that estimates its length lands near it, not on it.
  final double tolerance;
}

/// The contract every [FastScrollTarget] meets.
abstract final class FastScrollTargetContract {
  /// Registers the contract's tests against the targets [create] builds.
  static void run(
    Future<FastScrollTargetHarness> Function(WidgetTester tester) create,
  ) {
    testWidgets('at the start: progress 0, a share of the content in view', (
      tester,
    ) async {
      final h = await create(tester);
      expect(h.target.progress, closeTo(0, h.tolerance));
      expect(h.target.visibleShare, inExclusiveRange(0, 1));
    });

    testWidgets('jumpTo reaches the progress asked and notifies', (
      tester,
    ) async {
      final h = await create(tester);
      var notified = 0;
      void count() => notified++;
      h.target.addListener(count);
      addTearDown(() => h.target.removeListener(count));
      h.target.jumpTo(0.5);
      await h.settle();
      expect(h.target.progress, closeTo(0.5, h.tolerance));
      expect(notified, greaterThan(0));
      h.target.jumpTo(1);
      await h.settle();
      expect(h.target.progress, closeTo(1, h.tolerance));
    });

    testWidgets('jumpTo clamps to the content', (tester) async {
      final h = await create(tester);
      h.target.jumpTo(3);
      await h.settle();
      expect(h.target.progress, closeTo(1, h.tolerance));
      h.target.jumpTo(-1);
      await h.settle();
      expect(h.target.progress, closeTo(0, h.tolerance));
    });

    testWidgets('stop moves nothing', (tester) async {
      final h = await create(tester);
      h.target.jumpTo(0.3);
      await h.settle();
      final before = h.target.progress;
      h.target
        ..stop()
        ..dragStarted()
        ..dragEnded();
      await h.settle();
      expect(h.target.progress, closeTo(before!, 1e-6));
    });
  }
}

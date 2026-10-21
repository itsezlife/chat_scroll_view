import 'package:catalog_assets/src/atlas/bake_frame_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// A source under test and the way to make it produce one frame.
typedef BakeFrameSourceHarness = ({
  BakeFrameSource source,
  Future<void> Function() nextFrame,
});

/// Behaviour every [BakeFrameSource] must have, for adapter authors and hosts.
abstract final class BakeFrameSourceContract {
  /// Runs it as a test group. [create] makes a fresh source for the widget
  /// test's [WidgetTester] together with a function that runs one frame (for a
  /// binding-backed source, `tester.pump`; for a fake, its manual pump).
  static void run(
    String name,
    BakeFrameSourceHarness Function(WidgetTester tester) create,
  ) {
    group('BakeFrameSource contract: $name', () {
      testWidgets('does not call back inside requestFrame', (tester) async {
        final harness = create(tester);
        var calls = 0;

        harness.source.requestFrame((_) => calls++);

        expect(calls, 0);
        await harness.nextFrame();
      });

      testWidgets('calls back once, on the next frame', (tester) async {
        final harness = create(tester);
        final frames = <BakeFrame>[];
        harness.source.requestFrame(frames.add);

        await harness.nextFrame();
        await harness.nextFrame();

        expect(frames, hasLength(1));
        expect(frames.single.budget, greaterThan(Duration.zero));
      });

      testWidgets('a cancelled request never calls back', (tester) async {
        final harness = create(tester);
        var calls = 0;

        harness.source.requestFrame((_) => calls++)();
        await harness.nextFrame();

        expect(calls, 0);
      });

      testWidgets('cancelling after the frame, or twice, does nothing', (
        tester,
      ) async {
        final harness = create(tester);
        var calls = 0;
        final cancel = harness.source.requestFrame((_) => calls++);
        await harness.nextFrame();

        cancel();
        cancel();

        expect(calls, 1);
      });

      testWidgets('independent requests each get their frame', (tester) async {
        final harness = create(tester);
        var a = 0;
        var b = 0;
        harness.source
          ..requestFrame((_) => a++)
          ..requestFrame((_) => b++);

        await harness.nextFrame();

        expect([a, b], [1, 1]);
      });
    });
  }
}

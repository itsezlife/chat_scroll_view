import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/src/viewport/catalog_overscroll_sink.dart';

/// What a [CatalogOverscrollSink] contract run needs besides the sink.
final class CatalogOverscrollSinkHarness {
  /// Creates a harness around [sink].
  const CatalogOverscrollSinkHarness({
    required this.sink,
    required this.settle,
  });

  /// The sink under test, its receiver at rest and holding nothing.
  final CatalogOverscrollSink sink;

  /// Lets whatever the receiver started on a release run to its end
  /// (pumping frames for a widget).
  final Future<void> Function() settle;
}

/// What the viewport relies on from every receiver behind a
/// [CatalogOverscrollSink]: it never takes more than it is offered, it moves
/// before content in both directions while it holds something, and it says
/// truly whether it took a release.
///
/// Offers stay small (under a centimetre), so a receiver that acts on
/// distance (a sheet that closes past a threshold) behaves alike.
abstract final class CatalogOverscrollSinkContract {
  /// Registers the contract's tests against the sinks [create] builds.
  static void run(
    Future<CatalogOverscrollSinkHarness> Function(WidgetTester tester) create,
  ) {
    group('CatalogOverscrollSink contract', () {
      testWidgets('takes no more of a pull than it is offered', (tester) async {
        final sink = (await create(tester)).sink;
        sink.onStart?.call();

        final taken = sink.onDelta(12);

        expect(taken, inInclusiveRange(0, 12));
      });

      testWidgets('declines a push toward content while it holds nothing', (
        tester,
      ) async {
        final sink = (await create(tester)).sink;
        sink.onStart?.call();

        expect(sink.onDelta(-12), 0);
      });

      testWidgets('gives back what it holds before it declines', (
        tester,
      ) async {
        final sink = (await create(tester)).sink;
        sink.onStart?.call();
        final held = sink.onDelta(12);

        expect(sink.onDelta(-20), -held);
        expect(sink.onDelta(-5), 0);
      });

      testWidgets('takes the release of a drag it still holds part of, then '
          'holds nothing', (tester) async {
        final harness = await create(tester);
        final sink = harness.sink;
        sink.onStart?.call();
        final held = sink.onDelta(6);
        expect(held, greaterThan(0));

        expect(sink.onEnd(0), isTrue);
        await harness.settle();

        sink.onStart?.call();
        expect(sink.onDelta(-6), 0);
      });

      testWidgets('leaves the release to content once it gave all back', (
        tester,
      ) async {
        final harness = await create(tester);
        final sink = harness.sink;
        sink.onStart?.call();
        final held = sink.onDelta(6);
        sink.onDelta(-held);

        expect(sink.onEnd(-200), isFalse);
      });
    });
  }
}

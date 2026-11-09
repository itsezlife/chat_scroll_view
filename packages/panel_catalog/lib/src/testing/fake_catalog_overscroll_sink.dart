import 'package:panel_catalog/src/viewport/catalog_overscroll_sink.dart';

/// A receiver behind a [CatalogOverscrollSink] that records what the viewport
/// offered it and holds what it took, like a sheet pulled down by hand.
///
/// A pull (positive offer) is taken up to [capacity]; a push back (negative
/// offer) gives back what is held, and nothing more. A release is taken when
/// anything is held, and lets it go at once.
final class FakeCatalogOverscrollSink {
  /// A receiver that takes pulls up to [capacity] and waits [restBeforePull]
  /// after content moved.
  FakeCatalogOverscrollSink({
    this.capacity = double.infinity,
    this.restBeforePull = Duration.zero,
  });

  /// The most it holds at once.
  double capacity;

  /// Passed to the sink.
  final Duration restBeforePull;

  /// Every offer, in order.
  final List<double> offers = [];

  /// Every release velocity, in order.
  final List<double> releases = [];

  /// How many drags started.
  int starts = 0;

  /// What it holds now.
  double held = 0;

  /// The sum of [offers].
  double get offeredTotal => offers.fold(0, (sum, offer) => sum + offer);

  /// The sink to hand the viewport.
  late final CatalogOverscrollSink sink = CatalogOverscrollSink(
    restBeforePull: restBeforePull,
    onStart: () => starts++,
    onDelta: (pixels) {
      offers.add(pixels);
      final taken = pixels > 0
          ? (capacity - held).clamp(0.0, pixels)
          : (-held).clamp(pixels, 0.0);
      held += taken;
      return taken;
    },
    onEnd: (velocity) {
      releases.add(velocity);
      final took = held > 0;
      held = 0;
      return took;
    },
  );
}

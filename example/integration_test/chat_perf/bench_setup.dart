/// How a bench host's data source is built: pure Dart, shared by the
/// registry (a scenario names the setup it needs) and the device host.
library;

/// The latency profile of the data source's `fetchRange`.
enum BenchLatency {
  /// Resolves in a microtask.
  instant,

  /// A mobile-network-like delay with seeded jitter: a pure function of the
  /// requested range, so every launch sees the same delays.
  network;

  /// The delay of the fetch starting at [fromId].
  Duration delayFor(int fromId) => switch (this) {
    instant => Duration.zero,
    network => Duration(milliseconds: 60 + _jitter(fromId) % 120),
  };
}

int _jitter(int fromId) {
  var h = (fromId * 0x45d9f3b + 0x119de1f3) & 0xffffffff;
  h = ((h >> 16) ^ h) * 0x45d9f3b & 0xffffffff;
  return (h >> 16) ^ h;
}

/// What a scenario needs from the bench host's data source.
final class BenchSetup {
  const BenchSetup({this.latency = BenchLatency.instant, this.lazy = false});

  final BenchLatency latency;

  /// `true` seeds only the boundaries; chunks are fetched on demand. `false`
  /// seeds the whole history up front.
  final bool lazy;
}

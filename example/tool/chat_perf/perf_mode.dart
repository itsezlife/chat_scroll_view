/// The device's performance mode during a launch. Pure Dart.
///
/// Without it a phone's CPU and GPU frequency governors decide the clocks, and
/// the same code measured hours apart can differ by 1.6x on build and raster
/// p99 with no other observable change (display rate, battery, thermal status,
/// memory and foreign processes were all ruled out). The platform's fixed
/// performance mode pins the clocks, which makes runs comparable at the price
/// of numbers that are not what a user's phone in its default state shows.
library;

/// Which performance mode a run requests.
enum PerfMode {
  /// Pin the clocks for the run, restore afterwards (the default).
  fixed,

  /// Leave the device's governors alone.
  system;

  /// Parses a `--perf-mode` value; empty means the default, [fixed].
  static PerfMode parse(String value) {
    if (value.isEmpty) return fixed;
    for (final mode in values) {
      if (mode.name == value) return mode;
    }
    throw FormatException('perf-mode must be fixed or system', value);
  }
}

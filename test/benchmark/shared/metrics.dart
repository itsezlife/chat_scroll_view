import 'dart:math';

/// Collected timing samples for a single benchmark scenario.
class BenchmarkMetrics {
  BenchmarkMetrics(this.name, this.samples);

  final String name;
  final List<int> samples; // microseconds

  late final List<int> _sorted = [...samples]..sort();

  int get count => samples.length;

  double get meanUs => samples.isEmpty
      ? 0
      : samples.reduce((a, b) => a + b) / samples.length;

  double get medianUs {
    if (_sorted.isEmpty) return 0;
    final mid = _sorted.length ~/ 2;
    return _sorted.length.isOdd
        ? _sorted[mid].toDouble()
        : (_sorted[mid - 1] + _sorted[mid]) / 2.0;
  }

  double get p95Us => _percentile(0.95);
  double get p99Us => _percentile(0.99);
  int get minUs => _sorted.isEmpty ? 0 : _sorted.first;
  int get maxUs => _sorted.isEmpty ? 0 : _sorted.last;

  double get stdDevUs {
    if (samples.length < 2) return 0;
    final m = meanUs;
    final variance =
        samples.map((s) => (s - m) * (s - m)).reduce((a, b) => a + b) /
            (samples.length - 1);
    return sqrt(variance);
  }

  /// Frames exceeding 16.67ms (60 FPS budget).
  int get jankCount => samples.where((s) => s > 16667).length;
  double get jankRatio =>
      samples.isEmpty ? 0 : jankCount / samples.length;

  double _percentile(double p) {
    if (_sorted.isEmpty) return 0;
    final index = (p * (_sorted.length - 1)).round();
    return _sorted[index].toDouble();
  }

  String _fmtUs(double us) {
    if (us >= 1000) return '${(us / 1000).toStringAsFixed(2)}ms';
    return '${us.toStringAsFixed(1)}µs';
  }

  @override
  String toString() => '$name: mean=${_fmtUs(meanUs)} '
      'median=${_fmtUs(medianUs)} p95=${_fmtUs(p95Us)} '
      'p99=${_fmtUs(p99Us)} min=${_fmtUs(minUs.toDouble())} '
      'max=${_fmtUs(maxUs.toDouble())}';
}

/// Memory snapshot at a point in time.
class MemorySnapshot {
  const MemorySnapshot({
    required this.label,
    this.attachedRenders = 0,
    this.totalRenders = 0,
    this.chunkCount = 0,
    this.elementCount = 0,
    this.renderObjectCount = 0,
  });

  final String label;
  final int attachedRenders;
  final int totalRenders;
  final int chunkCount;
  final int elementCount;
  final int renderObjectCount;

  @override
  String toString() => '$label: attached=$attachedRenders '
      'total=$totalRenders chunks=$chunkCount '
      'elements=$elementCount renderObjects=$renderObjectCount';
}

/// Generate a markdown comparison table for two sets of metrics.
String generateComparisonTable({
  required String title,
  required List<(int messageCount, BenchmarkMetrics csv, BenchmarkMetrics lv)>
      rows,
}) {
  final buf = StringBuffer()
    ..writeln('### $title')
    ..writeln()
    ..writeln(
        '| Messages | Metric | ChatScrollView | ListView.builder | Ratio |')
    ..writeln(
        '|----------|--------|----------------|------------------|-------|');

  for (final (count, csv, lv) in rows) {
    void row(String metric, double csvVal, double lvVal) {
      final ratio = lvVal > 0 ? csvVal / lvVal : double.nan;
      buf.writeln(
        '| $count | $metric | ${_fmtUs(csvVal)} | ${_fmtUs(lvVal)} '
        '| ${ratio.toStringAsFixed(2)}x |',
      );
    }

    row('mean', csv.meanUs, lv.meanUs);
    row('median', csv.medianUs, lv.medianUs);
    row('p95', csv.p95Us, lv.p95Us);
    row('p99', csv.p99Us, lv.p99Us);
  }

  buf.writeln();
  return buf.toString();
}

/// Generate markdown for memory comparison.
String generateMemoryTable({
  required String title,
  required List<(int messageCount, MemorySnapshot csv, MemorySnapshot lv)>
      rows,
}) {
  final buf = StringBuffer()
    ..writeln('### $title')
    ..writeln()
    ..writeln(
        '| Messages | Metric | ChatScrollView | ListView.builder |')
    ..writeln(
        '|----------|--------|----------------|------------------|');

  for (final (count, csv, lv) in rows) {
    buf
      ..writeln(
          '| $count | Attached renders / Visible elements | '
          '${csv.attachedRenders} | ${lv.elementCount} |')
      ..writeln(
          '| $count | Total renders / RenderObjects | '
          '${csv.totalRenders} | ${lv.renderObjectCount} |')
      ..writeln(
          '| $count | Chunks / — | ${csv.chunkCount} | — |');
  }

  buf.writeln();
  return buf.toString();
}

String _fmtUs(double us) {
  if (us >= 1000) return '${(us / 1000).toStringAsFixed(2)}ms';
  return '${us.toStringAsFixed(1)}µs';
}

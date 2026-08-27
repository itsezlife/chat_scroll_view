import 'dart:math';

/// Collected timing samples for a single benchmark scenario.
///
/// Mirrors the chat-scroll [BenchmarkMetrics] contract (mean / median / p95 /
/// p99 / min / max / jank vs 16.67ms) so panel A/B reports stay comparable.
class BenchmarkMetrics {
  /// Creates metrics over [samples] in microseconds.
  BenchmarkMetrics(this.name, this.samples);

  /// Scenario label printed in reports.
  final String name;

  /// Per-sample wall times in microseconds.
  final List<int> samples;

  late final List<int> _sorted = [...samples]..sort();

  /// Number of samples.
  int get count => samples.length;

  /// Arithmetic mean in microseconds.
  double get meanUs =>
      samples.isEmpty ? 0 : samples.reduce((a, b) => a + b) / samples.length;

  /// Median in microseconds.
  double get medianUs {
    if (_sorted.isEmpty) return 0;
    final mid = _sorted.length ~/ 2;
    return _sorted.length.isOdd
        ? _sorted[mid].toDouble()
        : (_sorted[mid - 1] + _sorted[mid]) / 2.0;
  }

  /// 95th percentile in microseconds.
  double get p95Us => _percentile(0.95);

  /// 99th percentile in microseconds.
  double get p99Us => _percentile(0.99);

  /// Minimum sample in microseconds.
  int get minUs => _sorted.isEmpty ? 0 : _sorted.first;

  /// Maximum sample in microseconds.
  int get maxUs => _sorted.isEmpty ? 0 : _sorted.last;

  /// Sample standard deviation in microseconds.
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

  /// Fraction of samples that janked (`0`…`1`).
  double get jankRatio => samples.isEmpty ? 0 : jankCount / samples.length;

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
  String toString() =>
      '$name: mean=${_fmtUs(meanUs)} '
      'median=${_fmtUs(medianUs)} p95=${_fmtUs(p95Us)} '
      'p99=${_fmtUs(p99Us)} min=${_fmtUs(minUs.toDouble())} '
      'max=${_fmtUs(maxUs.toDouble())} '
      'jank=$jankCount/$count (${(jankRatio * 100).toStringAsFixed(1)}%)';
}

/// Live object snapshot for catalog body comparisons.
class CatalogMemorySnapshot {
  /// Creates a labeled count snapshot.
  const CatalogMemorySnapshot({
    required this.label,
    this.attachedLeaves = 0,
    this.visibleCells = 0,
    this.renderObjectCount = 0,
  });

  /// Scenario label.
  final String label;

  /// Candidate: leaves retained via asset-cache attach.
  final int attachedLeaves;

  /// Baseline: mounted glyph-cell elements (skipOffstage: false).
  final int visibleCells;

  /// Full [MaterialApp] tree [RenderObject] count.
  final int renderObjectCount;

  @override
  String toString() =>
      '$label: attachedLeaves=$attachedLeaves '
      'visibleCells=$visibleCells renderObjects=$renderObjectCount';
}

/// Markdown comparison table for candidate vs baseline timing rows.
///
/// [rows] are `(catalogLeafCount, candidate, baseline)`. Ratio is
/// candidate/baseline (`< 1` means candidate is faster).
String generateCatalogComparisonTable({
  required String title,
  required List<
    (int leafCount, BenchmarkMetrics candidate, BenchmarkMetrics baseline)
  >
  rows,
  String baselineLabel = 'SuperSliverList + cells',
}) {
  final buf = StringBuffer()
    ..writeln('### $title')
    ..writeln()
    ..writeln(
      '| Leaves | Metric | Panel Catalog Viewport | $baselineLabel | Ratio |',
    )
    ..writeln(
      '|--------|--------|------------------------|${'-' * (baselineLabel.length + 2)}|-------|',
    );

  for (final (count, cand, base) in rows) {
    void row(String metric, double candVal, double baseVal) {
      final ratio = baseVal > 0 ? candVal / baseVal : double.nan;
      buf.writeln(
        '| $count | $metric | ${_fmtUs(candVal)} | ${_fmtUs(baseVal)} '
        '| ${ratio.toStringAsFixed(2)}x |',
      );
    }

    row('mean', cand.meanUs, base.meanUs);
    row('median', cand.medianUs, base.medianUs);
    row('p95', cand.p95Us, base.p95Us);
    row('p99', cand.p99Us, base.p99Us);
    row('max', cand.maxUs.toDouble(), base.maxUs.toDouble());
    buf.writeln(
      '| $count | jank | ${cand.jankCount}/${cand.count} '
      '(${(cand.jankRatio * 100).toStringAsFixed(1)}%) | '
      '${base.jankCount}/${base.count} '
      '(${(base.jankRatio * 100).toStringAsFixed(1)}%) | — |',
    );
  }

  buf.writeln();
  return buf.toString();
}

/// Markdown table for memory snapshots.
String generateCatalogMemoryTable({
  required String title,
  required List<
    (
      int leafCount,
      CatalogMemorySnapshot candidate,
      CatalogMemorySnapshot baseline,
    )
  >
  rows,
  String baselineLabel = 'SuperSliverList + cells',
}) {
  final buf = StringBuffer()
    ..writeln('### $title')
    ..writeln()
    ..writeln(
      '| Leaves | Metric | Panel Catalog Viewport | $baselineLabel |',
    )
    ..writeln(
      '|--------|--------|------------------------|${'-' * (baselineLabel.length + 2)}|',
    );

  for (final (count, cand, base) in rows) {
    buf
      ..writeln(
        '| $count | Attached leaves / Visible cells | '
        '${cand.attachedLeaves} | ${base.visibleCells} |',
      )
      ..writeln(
        '| $count | RenderObjects (full tree) | '
        '${cand.renderObjectCount} | ${base.renderObjectCount} |',
      );
  }

  buf.writeln();
  return buf.toString();
}

String _fmtUs(double us) {
  if (us >= 1000) return '${(us / 1000).toStringAsFixed(2)}ms';
  return '${us.toStringAsFixed(1)}µs';
}

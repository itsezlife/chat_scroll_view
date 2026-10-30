/// The table `quick` prints. Pure Dart.
library;

import 'metrics.dart';
import 'report_document.dart';

/// Columns, in order: the headline metric and how it prints.
const _columns = <(String, String)>[
  ('build p99', 'build_p99_share'),
  ('raster p99', 'raster_p99_share'),
  ('over budget', 'over_budget_share'),
  ('frames', 'frames'),
];

String _cell(Metric? m) => switch (m) {
  null => '-',
  Metric(kind: MetricKind.share, :final value) =>
    '${(value * 100).toStringAsFixed(1)}%',
  Metric(:final value) =>
    value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2),
};

/// Renders [doc]'s headline metrics, one row per scenario window. Build and
/// raster p99 are shares of the vsync budget at the launch's refresh rate.
String renderTable(MetricsDocument doc) {
  final rows = <List<String>>[
    ['scenario', 'window', for (final c in _columns) c.$1],
  ];
  for (final s in doc.scenarios.entries) {
    for (final w in s.value.entries) {
      rows.add([s.key, w.key, for (final c in _columns) _cell(w.value[c.$2])]);
    }
  }
  final widths = [
    for (var i = 0; i < rows.first.length; i++)
      rows.map((r) => r[i].length).reduce((a, b) => a > b ? a : b),
  ];
  String line(List<String> r) => [
    for (var i = 0; i < r.length; i++) r[i].padRight(widths[i]),
  ].join('  ').trimRight();
  final m = doc.meta;
  return [
    '${m.device}, ${m.os}, ${m.backend}, ${m.refreshRateHz.toStringAsFixed(0)}'
        ' Hz, semantics ${m.semanticsMode}, corpus v${m.corpusVersion}',
    'p99 columns are shares of the vsync budget '
        '(${(1000 / m.refreshRateHz).toStringAsFixed(2)} ms).',
    '',
    line(rows.first),
    for (final r in rows.skip(1)) line(r),
  ].join('\n');
}

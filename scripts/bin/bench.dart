import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:workspace_check/workspace_check.dart';

/// Runs the headless benchmarks, sets their ratios against the stored
/// baselines and writes a report. Never a merge gate: the nightly workflow
/// calls it, and a regression there opens an issue.
///
///     scripts/bench [--runs 3] [--out build/bench] [--only <suite,...>]
///                   [--update-baselines] [--inject-regression <factor>]
///                   [--compare-only]
///
/// Exit code: 0 nothing regressed (a platform with no baseline yet is seeded,
/// not failed), 1 something regressed, 2 a benchmark did not run or the
/// arguments were wrong.
///
/// Documented, with the tolerance and the re-baselining steps, in
/// `benchmarks/README.md`.
Future<void> main(List<String> arguments) async {
  final root = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  final _Options options;
  try {
    options = _Options.parse(arguments, root);
  } on FormatException catch (error) {
    stderr.writeln('scripts/bench: ${error.message}');
    exitCode = 2;
    return;
  }

  final store = BenchBaselineStore(
    p.join(root, 'benchmarks', 'baselines'),
    platform: Platform.operatingSystem,
  );
  final sections = <String>[];
  final seeded = <String>[];
  var regressed = false;

  for (final suite in _suites.where(options.wants)) {
    stdout.writeln('==> ${suite.id}');
    final runs = options.compareOnly
        ? _readRuns(options.out, suite)
        : await _runSuite(suite, root, options);
    if (runs == null || runs.isEmpty) {
      stderr.writeln('scripts/bench: ${suite.id} produced no report.');
      exitCode = 2;
      return;
    }
    final measured = BenchReport.medianOf(runs);
    _write(p.join(options.out, 'results', '${suite.id}.json'), measured);

    // A drill compares the worsened numbers with the same run's own, not with
    // the stored baseline: it proves the alarm and issue path on any runner,
    // including one that has no baseline yet, and cannot be missed because the
    // runner happened to be faster than the machine the baseline came from.
    final factor = options.injectRegression;
    if (factor != null) {
      final drill = BenchComparison.compare(
        baseline: measured,
        current: measured.regressed(factor),
        tolerance: BenchTolerance.standard,
      );
      regressed |= drill.hasRegression;
      sections.add(
        '${drill.toMarkdown()}\n'
        'Drill: every metric made ${factor}x worse and compared with this '
        'run\'s own medians, not the stored baseline.\n',
      );
      continue;
    }

    if (options.updateBaselines) {
      store.save(measured);
      sections.add('### `${suite.id}`: baseline written\n');
      continue;
    }
    final baseline = store.load(suite.id);
    if (baseline == null) {
      seeded.add(suite.id);
      sections.add(
        '### `${suite.id}`: no baseline for `${store.platform}` yet\n\n'
        'Nothing to compare with. The measured ratios are in the results '
        'artifact (`results/${suite.id}.json`); committing it as '
        '`benchmarks/baselines/${suite.id}.${store.platform}.json` seeds the '
        'baseline.\n',
      );
      continue;
    }
    final comparison = BenchComparison.compare(
      baseline: baseline,
      current: measured,
      tolerance: BenchTolerance.standard,
    );
    regressed |= comparison.hasRegression;
    sections.add(comparison.toMarkdown());
  }

  final headline = options.updateBaselines
      ? 'Baselines updated for `${store.platform}`.'
      : regressed
      ? 'Benchmark regression on `${store.platform}`.'
      : seeded.isEmpty
      ? 'No benchmark regression on `${store.platform}`.'
      : 'No regression; no baseline yet for ${seeded.join(', ')}.';
  final report = StringBuffer()
    ..writeln('## $headline')
    ..writeln()
    ..writeln(
      'Headless debug timings: layout cost and object counts only, never a '
      'statement about fling smoothness (that is the device acceptance). '
      'Ratios are medians of ${options.runs} run(s); the tolerance is in '
      '`benchmarks/README.md`.',
    )
    ..writeln();
  sections.forEach(report.writeln);
  _writeText(p.join(options.out, 'report.md'), report.toString());
  stdout.write(report);
  if (regressed) exitCode = 1;
}

/// A benchmark suite: the test file that runs it and the environment that
/// picks its preset. Each writes its metrics where `BENCH_REPORT` points.
final class _Suite {
  const _Suite(this.id, this.package, this.testFile, [this.env = const {}]);

  final String id;
  final String package;
  final String testFile;
  final Map<String, String> env;
}

const _suites = [
  _Suite(
    'panel_catalog.semantics-off',
    'packages/panel_catalog',
    'test/benchmark/vs_supersliver_bench_test.dart',
    {'BENCH_SEMANTICS': 'off'},
  ),
  _Suite(
    'panel_catalog.semantics-on',
    'packages/panel_catalog',
    'test/benchmark/vs_supersliver_bench_test.dart',
    {'BENCH_SEMANTICS': 'on'},
  ),
  _Suite(
    'catalog_assets',
    'packages/catalog_assets',
    'test/benchmark/asset_cache_ratio_bench_test.dart',
  ),
];

final class _Options {
  const _Options({
    required this.runs,
    required this.out,
    required this.only,
    required this.updateBaselines,
    required this.compareOnly,
    required this.injectRegression,
  });

  factory _Options.parse(List<String> arguments, String root) {
    var runs = 3;
    var out = p.join(root, 'build', 'bench');
    var only = <String>{};
    var update = false;
    var compareOnly = false;
    double? inject;
    final queue = [...arguments];
    String value(String flag) {
      if (queue.isEmpty) throw FormatException('$flag needs a value');
      return queue.removeAt(0);
    }

    while (queue.isNotEmpty) {
      final flag = queue.removeAt(0);
      switch (flag) {
        case '--runs':
          runs = int.tryParse(value(flag)) ?? 0;
          if (runs < 1) throw const FormatException('--runs needs 1 or more');
        case '--out':
          out = p.absolute(value(flag));
        case '--only':
          only = value(flag).split(',').toSet();
          final unknown = only.difference({for (final s in _suites) s.id});
          if (unknown.isNotEmpty) {
            throw FormatException('unknown suite(s): ${unknown.join(', ')}');
          }
        case '--update-baselines':
          update = true;
        case '--compare-only':
          compareOnly = true;
        case '--inject-regression':
          inject = double.tryParse(value(flag));
          if (inject == null || inject <= 1) {
            throw const FormatException(
              '--inject-regression needs a factor above 1',
            );
          }
        default:
          throw FormatException('unknown argument $flag');
      }
    }
    if (update && inject != null) {
      throw const FormatException(
        '--update-baselines and --inject-regression exclude each other',
      );
    }
    return _Options(
      runs: runs,
      out: out,
      only: only,
      updateBaselines: update,
      compareOnly: compareOnly,
      injectRegression: inject,
    );
  }

  final int runs;
  final String out;
  final Set<String> only;
  final bool updateBaselines;
  final bool compareOnly;
  final double? injectRegression;

  bool wants(_Suite suite) => only.isEmpty || only.contains(suite.id);
}

/// Runs [suite] `options.runs` times, each a fresh `flutter test` process, and
/// returns what each reported; null if one did not run.
Future<List<BenchReport>?> _runSuite(
  _Suite suite,
  String root,
  _Options options,
) async {
  final reports = <BenchReport>[];
  for (var run = 1; run <= options.runs; run++) {
    final file = p.join(options.out, 'runs', '${suite.id}.$run.json');
    File(file).parent.createSync(recursive: true);
    if (File(file).existsSync()) File(file).deleteSync();
    stdout.writeln('    run $run of ${options.runs}');
    final process = await Process.start(
      'flutter',
      ['test', '--no-pub', suite.testFile],
      workingDirectory: p.join(root, suite.package),
      environment: {
        ...suite.env,
        'BENCH_REPORT': file,
        'BENCH_SUITE': suite.id,
      },
    );
    // The test prints its full tables; they are noise here and kept out of the
    // log unless the run fails.
    final log = StringBuffer();
    await Future.wait([
      process.stdout.transform(utf8.decoder).forEach(log.write),
      process.stderr.transform(utf8.decoder).forEach(log.write),
    ]);
    if (await process.exitCode != 0 || !File(file).existsSync()) {
      stderr.writeln(log);
      return null;
    }
    reports.add(_read(file));
  }
  return reports;
}

List<BenchReport>? _readRuns(String out, _Suite suite) {
  final dir = Directory(p.join(out, 'runs'));
  if (!dir.existsSync()) return null;
  return [
    for (final file
        in dir.listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
      if (p.basename(file.path).startsWith('${suite.id}.')) _read(file.path),
  ];
}

BenchReport _read(String path) => BenchReport.fromJson(
  jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>,
);

void _write(String path, BenchReport report) => _writeText(
  path,
  '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
);

void _writeText(String path, String text) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);
}

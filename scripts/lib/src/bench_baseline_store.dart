import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:workspace_check/src/bench_report.dart';

/// The stored benchmark baselines: one json file per suite and platform, in a
/// directory that is committed.
///
/// Per platform because a ratio is only comparable on the machine class that
/// produced it: the same code is slower or faster on a CI runner than on a
/// laptop by a different amount in every probe. A platform with no file has no
/// baseline yet, which the runner reports as a seed, not a regression.
final class BenchBaselineStore {
  /// Creates a store over [directory] for [platform] (`Platform.operatingSystem`
  /// in practice).
  const BenchBaselineStore(this.directory, {required this.platform});

  /// Where the baseline files live.
  final String directory;

  /// The platform whose baselines this store reads and writes.
  final String platform;

  /// The file of [suite]'s baseline on this platform.
  File fileFor(String suite) =>
      File(p.join(directory, '$suite.$platform.json'));

  /// The stored baseline of [suite], or null when there is none yet. A file
  /// that exists but cannot be read throws [FormatException]: a corrupt
  /// baseline must not be silently replaced by a new one.
  BenchReport? load(String suite) {
    final file = fileFor(suite);
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map<String, Object?>) {
      throw FormatException('${file.path} is not a benchmark report');
    }
    return BenchReport.fromJson(json);
  }

  /// Writes [report] as the baseline of its suite on this platform.
  void save(BenchReport report) {
    fileFor(report.suite)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
      );
  }
}

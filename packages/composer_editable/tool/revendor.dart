// Moves composer_editable onto a Flutter SDK: the one command behind every
// workspace SDK upgrade.
//
//   dart tool/revendor.dart [--sdk=<flutter root>] [--baseline-only]
//                           [--skip-suite]
//
// The package is a patch series over a renamed stock baseline. This tool
//
//   1. copies the vendored stock files from the SDK, renames them, applies the
//      package's analyzer fixes and formats them: the baseline for that SDK;
//   2. three-way merges each package file, old baseline -> new baseline;
//   3. raises every SDK pin, regenerates DIVERGENCES.md, runs the suite;
//   4. reports what conflicted and what failed.
//
// Run it on a branch: a conflicted merge leaves markers in lib/ for you to
// resolve. Exit status: 0 clean, 1 conflicts or a failing suite, 2 refused.
//
// The tool is run with `dart tool/revendor.dart`, not `dart run`, which would
// resolve the workspace first. Its imports are relative because tool/ is
// outside the package URI space.

import 'dart:convert';
import 'dart:io';

import 'src/divergences_doc.dart';
import 'src/sdk_pins.dart';
import 'src/stock_renamer.dart';
import 'src/three_way_merge.dart';
import 'src/vendored_files.dart';

Future<void> main(List<String> args) async {
  final packageRoot = File.fromUri(Platform.script).parent.parent;
  exit(await Revendor(packageRoot, args).run());
}

/// One re-vendor run.
class Revendor {
  Revendor(this.packageRoot, List<String> args)
    : _args = args,
      repoRoot = findRepoRoot(packageRoot);

  final Directory packageRoot;
  final Directory repoRoot;
  final List<String> _args;

  late final Directory _sdk = _resolveSdk();
  late final bool _baselineOnly = _args.contains('--baseline-only');
  late final bool _skipSuite = _args.contains('--skip-suite');
  final StringBuffer _report = StringBuffer();

  String get _dart => '${_sdk.path}/bin/dart';
  String get _flutter => '${_sdk.path}/bin/flutter';
  Directory get _baselines => Directory('${packageRoot.path}/tool/baseline');

  Future<int> run() async {
    final BaselineOrigin origin;
    final String oldVersion;
    try {
      origin = _sdkOrigin();
      oldVersion = _pinnedVersion();
      _preflight(oldVersion, origin.version);
    } on _Refused catch (refusal) {
      stderr.writeln('revendor: ${refusal.message}');
      return 2;
    }
    final newVersion = origin.version;
    _report.writeln(
      '## composer_editable re-vendor: $oldVersion -> $newVersion',
    );

    if (!_baselineOnly && oldVersion != newVersion) {
      writePins(repoRoot, newVersion);
      _report.writeln('- SDK pins raised to $newVersion.');
    }
    final pubGet = await _run(_flutter, ['pub', 'get'], repoRoot);
    if (pubGet != 0) {
      stderr.writeln('revendor: `flutter pub get` failed under the new pins.');
      return 2;
    }

    final staging = await _buildBaseline(origin);
    final conflicts = _baselineOnly ? 0 : _mergeAll(oldVersion, staging);
    _keepBaseline(staging, origin, oldVersion);
    _writeDivergences(origin);

    var suiteOk = true;
    if (!_baselineOnly && !_skipSuite) suiteOk = await _runSuite();

    if (_baselineOnly) {
      _report.writeln(
        '- Baseline for ${origin.version} rebuilt; lib/ untouched.',
      );
    } else {
      _report.writeln(
        conflicts == 0
            ? '- Merge: no conflicts.'
            : '- Merge: **$conflicts conflict(s)**, markers left in lib/.',
      );
    }
    stdout.write(_report);
    final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
    if (summary != null) {
      File(summary).writeAsStringSync('$_report', mode: FileMode.append);
    }
    return conflicts == 0 && suiteOk ? 0 : 1;
  }

  // --- The SDK ---------------------------------------------------------------

  Directory _resolveSdk() {
    for (final arg in _args) {
      if (arg.startsWith('--sdk=')) return Directory(arg.substring(6));
    }
    final env = Platform.environment['FLUTTER_ROOT'];
    if (env != null) return Directory(env);
    final which = Process.runSync('which', ['flutter']);
    if (which.exitCode != 0) {
      throw const _Refused('No --sdk, no FLUTTER_ROOT and no flutter on PATH.');
    }
    // fvm's `default` is a symlink; resolve it to the SDK itself.
    final bin = File(
      (which.stdout as String).trim(),
    ).resolveSymbolicLinksSync();
    return File(bin).parent.parent;
  }

  BaselineOrigin _sdkOrigin() {
    final file = File('${_sdk.path}/bin/cache/flutter.version.json');
    if (!file.existsSync()) {
      throw _Refused('${_sdk.path} is not a Flutter SDK (no ${file.path}).');
    }
    return BaselineOrigin.fromSdkJson(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
  }

  String _pinnedVersion() {
    final pinned = readPin(repoRoot, sdkPins.first);
    if (pinned == null) {
      throw const _Refused('pubspec.yaml has no exact `flutter:` pin.');
    }
    return pinned;
  }

  // --- Refusals --------------------------------------------------------------

  /// The tool writes only to paths that exist; it never creates a vendored
  /// directory, so a path drift (research 04's `widgets/` vs `widget/`) stops
  /// the run instead of growing a second tree.
  void _preflight(String oldVersion, String newVersion) {
    final missing = <String>[];
    for (final file in vendoredFiles) {
      if (!File('${packageRoot.path}/${file.fork}').existsSync()) {
        missing.add(file.fork);
      }
      if (!_baselineOnly &&
          !File(
            '${_baselines.path}/$oldVersion/${file.baseline}',
          ).existsSync()) {
        missing.add('tool/baseline/$oldVersion/${file.baseline}');
      }
      final stock = File('${_sdk.path}/packages/flutter/lib/src/${file.stock}');
      if (!stock.existsSync()) missing.add(stock.path);
    }
    if (missing.isNotEmpty) {
      throw _Refused('missing paths:\n  ${missing.join('\n  ')}');
    }
  }

  // --- The baseline ----------------------------------------------------------

  /// Renames the SDK's stock files into a staging directory inside the package
  /// (so the analyzer sees the package's options and resolution), fixes and
  /// formats them there, and returns it.
  Future<Directory> _buildBaseline(BaselineOrigin origin) async {
    final staging = Directory('${packageRoot.path}/tool/staging');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    for (final file in vendoredFiles) {
      final stock = File('${_sdk.path}/packages/flutter/lib/src/${file.stock}');
      File('${staging.path}/${file.baseline}')
        ..createSync(recursive: true)
        ..writeAsStringSync(renameStockSource(stock.readAsStringSync(), file));
    }
    // `dart fix` exits 0 whether or not it changed anything.
    await _run(_dart, ['fix', '--apply', staging.path], packageRoot);
    await _run(_dart, ['format', staging.path], packageRoot);
    return staging;
  }

  /// Stores the baseline of the new SDK and drops the old one (git keeps it).
  void _keepBaseline(
    Directory staging,
    BaselineOrigin origin,
    String oldVersion,
  ) {
    final target = Directory('${_baselines.path}/${origin.version}');
    if (target.existsSync()) target.deleteSync(recursive: true);
    for (final file in vendoredFiles) {
      File('${target.path}/${file.baseline}')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          File('${staging.path}/${file.baseline}').readAsStringSync(),
        );
    }
    File('${target.path}/SDK.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(origin.toJson())}\n',
    );
    staging.deleteSync(recursive: true);
    if (!_baselineOnly && oldVersion != origin.version) {
      final old = Directory('${_baselines.path}/$oldVersion');
      if (old.existsSync()) old.deleteSync(recursive: true);
    }
  }

  // --- The merge -------------------------------------------------------------

  /// Merges every vendored file; returns the number of conflicts.
  int _mergeAll(String oldVersion, Directory staging) {
    var total = 0;
    for (final file in vendoredFiles) {
      final oldBase = File(
        '${_baselines.path}/$oldVersion/${file.baseline}',
      ).readAsStringSync();
      final newBase = File(
        '${staging.path}/${file.baseline}',
      ).readAsStringSync();
      if (oldBase == newBase) {
        _report.writeln('- `${file.fork}`: baseline unchanged.');
        continue;
      }
      final target = File('${packageRoot.path}/${file.fork}');
      final merged = threeWayMerge(
        fork: target.readAsStringSync(),
        oldBase: oldBase,
        newBase: newBase,
        label: file.fork,
      );
      target.writeAsStringSync(merged.text);
      total += merged.conflicts;
      _report.writeln(
        merged.conflicts == 0
            ? '- `${file.fork}`: merged cleanly.'
            : '- `${file.fork}`: **${merged.conflicts} conflict(s)**.',
      );
    }
    return total;
  }

  // --- The report ------------------------------------------------------------

  void _writeDivergences(BaselineOrigin origin) {
    final baseline = Directory('${_baselines.path}/${origin.version}');
    File('${packageRoot.path}/DIVERGENCES.md').writeAsStringSync(
      renderDivergences(
        template: File(
          '${packageRoot.path}/tool/divergences.template.md',
        ).readAsStringSync(),
        origin: origin,
        baselineDir: baseline,
        packageRoot: packageRoot,
      ),
    );
  }

  Future<bool> _runSuite() async {
    final result = await Process.run(_flutter, [
      'test',
      'test/unit_test.dart',
    ], workingDirectory: packageRoot.path);
    final output = '${result.stdout}${result.stderr}';
    final errors = output
        .split('\n')
        .where((line) => line.contains('Error:') || line.contains('error:'))
        .take(20)
        .toList();
    final tail = output.trimRight().split('\n').last;
    _report
      ..writeln(
        result.exitCode == 0
            ? '- Suite: passed.'
            : '- Suite: **failed** (exit ${result.exitCode}).',
      )
      ..writeln('  - ${tail.trim()}');
    for (final line in errors) {
      _report.writeln('  - `${line.trim()}`');
    }
    return result.exitCode == 0;
  }

  Future<int> _run(String exe, List<String> args, Directory cwd) async {
    final process = await Process.start(
      exe,
      args,
      workingDirectory: cwd.path,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }
}

class _Refused implements Exception {
  const _Refused(this.message);
  final String message;
}

/// Runner of the chat performance suite.
///
///   dart run tool/chat_perf.dart quick|run|baseline --device ID
///       [--scenario GLOB,...] [--label NAME] [--backend impeller|skia]
///       [--history N] [--semantics off|on|pair] [--refresh HZ]
///       [--launches N]   (baseline only, at least 5)
///   dart run tool/chat_perf.dart promote LABEL --reason "one line"
///   dart run tool/chat_perf.dart compare LABEL [--refresh HZ]
///
/// `quick` makes one launch of the timing pass, prints the headline table and
/// an informational diff against the baseline, and writes
/// `perf/runs/<label>/chat_perf_metrics.json` plus the per-frame sidecar
/// `chat_perf_frames.json`. No verdict, nothing promoted.
///
/// `run` makes 3 fresh timing launches (the shared-process group plus one
/// launch per cold scenario, in each), takes the median per metric and judges
/// it against the committed baseline. `baseline` makes at least 5 and writes a
/// candidate under `perf/runs/<label>/`; `promote` makes it current with a
/// recorded reason; `compare` re-judges a stored run. Only baseline regressions
/// set a failing exit status. `run` and `baseline` take the same
/// `--semantics`.
///
/// Before the first launch it refuses a device that cannot give meaningful
/// numbers and takes the per-device lock. Each launch uses the APK cached under
/// a fingerprint of the sources and the dart-define set; a launch killed by a
/// foreign package install is discarded and retried once. The label is
/// host-side only (`PERF_LABEL`); it is never a dart-define.
library;

import 'dart:convert';
import 'dart:io';

import '../integration_test/chat_perf/registry.dart';
import '../integration_test/chat_perf/report_document.dart';
import '../integration_test/chat_perf/scenarios/churn_scenarios.dart';
import '../integration_test/chat_perf/scenarios/ime_scenarios.dart';
import '../integration_test/chat_perf/scenarios/keyboard_scenarios.dart';
import '../integration_test/chat_perf/scenarios/scroll_scenarios.dart';
import '../integration_test/chat_perf/semantics.dart';
import '../integration_test/chat_perf/table.dart';
import 'chat_perf/adb.dart';
import 'chat_perf/baseline.dart';
import 'chat_perf/build_fingerprint.dart';
import 'chat_perf/cooldown.dart';
import 'chat_perf/device_lock.dart';
import 'chat_perf/gates.dart';
import 'chat_perf/launch_retry.dart';
import 'chat_perf/verdict.dart';

const _modes = {'quick', 'run', 'baseline', 'promote', 'compare'};
const _baselineRoot = 'perf/baseline/chat';

String get _out =>
    Platform.environment['PERF_OUT'] ?? '${Directory.current.path}/perf';

typedef _Launch = ({String label, String filter, bool cold});

final _all = ScenarioRegistry([
  ...scrollScenarios.all,
  ...churnScenarios.all,
  ...keyboardScenarios.all,
  ...imeScenarios.all,
]);

Future<void> main(List<String> args) async {
  if (args.isEmpty || !_modes.contains(args.first)) {
    stderr.writeln(
      'usage: dart run tool/chat_perf.dart quick|run|baseline --device ID '
      '[--scenario GLOB,...] [--label NAME] [--backend impeller|skia] '
      '[--history N] [--semantics off|on|pair] [--refresh HZ] '
      '[--launches N]\n'
      '       dart run tool/chat_perf.dart promote LABEL --reason "..."\n'
      '       dart run tool/chat_perf.dart compare LABEL [--refresh HZ]',
    );
    exit(64);
  }
  final mode = args.first;
  final rest = args.skip(1).toList();
  if (mode == 'promote' || mode == 'compare') {
    if (rest.isEmpty || rest.first.startsWith('--')) {
      stderr.writeln('$mode needs a run label');
      exit(64);
    }
    final options = _options(rest.skip(1).toList());
    exit(
      mode == 'promote'
          ? _promote(rest.first, options['reason'] ?? '')
          : _compare(rest.first, options),
    );
  }
  final options = _options(rest);
  final device = options['device'];
  if (device == null) {
    stderr.writeln('--device ID is required (see: adb devices)');
    exit(64);
  }
  final SemanticsRun semantics;
  try {
    semantics = SemanticsRun.parse(options['semantics'] ?? '');
  } on FormatException catch (e) {
    stderr.writeln('--semantics: ${e.message}');
    exit(64);
  }
  final rounds = switch (mode) {
    'run' => 3,
    'baseline' => int.tryParse(options['launches'] ?? '') ?? 5,
    _ => 1,
  };
  if (mode == 'baseline' && rounds < kMinBaselineLaunches) {
    stderr.writeln('--launches must be at least $kMinBaselineLaunches');
    exit(64);
  }
  final label =
      options['label'] ??
      '$mode-${DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-')}';
  final filter = options['scenario'] ?? '';

  // The shared-process set is one launch; each cold scenario gets its own
  // (spec 5), under `<round label>-<scenario id>`. A round is one of each.
  List<_Launch> launchesOf(String round) => [
    if (_all.where(filter).isNotEmpty)
      (label: round, filter: filter, cold: false),
    for (final s in _all.where(filter, cold: true))
      (label: '$round-${s.id}', filter: s.id, cold: true),
  ];
  if (launchesOf(label).isEmpty) {
    stderr.writeln('no scenario matches "$filter"');
    exit(64);
  }
  final adb = Adb(device);
  final failures = evaluateGates(await adb.state());
  if (failures.isNotEmpty) {
    stderr.writeln('refusing to start on $device:');
    for (final f in failures) {
      stderr.writeln('  - $f');
    }
    exit(2);
  }
  final DeviceLock lock;
  try {
    lock = DeviceLock.acquire(
      const DirectoryLockStore(),
      device,
      owner: 'pid $pid, label $label',
    );
  } on DeviceLockedException catch (e) {
    stderr.writeln(e.message);
    exit(3);
  }

  var status = 0;
  final batteryStart = await adb.battery();
  final roundDocs = <MetricsDocument>[];
  final roundLabels = <List<String>>[];
  var discarded = 0;
  try {
    var first = true;
    for (var r = 1; r <= rounds && status == 0; r++) {
      final roundLabel = rounds == 1 ? label : '$label-r$r';
      final docs = <MetricsDocument>[];
      final labels = <String>[];
      for (final launch in launchesOf(roundLabel)) {
        if (!first) {
          // Between launches: let the battery cool back toward the start.
          cooldown = await waitForCooldown(
            startTempC: batteryStart.temperatureC,
            readTempC: () async => (await adb.battery()).temperatureC,
            sleep: Future<void>.delayed,
          );
        }
        first = false;
        final result = await _launch(adb, options, semantics, launch);
        discarded += result.discarded;
        labels.add(launch.label);
        if (result.doc case final doc?) docs.add(doc);
        if (result.code != 0 || result.doc == null) {
          status = result.code == 0 ? 1 : result.code;
          break;
        }
      }
      if (status == 0) {
        roundDocs.add(unionDocuments(docs));
        roundLabels.add(labels);
      }
    }
  } on ForeignInstallException catch (e) {
    stderr.writeln('run failed: ${e.message}');
    status = 4;
  } finally {
    lock.release();
  }
  if (status != 0) {
    stderr.writeln('no verdict: a launch failed (exit $status)');
    exit(status);
  }
  exit(
    _finish(
      mode: mode,
      label: label,
      rounds: roundDocs,
      roundLabels: roundLabels,
      discarded: discarded,
      requested: Requested(
        backend: options['backend'] ?? 'impeller',
        semantics: semantics.name,
        refreshHz: int.tryParse(options['refresh'] ?? ''),
      ),
    ),
  );
}

/// Verdict, candidate or informational diff for the finished launches.
int _finish({
  required String mode,
  required String label,
  required List<MetricsDocument> rounds,
  required List<List<String>> roundLabels,
  required int discarded,
  required Requested requested,
}) {
  final dir = Directory('$_out/runs/$label')..createSync(recursive: true);
  File('${dir.path}/chat_perf_run.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'mode': mode,
      'rounds': roundLabels,
      'discardedLaunches': discarded,
      'requested': {
        'backend': requested.backend,
        'semantics': requested.semantics,
        'refreshHz': requested.refreshHz,
      },
    }),
  );
  final disagreement = launchDisagreement(rounds);
  if (disagreement.isNotEmpty) {
    stdout.writeln('refusing to compare: ${disagreement.join('; ')}');
    return 0;
  }
  if (mode != 'baseline') {
    return _judgeAndPrint(
      medianOf(rounds),
      requested,
      informational: mode == 'quick',
    );
  }
  final problems = combinationProblems(rounds.first.meta, requested);
  if (problems.isNotEmpty) {
    stdout.writeln('refusing to write a candidate: ${problems.join('; ')}');
    return 0;
  }
  final candidate = Baseline.fromLaunches(
    rounds,
    label: label,
    discarded: discarded,
  );
  final file = File('${dir.path}/baseline_candidate.json')
    ..writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(candidate.toJson()),
    );
  stdout
    ..writeln()
    ..writeln('candidate for ${candidate.key}: ${file.path}')
    ..writeln(
      'promote with: dart run tool/chat_perf.dart promote $label '
      '--reason "..."',
    );
  return 0;
}

Baseline? _currentBaseline(String key) {
  final file = File('$_baselineRoot/$key/metrics.json');
  return file.existsSync()
      ? Baseline.fromJson(
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
        )
      : null;
}

int _judgeAndPrint(
  MetricsDocument run,
  Requested requested, {
  bool informational = false,
}) {
  final key = baselineKey(run.meta);
  final baseline = _currentBaseline(key);
  final verdict = judge(run, baseline, requested: requested);
  stdout
    ..writeln()
    ..writeln(
      '${informational ? 'informational diff' : 'verdict'} against $key '
      '(${baseline == null ? 'no baseline' : '${baseline.launches} launches'}):',
    )
    ..writeln(renderVerdict(verdict));
  return informational ? 0 : verdict.exitCode;
}

/// Re-judges a stored run from its launches' documents.
int _compare(String label, Map<String, String> options) {
  final manifestFile = File('$_out/runs/$label/chat_perf_run.json');
  if (!manifestFile.existsSync()) {
    stderr.writeln('no stored run "$label" under $_out/runs');
    return 66;
  }
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
  final rounds = [
    for (final round in manifest['rounds']! as List<Object?>)
      unionDocuments([
        for (final l in round! as List<Object?>)
          MetricsDocument.fromJson(
            jsonDecode(
                  File(
                    '$_out/runs/$l/chat_perf_metrics.json',
                  ).readAsStringSync(),
                )
                as Map<String, Object?>,
          ),
      ]),
  ];
  final req = manifest['requested']! as Map<String, Object?>;
  return _judgeAndPrint(
    medianOf(rounds),
    Requested(
      backend: req['backend']! as String,
      semantics: req['semantics']! as String,
      refreshHz:
          int.tryParse(options['refresh'] ?? '') ?? req['refreshHz'] as int?,
    ),
  );
}

int _promote(String label, String reason) {
  final file = File('$_out/runs/$label/baseline_candidate.json');
  if (!file.existsSync()) {
    stderr.writeln('no candidate for "$label": run `baseline` first');
    return 66;
  }
  final candidate = Baseline.fromJson(
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
  );
  stdout.writeln(headlineDiff(_currentBaseline(candidate.key), candidate));
  final problems = promoteProblems(candidate, reason);
  if (problems.isNotEmpty) {
    stderr.writeln('refusing to promote:');
    for (final p in problems) {
      stderr.writeln('  - $p');
    }
    return 1;
  }
  final target = File('$_baselineRoot/${candidate.key}/metrics.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(candidate.withReason(reason.trim()).toJson()),
    );
  stdout.writeln('promoted: ${target.path} (commit it for review)');
  return 0;
}

/// The last between-launch wait; null before one ran.
CooldownResult? cooldown;

Future<({int code, int discarded, MetricsDocument? doc})> _launch(
  Adb adb,
  Map<String, String> options,
  SemanticsRun semantics,
  _Launch launch,
) async {
  final label = launch.label;
  final backend = options['backend'] ?? 'impeller';
  final defines = buildDefines(
    backend: backend,
    scenario: launch.filter,
    history: options['history'],
    cold: launch.cold,
    semantics: semantics.name,
  );
  final apk = await _ensureApk(defines, backend);
  final out = _out;

  final batteryStart = await adb.battery();
  final result = await runWithRetry<int>(
    launch: () async {
      await adb.clearLogcat();
      return _drive(
        adb.device,
        label,
        out,
        defines,
        apk,
        backend,
        noDds: semantics == SemanticsRun.pair,
      );
    },
    foreignInstall: () async => hasForeignInstall(await adb.logcat(), kPackage),
  );
  final code = result.value;

  final file = File('$out/runs/$label/chat_perf_metrics.json');
  if (!file.existsSync()) {
    stderr.writeln('launch exited $code and wrote no metrics document');
    return (code: code, discarded: result.discarded, doc: null);
  }

  // The app cannot read what only the host sees; fill it in.
  final batteryEnd = await adb.battery();
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final meta = json['meta']! as Map<String, Object?>
    ..['device'] = (await adb.shell('getprop ro.product.model')).trim()
    ..['flutterVersion'] = await _flutterVersion()
    ..['environment'] = {
      'batteryStart': batteryStart.toJson(),
      'batteryEnd': batteryEnd.toJson(),
      'inputMethod': await adb.inputMethod(),
      'discardedLaunches': result.discarded,
      'cooldownBoundHit': ?cooldown?.boundHit,
    };
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));

  final doc = MetricsDocument.fromJson(json);
  stdout
    ..writeln()
    ..writeln(renderTable(doc))
    ..writeln()
    ..writeln('metrics: ${file.path}')
    ..writeln('frames:  $out/runs/$label/chat_perf_frames.json');
  for (final skip
      in ((json['skipped'] as Map<String, Object?>?) ?? {}).entries) {
    stdout.writeln('skipped ${skip.key}: ${skip.value}');
  }
  if (meta['semanticsMode'] == 'on' && semantics != SemanticsRun.on) {
    stdout.writeln('note: semantics were on during this launch.');
  }
  return (code: code, discarded: result.discarded, doc: doc);
}

const _target = 'integration_test/chat_perf/chat_perf_test.dart';
const _driver = 'test_driver/integration_test.dart';

/// The APK for these sources and defines, built when no cached one matches.
Future<String> _ensureApk(List<String> defines, String backend) async {
  // Resolve first: a pub get rewrites the lockfile, which is a fingerprint
  // input, so it must settle before the key is taken.
  final pubGet = await Process.run('flutter', ['pub', 'get']);
  if (pubGet.exitCode != 0) {
    stderr.writeln('flutter pub get failed:\n${pubGet.stderr}');
    exit(1);
  }
  final apk = 'build/chat_perf/${buildFingerprint(buildInputs(), defines)}.apk';
  if (File(apk).existsSync()) return apk;
  final build = await Process.start('flutter', [
    'build',
    'apk',
    '--profile',
    '--target-platform',
    'android-arm64',
    '--target=$_target',
    for (final d in defines) '--dart-define=$d',
    if (backend == 'skia') '--no-enable-impeller',
  ], mode: ProcessStartMode.inheritStdio);
  if (await build.exitCode != 0) {
    stderr.writeln('build failed');
    exit(1);
  }
  Directory(File(apk).parent.path).createSync(recursive: true);
  File('build/app/outputs/flutter-apk/app-profile.apk').copySync(apk);
  return apk;
}

Future<int> _drive(
  String device,
  String label,
  String out,
  List<String> defines,
  String apk,
  String backend, {
  bool noDds = false,
}) async {
  Directory('$out/runs/$label').createSync(recursive: true);
  final process = await Process.start(
    'flutter',
    [
      'drive',
      '--profile',
      '-d',
      device,
      '--driver=$_driver',
      '--target=$_target',
      for (final d in defines) '--dart-define=$d',
      if (backend == 'skia') '--no-enable-impeller',
      // The timeline tracer (pair mode) connects to the VM service itself.
      if (noDds) '--no-dds',
      '--use-application-binary=$apk',
    ],
    environment: {'PERF_LABEL': label, 'PERF_OUT': out},
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  stdout.writeln('reports: $out/runs/$label/');
  return code;
}

Map<String, String> _options(List<String> args) {
  final result = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    if (!args[i].startsWith('--')) {
      stderr.writeln('unexpected argument ${args[i]}');
      exit(64);
    }
    result[args[i].substring(2)] = args[i + 1];
  }
  return result;
}

Future<String> _flutterVersion() async {
  final r = await Process.run('flutter', ['--version', '--machine']);
  if (r.exitCode != 0) return 'unknown';
  final v = jsonDecode(r.stdout as String) as Map<String, Object?>;
  return '${v['frameworkVersion']} (${v['channel']})';
}

/// Runner of the chat performance suite.
///
///   dart run tool/chat_perf.dart quick|run|baseline --device ID
///       [--scenario GLOB,...] [--label NAME] [--backend impeller|skia]
///       [--history N] [--semantics off|on|pair] [--refresh HZ]
///       [--launches N]   (baseline only, at least 5)
///       [--perf-mode fixed|system]   (fixed pins the clocks; the default,
///                                     restored after every run)
///       [--trace off]    (run and baseline: skip the traced pass)
///       [--traced-launches N]   (run and baseline: 3 by default)
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
/// `run` and `baseline` end with traced launches (a `trace=phase` build,
/// `--no-dds`, 3 by default) over the `deterministic` scenarios; their
/// timelines give the structural counts (`trace.*`). Traced launch `i` joins
/// timing round `i`, so a baseline stores the counts' spread and a run judges
/// their median. Timing never comes from a traced launch.
///
/// Before the first launch it refuses a device that cannot give meaningful
/// numbers and takes the per-device lock. Each launch uses the APK cached under
/// a fingerprint of the sources and the dart-define set; a launch killed by a
/// foreign package install is discarded and retried once. The label is
/// host-side only (`PERF_LABEL`); it is never a dart-define.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../integration_test/chat_perf/metrics.dart';
import '../integration_test/chat_perf/report_document.dart';
import '../integration_test/chat_perf/scenario_index.dart';
import '../integration_test/chat_perf/semantics.dart';
import '../integration_test/chat_perf/table.dart';
import '../integration_test/chat_perf/trace_counts.dart';
import 'chat_perf/adb.dart';
import 'chat_perf/baseline.dart';
import 'chat_perf/build_fingerprint.dart';
import 'chat_perf/cooldown.dart';
import 'chat_perf/dependency_stamp.dart';
import 'chat_perf/device_lock.dart';
import 'chat_perf/gates.dart';
import 'chat_perf/launch_retry.dart';
import 'chat_perf/perf_mode.dart';
import 'chat_perf/verdict.dart';

const _modes = {'quick', 'run', 'baseline', 'promote', 'compare', 'counts'};
const _baselineRoot = 'perf/baseline/chat';

/// Traced launches a `run` or `baseline` ends with (`--traced-launches`), so
/// the `trace.*` counts get a spread (finding 17).
const kDefaultTracedLaunches = 3;

/// The counts of one traced launch, in that launch's run directory.
const _tracedMetricsFile = 'chat_perf_trace_metrics.json';

String get _out =>
    Platform.environment['PERF_OUT'] ?? '${Directory.current.path}/perf';

/// The markdown engine the build resolved: version, source, path or url and
/// commit, from the workspace lock (and the checkout's HEAD for a path).
Map<String, Object?> _markdownStamp() {
  final lock = File('../pubspec.lock');
  if (!lock.existsSync()) return {'unknown': true};
  final stamp = parseLockEntry(lock.readAsStringSync(), 'flutter_md');
  if (stamp == null) return {'unknown': true};
  var revision = stamp.revision;
  if (stamp.source == 'path' && stamp.location != null) {
    final git = Directory(
      '${Directory('..').absolute.path}/${stamp.location}',
    ).absolute.uri.resolve('.git/');
    String? read(String name) {
      final f = File.fromUri(git.resolve(name));
      return f.existsSync() ? f.readAsStringSync() : null;
    }

    final head = read('HEAD');
    if (head != null) revision = parseHeadRevision(head, read);
  }
  return stamp.withRevision(revision).toJson();
}

/// The markdown theme's `disposeBuiltPainters` both hosts run with: the demo
/// theme's shipping value, which the bench host matches. Recorded with the
/// engine stamp, so a baseline made with the other value refuses to compare.
const _disposeBuiltPainters = true;

/// The flags of a device run as given, and the ones parsed from them.
typedef _RunOptions = ({Map<String, String> flags, PerfMode perfMode});

typedef _Launch = ({String label, String filter, bool cold});

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
  final tracedLaunches =
      int.tryParse(options['traced-launches'] ?? '') ?? kDefaultTracedLaunches;
  if (tracedLaunches < 1) {
    stderr.writeln('--traced-launches must be at least 1');
    exit(64);
  }
  final label =
      options['label'] ??
      '$mode-${DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-')}';
  final filter = options['scenario'] ?? '';

  // The shared-process set is one launch; each cold scenario gets its own
  // (spec 5), under `<round label>-<scenario id>`. A round is one of each.
  List<_Launch> launchesOf(String round) => [
    if (selectScenarios(scenarioIndex, filter).isNotEmpty)
      (label: round, filter: filter, cold: false),
    for (final s in selectScenarios(scenarioIndex, filter, cold: true))
      (label: '$round-${s.id}', filter: s.id, cold: true),
  ];
  if (launchesOf(label).isEmpty) {
    stderr.writeln('no scenario matches "$filter"');
    exit(64);
  }
  final _RunOptions run;
  try {
    run = (
      flags: options,
      perfMode: PerfMode.parse(options['perf-mode'] ?? ''),
    );
  } on FormatException catch (e) {
    stderr.writeln('--perf-mode: ${e.message}');
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

  if (run.perfMode == PerfMode.fixed) {
    await adb.setFixedPerformance(enabled: true);
  }

  if (mode == 'counts') {
    exit(await _counts(adb, lock, run, filter, label));
  }

  var status = 0;
  final batteryStart = await adb.battery();
  final roundDocs = <MetricsDocument>[];
  final roundLabels = <List<String>>[];
  var discarded = 0;
  final traced = <({String label, MetricsDocument doc})>[];
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
        final result = await _launch(adb, run, semantics, launch);
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
    final matching = scenarioGlobs(filter);
    final traceable = [
      for (final id in tracedScenarioIds)
        if (matching(id)) id,
    ];
    if (status == 0 &&
        (mode == 'run' || mode == 'baseline') &&
        options['trace'] != 'off' &&
        traceable.isNotEmpty &&
        roundDocs.isNotEmpty) {
      // A count's spread needs several traced launches (finding 17); never
      // more than the timing rounds they join.
      final count = math.min(tracedLaunches, roundDocs.length);
      for (var t = 1; t <= count && status == 0; t++) {
        final tracedLabel = count == 1 ? '$label-traced' : '$label-traced$t';
        final result = await _tracedLaunch(adb, run, tracedLabel, traceable);
        discarded += result.discarded;
        if (result.doc case final doc? when result.code == 0) {
          traced.add((label: tracedLabel, doc: doc));
        } else {
          status = result.code == 0 ? 1 : result.code;
        }
      }
    }
  } on ForeignInstallException catch (e) {
    stderr.writeln('run failed: ${e.message}');
    status = 4;
  } on _BuildFailure catch (e) {
    stderr.writeln(e.message);
    status = 1;
  } finally {
    // The phone's default mode comes back after every run, failed or not.
    if (run.perfMode == PerfMode.fixed) {
      await adb.setFixedPerformance(enabled: false);
    }
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
      launches: roundDocs,
      roundLabels: roundLabels,
      traced: traced,
      discarded: discarded,
      requested: Requested(
        backend: options['backend'] ?? 'impeller',
        semantics: semantics.name,
        refreshHz: int.tryParse(options['refresh'] ?? ''),
      ),
    ),
  );
}

/// `counts`: only the traced launch, repeated `--launches` times (3 by
/// default), written as a candidate that is the current baseline plus the
/// `trace.*` counts. `promote` makes it current. Seeds the counts of a
/// baseline made before the traced pass existed.
Future<int> _counts(
  Adb adb,
  DeviceLock lock,
  _RunOptions run,
  String filter,
  String label,
) async {
  final matching = scenarioGlobs(filter);
  final ids = [
    for (final id in tracedScenarioIds)
      if (matching(id)) id,
  ];
  final launches = int.tryParse(run.flags['launches'] ?? '') ?? 3;
  final docs = <MetricsDocument>[];
  var code = 0;
  try {
    for (var i = 1; i <= launches && code == 0; i++) {
      final result = await _tracedLaunch(adb, run, '$label-t$i', ids);
      code = result.code;
      if (result.doc case final doc?) docs.add(doc);
    }
  } on ForeignInstallException catch (e) {
    stderr.writeln('run failed: ${e.message}');
    code = 4;
  } on _BuildFailure catch (e) {
    stderr.writeln(e.message);
    code = 1;
  } finally {
    if (run.perfMode == PerfMode.fixed) {
      await adb.setFixedPerformance(enabled: false);
    }
    lock.release();
  }
  if (code != 0 || docs.isEmpty) {
    stderr.writeln('no counts: a traced launch failed (exit $code)');
    return code == 0 ? 1 : code;
  }
  final counts = Baseline.fromLaunches(docs, label: label);
  final current = _currentBaseline(counts.key);
  if (current == null) {
    stderr.writeln('no baseline for ${counts.key} to add the counts to');
    return 66;
  }
  final dir = Directory('$_out/runs/$label')..createSync(recursive: true);
  final file = File('${dir.path}/baseline_candidate.json')
    ..writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(current.withMetricsOf(counts).toJson()),
    );
  stdout.writeln(
    'candidate for ${counts.key} (counts from ${docs.length} launches): '
    '${file.path}\npromote with: dart run tool/chat_perf.dart promote '
    '$label --reason "..."',
  );
  return 0;
}

/// Verdict, candidate or informational diff for the finished launches.
int _finish({
  required String mode,
  required String label,
  required List<MetricsDocument> launches,
  required List<List<String>> roundLabels,
  required int discarded,
  required Requested requested,
  List<({String label, MetricsDocument doc})> traced = const [],
}) {
  final dir = Directory('$_out/runs/$label')..createSync(recursive: true);
  for (final t in traced) {
    File('$_out/runs/${t.label}/$_tracedMetricsFile').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(t.doc.toJson()),
    );
  }
  final rounds = withTracedRounds(launches, [for (final t in traced) t.doc]);
  File('${dir.path}/chat_perf_run.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'mode': mode,
      'rounds': roundLabels,
      'traced': [for (final t in traced) t.label],
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
      '(${switch (baseline) {
        final b? => '${b.launches} launches',
        null => 'no baseline',
      }}):',
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
  // The traced launches' labels; a run stored before several were made names
  // one, whose counts sit beside the manifest.
  final tracedFiles = switch (manifest['traced']) {
    final List<Object?> labels => [
      for (final l in labels) File('$_out/runs/$l/$_tracedMetricsFile'),
    ],
    final String _ => [File('$_out/runs/$label/$_tracedMetricsFile')],
    _ => <File>[],
  };
  final tracedDocs = [
    for (final f in tracedFiles)
      if (f.existsSync())
        MetricsDocument.fromJson(
          jsonDecode(f.readAsStringSync()) as Map<String, Object?>,
        ),
  ];
  final judged = withTracedRounds(rounds, tracedDocs);
  final req = manifest['requested']! as Map<String, Object?>;
  return _judgeAndPrint(
    medianOf(judged),
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
  _RunOptions run,
  SemanticsRun semantics,
  _Launch launch,
) async {
  final label = launch.label;
  final backend = run.flags['backend'] ?? 'impeller';
  final defines = buildDefines(
    backend: backend,
    scenario: launch.filter,
    history: run.flags['history'],
    cold: launch.cold,
    semantics: semantics.name,
  );
  final apk = await _ensureApk(defines, backend);
  final out = _out;

  final batteryStart = await adb.battery();
  final clocksStart = await adb.clocks();
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
      'clocksStart': clocksStart,
      'clocksEnd': await adb.clocks(),
      'inputMethod': await adb.inputMethod(),
      ..._combination(run),
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

/// The traced pass: one launch of the `trace=phase` build over the scripted
/// [scenarios], driven with the VM-service connection the timeline capture
/// needs (`--no-dds`). Only the counts derived from its timelines are kept;
/// the launch's own timing document is ignored.
Future<({int code, int discarded, MetricsDocument? doc})> _tracedLaunch(
  Adb adb,
  _RunOptions run,
  String label,
  List<String> ids,
) async {
  final backend = run.flags['backend'] ?? 'impeller';
  final defines = buildDefines(
    backend: backend,
    scenario: ids.join(','),
    history: run.flags['history'],
    semantics: 'off',
    traced: true,
  );
  final apk = await _ensureApk(defines, backend);
  final result = await runWithRetry<int>(
    launch: () async {
      await adb.clearLogcat();
      return _drive(
        adb.device,
        label,
        _out,
        defines,
        apk,
        backend,
        noDds: true,
      );
    },
    foreignInstall: () async => hasForeignInstall(await adb.logcat(), kPackage),
  );
  final dir = '$_out/runs/$label';
  final counts = <String, Map<String, Map<String, Metric>>>{};
  // The launch's own document names the scenario versions and the combination;
  // its timing metrics are never read.
  final own = File('$dir/chat_perf_metrics.json');
  if (!own.existsSync()) {
    stderr.writeln('the traced launch wrote no document');
    return (
      code: result.value == 0 ? 1 : result.value,
      discarded: result.discarded,
      doc: null,
    );
  }
  final ownJson = jsonDecode(own.readAsStringSync()) as Map<String, Object?>;
  (ownJson['meta']! as Map<String, Object?>)
    ..['device'] = (await adb.shell('getprop ro.product.model')).trim()
    // The combination keys the baseline the counts are added to.
    ..['environment'] = _combination(run);
  final timing = MetricsDocument.fromJson(ownJson);
  var failed = false;
  for (final id in ids) {
    final key = timing.scenarios.keys.where((k) => k.split('@').first == id);
    if (key.isEmpty) continue;
    final file = File('$dir/${traceTimelineFile(id)}');
    if (!file.existsSync()) {
      stderr.writeln('no timeline for ${key.first} in the traced launch');
      continue;
    }
    counts[key.first] = traceCounts(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
    // A window the scenario measured but the timeline has no marks for lost
    // them (the ring buffer drops the oldest events): no counts then.
    final lost = timing.scenarios[key.first]!.keys.where(
      (w) => !counts[key.first]!.containsKey(w),
    );
    if (lost.isNotEmpty) {
      stderr.writeln(
        'traced launch: no window marks for ${key.first}: ${lost.join(', ')}',
      );
      failed = true;
    }
  }
  stdout.writeln(
    'traced pass: counts for ${counts.length} of ${ids.length} '
    'scenarios ($dir)',
  );
  return (
    code: failed && result.value == 0 ? 1 : result.value,
    discarded: result.discarded,
    doc: counts.isEmpty
        ? null
        : tracedDocument(meta: timing.meta, counts: counts),
  );
}

const _target = 'integration_test/chat_perf/chat_perf_test.dart';
const _driver = 'test_driver/integration_test.dart';

/// A failed `pub get` or APK build. Thrown, not `exit`ed, so the run's
/// `finally` still restores the phone's performance mode and the lock.
final class _BuildFailure implements Exception {
  const _BuildFailure(this.message);

  final String message;
}

/// The APK for these sources and defines, built when no cached one matches.
/// Throws [_BuildFailure] when resolving or building fails.
Future<String> _ensureApk(List<String> defines, String backend) async {
  // Resolve first: a pub get rewrites the lockfile, which is a fingerprint
  // input, so it must settle before the key is taken.
  final pubGet = await Process.run('flutter', ['pub', 'get']);
  if (pubGet.exitCode != 0) {
    throw _BuildFailure('flutter pub get failed:\n${pubGet.stderr}');
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
    throw const _BuildFailure('build failed');
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

/// The combination a launch ran in beyond what the app observes (spec 6.4):
/// the performance mode and the markdown engine stamp.
Map<String, Object?> _combination(_RunOptions run) => {
  'perfMode': run.perfMode.name,
  'markdown': {
    ..._markdownStamp(),
    'disposeBuiltPainters': _disposeBuiltPainters,
  },
};

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

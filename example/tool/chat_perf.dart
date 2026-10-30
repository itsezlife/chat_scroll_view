/// Runner of the chat performance suite (Android).
///
///   dart run tool/chat_perf.dart quick --device ID [--scenario GLOB,...]
///       [--label NAME] [--backend impeller|skia] [--history N]
///
/// `quick` makes one launch of the timing pass, prints the headline table and
/// writes `perf/runs/<label>/chat_perf_metrics.json` plus the per-frame
/// sidecar `chat_perf_frames.json`. No verdict, nothing promoted.
///
/// Before the launch it refuses a device that cannot give meaningful numbers,
/// takes the per-device lock, and builds (or reuses, by fingerprint) the APK.
/// A launch killed by a foreign package install is discarded and retried once.
/// The label is host-side only (`PERF_LABEL`); it is never a dart-define.
library;

import 'dart:convert';
import 'dart:io';

import '../integration_test/chat_perf/report_document.dart';
import '../integration_test/chat_perf/table.dart';
import 'chat_perf/adb.dart';
import 'chat_perf/build_fingerprint.dart';
import 'chat_perf/cooldown.dart';
import 'chat_perf/device_lock.dart';
import 'chat_perf/gates.dart';
import 'chat_perf/launch_retry.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first != 'quick') {
    stderr.writeln(
      'usage: dart run tool/chat_perf.dart quick --device ID '
      '[--scenario GLOB,...] [--label NAME] [--backend impeller|skia] '
      '[--history N]',
    );
    exit(64);
  }
  final options = _options(args.skip(1).toList());
  final device = options['device'];
  if (device == null) {
    stderr.writeln('--device ID is required (see: adb devices)');
    exit(64);
  }
  final label =
      options['label'] ??
      'quick-${DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-')}';
  final out =
      Platform.environment['PERF_OUT'] ?? '${Directory.current.path}/perf';
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

  try {
    await _run(adb, options, label, out);
  } on ForeignInstallException catch (e) {
    stderr.writeln('run failed: ${e.message}');
    exitCode = 4;
  } finally {
    lock.release();
  }
}

Future<void> _run(
  Adb adb,
  Map<String, String> options,
  String label,
  String out,
) async {
  final backend = options['backend'] ?? 'impeller';
  final defines = buildDefines(
    backend: backend,
    scenario: options['scenario'],
    history: options['history'],
  );
  final apk = await _ensureApk(defines, backend);

  final batteryStart = await adb.battery();
  var launches = 0;
  CooldownResult? cooldown;
  final result = await runWithRetry<int>(
    launch: () async {
      if (launches++ > 0) {
        cooldown = await waitForCooldown(
          startTempC: batteryStart.temperatureC,
          readTempC: () async => (await adb.battery()).temperatureC,
          sleep: Future<void>.delayed,
        );
      }
      await adb.clearLogcat();
      return _drive(adb.device, label, out, defines, apk, backend);
    },
    foreignInstall: () async => hasForeignInstall(await adb.logcat(), kPackage),
  );
  final code = result.value;

  final file = File('$out/runs/$label/chat_perf_metrics.json');
  if (!file.existsSync()) {
    stderr.writeln('launch exited $code and wrote no metrics document');
    exitCode = code == 0 ? 1 : code;
    return;
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

  stdout
    ..writeln()
    ..writeln(renderTable(MetricsDocument.fromJson(json)))
    ..writeln()
    ..writeln('metrics: ${file.path}')
    ..writeln('frames:  $out/runs/$label/chat_perf_frames.json');
  if (meta['semanticsMode'] == 'on') {
    stdout.writeln('note: semantics were on during this launch.');
  }
  exitCode = code;
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
  String backend,
) async {
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

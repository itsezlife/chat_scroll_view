/// Runner of the chat performance suite.
///
///   dart run tool/chat_perf.dart quick --device ID [--scenario GLOB,...]
///       [--label NAME] [--backend impeller|skia] [--semantics off|on|pair]
///
/// `quick` makes one launch of the timing pass, prints the headline table and
/// writes `perf/runs/<label>/chat_perf_metrics.json` plus the per-frame
/// sidecar `chat_perf_frames.json`. No verdict, nothing promoted.
library;

import 'dart:convert';
import 'dart:io';

import '../integration_test/chat_perf/report_document.dart';
import '../integration_test/chat_perf/scenarios/all_scenarios.dart';
import '../integration_test/chat_perf/semantics.dart';
import '../integration_test/chat_perf/table.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first != 'quick') {
    stderr.writeln(
      'usage: dart run tool/chat_perf.dart quick --device ID '
      '[--scenario GLOB,...] [--label NAME] [--backend impeller|skia] '
      '[--semantics off|on|pair]',
    );
    exit(64);
  }
  final options = _options(args.skip(1).toList());
  final device = options['device'];
  if (device == null) {
    stderr.writeln('--device ID is required (see: flutter devices)');
    exit(64);
  }
  final SemanticsRun semantics;
  try {
    semantics = SemanticsRun.parse(options['semantics'] ?? '');
  } on FormatException catch (e) {
    stderr.writeln('--semantics: ${e.message}');
    exit(64);
  }
  final label =
      options['label'] ??
      'quick-${DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-')}';
  final filter = options['scenario'] ?? '';

  // The shared-process set is one launch; each cold scenario gets its own
  // (spec 5), under `<label>-<scenario id>`.
  final launches = <({String label, String filter, bool cold})>[
    if (allScenarios.where(filter).isNotEmpty)
      (label: label, filter: filter, cold: false),
    for (final s in allScenarios.where(filter, cold: true))
      (label: '$label-${s.id}', filter: s.id, cold: true),
  ];
  if (launches.isEmpty) {
    stderr.writeln('no scenario matches "$filter"');
    exit(64);
  }
  var status = 0;
  for (final launch in launches) {
    final code = await _quickLaunch(device, options, semantics, launch);
    if (code != 0) status = code;
  }
  exit(status);
}

Future<int> _quickLaunch(
  String device,
  Map<String, String> options,
  SemanticsRun semantics,
  ({String label, String filter, bool cold}) launch,
) async {
  final label = launch.label;
  final process = await Process.start(
    'tool/run_chat_perf.sh',
    [device, label],
    environment: {
      if (launch.filter.isNotEmpty) 'SCENARIO': launch.filter,
      'COLD': '${launch.cold}',
      'BACKEND': options['backend'] ?? 'impeller',
      'SEMANTICS': semantics.name,
    },
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  final out = Platform.environment['PERF_OUT'] ?? 'perf';
  final file = File('$out/runs/$label/chat_perf_metrics.json');
  if (!file.existsSync()) {
    stderr.writeln('launch exited $code and wrote no metrics document');
    return code == 0 ? 1 : code;
  }

  // The app cannot read its device model or the Flutter version; fill them in.
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final meta = json['meta']! as Map<String, Object?>
    ..['device'] = await _adb(device, 'getprop ro.product.model')
    ..['flutterVersion'] = await _flutterVersion();
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));

  stdout
    ..writeln()
    ..writeln(renderTable(MetricsDocument.fromJson(json)))
    ..writeln()
    ..writeln('metrics: ${file.path}')
    ..writeln('frames:  $out/runs/$label/chat_perf_frames.json');
  if (meta['semanticsMode'] == 'on' && semantics != SemanticsRun.on) {
    stdout.writeln('note: semantics were on during this launch.');
  }
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

Future<String> _adb(String device, String command) async {
  final r = await Process.run('adb', ['-s', device, 'shell', command]);
  return r.exitCode == 0 ? (r.stdout as String).trim() : 'unknown';
}

Future<String> _flutterVersion() async {
  final r = await Process.run('flutter', ['--version', '--machine']);
  if (r.exitCode != 0) return 'unknown';
  final v = jsonDecode(r.stdout as String) as Map<String, Object?>;
  return '${v['frameworkVersion']} (${v['channel']})';
}

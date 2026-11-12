/// Writes `native/prebuilts.json` from a directory of built libraries; run
/// by the prebuilts workflow after every target built, and by a maintainer
/// the same way. From the package root:
///
/// ```sh
/// dart native/tool/assemble_manifest.dart <dir> --base-url <https url ending /> \
///   [--require key,key,... | --require-all] [--out <file>]
/// ```
///
/// `<dir>` holds only files named `libchat_lottie-<key>.<ext>`, the key being
/// one of the manifest's target keys (`LottieNativeTarget.keys`).
/// `--require-all` demands a file for every key, so the key list lives in the
/// hook and not in a workflow. Nothing is written unless every file is sound,
/// that is passes the hook's own header check for its target, so a
/// half-built or mislabelled release can never become a manifest.
library;

import 'dart:convert';
import 'dart:io';

import '../../hook/src/manifest_entry.dart';
import '../../hook/src/prebuilt_manifest.dart';
import '../../hook/src/source_hash.dart';
import '../../hook/src/targets.dart';
import 'verify_artifact.dart';

Future<void> main(List<String> args) async {
  exitCode = await runAssembleManifest(
    args,
    native: File.fromUri(Platform.script).parent.parent,
    out: stdout,
  );
}

final _libraryName = RegExp(r'^libchat_lottie-(.+)\.(?:so|dylib|dll)$');

const _usage =
    'usage: dart native/tool/assemble_manifest.dart <dir> --base-url <url> '
    '[--require key,key,...|--require-all] [--out <file>]\n'
    '  <dir> holds libchat_lottie-<key>.<so|dylib|dll> files; keys: ';

/// The command line of `native/tool/assemble_manifest.dart`; returns the exit
/// code: 0 written and verified, 1 refused (every reason is printed), 64
/// usage.
Future<int> runAssembleManifest(
  List<String> args, {
  required Directory native,
  required StringSink out,
}) async {
  final options = _Options.parse(args);
  if (options == null) {
    out.writeln('$_usage${LottieNativeTarget.keys.join(', ')}');
    return 64;
  }
  final required = options.requireAll
      ? LottieNativeTarget.keys
      : options.require;
  final unknown = required.where((k) => LottieNativeTarget.fromKey(k) == null);
  if (unknown.isNotEmpty) {
    out.writeln('unknown --require key(s): ${unknown.join(', ')}');
    return 64;
  }

  final problems = <String>[];
  final files = <String, File>{};
  final directory = Directory(options.directory);
  if (!directory.existsSync()) {
    out.writeln('no such directory: ${options.directory}');
    return 1;
  }
  final listed = directory.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in listed) {
    final name = file.uri.pathSegments.last;
    final key = _libraryName.firstMatch(name)?.group(1);
    if (key == null || LottieNativeTarget.fromKey(key) == null) {
      problems.add('$name: not a libchat_lottie-<key>.<ext> of a known key');
      continue;
    }
    final other = files[key];
    if (other != null) {
      problems.add(
        '$key: claimed by both ${other.uri.pathSegments.last} and $name',
      );
      continue;
    }
    files[key] = file;
  }
  for (final key in required) {
    if (!files.containsKey(key)) problems.add('$key: no library for it');
  }
  if (files.isEmpty && problems.isEmpty) problems.add('no libraries found');

  for (final MapEntry(:key, :value) in files.entries) {
    final problem = libraryProblem(value, LottieNativeTarget.fromKey(key)!);
    if (problem != null) problems.add('$key: $problem');
  }
  final baseUrl = options.baseUrl;
  if (problems.isEmpty) {
    try {
      PrebuiltManifest.parse(
        jsonEncode({
          'schema': 1,
          'crateVersion': '0',
          'sourceHash': '0' * 64,
          'baseUrl': baseUrl,
          'artifacts': <String, Object?>{},
        }),
      );
    } on FormatException catch (e) {
      problems.add('--base-url: ${e.message}');
    }
  }
  if (problems.isNotEmpty) {
    out.writeln('refusing to write a manifest:');
    for (final problem in problems) {
      out.writeln('  $problem');
    }
    return 1;
  }

  final artifacts = <String, Object?>{
    for (final key in (files.keys.toList()..sort()))
      key: jsonDecode(await manifestEntryFor(files[key]!)),
  };
  final manifest = <String, Object?>{
    'schema': 1,
    'crateVersion': readCrateVersion(native),
    'sourceHash': computeSourceHash(native),
    'baseUrl': baseUrl,
    'artifacts': artifacts,
  };
  final target = File(options.out ?? '${native.path}/prebuilts.json');
  target.parent.createSync(recursive: true);
  target.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );

  final mismatch = _reread(target, manifest);
  if (mismatch != null) {
    out.writeln('wrote ${target.path} but it does not verify: $mismatch');
    return 1;
  }
  out.writeln(
    'wrote ${target.path}: ${artifacts.length} artifact(s) '
    '(${(artifacts.keys.toList()..sort()).join(', ')})',
  );
  return 0;
}

/// What differs between the manifest as the hook will read it and the one
/// just built, or null. The hook's own parser is the judge of the former.
String? _reread(File written, Map<String, Object?> expected) {
  final PrebuiltManifest parsed;
  try {
    parsed = PrebuiltManifest.parse(written.readAsStringSync());
  } on FormatException catch (e) {
    return e.message;
  }
  if (parsed.sourceHash != expected['sourceHash']) return 'sourceHash';
  if (parsed.crateVersion != expected['crateVersion']) return 'crateVersion';
  final artifacts = expected['artifacts']! as Map<String, Object?>;
  if (parsed.artifacts.length != artifacts.length) return 'artifact count';
  for (final MapEntry(:key, :value) in artifacts.entries) {
    final entry = value! as Map<String, Object?>;
    final read = parsed.artifactFor(key);
    if (read == null ||
        read.file != entry['file'] ||
        read.sha256 != entry['sha256'] ||
        read.size != entry['size']) {
      return 'artifact $key';
    }
  }
  return null;
}

final class _Options {
  const _Options({
    required this.directory,
    required this.baseUrl,
    required this.require,
    required this.requireAll,
    required this.out,
  });

  static _Options? parse(List<String> args) {
    String? directory;
    String? baseUrl;
    String? out;
    var require = <String>[];
    var requireAll = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--base-url' || '--require' || '--out':
          if (i + 1 >= args.length) return null;
          final value = args[++i];
          switch (arg) {
            case '--base-url':
              baseUrl = value;
            case '--out':
              out = value;
            default:
              require = value.split(',').where((k) => k.isNotEmpty).toList();
          }
        case '--require-all':
          requireAll = true;
        case _ when arg.startsWith('--'):
          return null;
        default:
          if (directory != null) return null;
          directory = arg;
      }
    }
    if (directory == null || baseUrl == null) return null;
    return _Options(
      directory: directory,
      baseUrl: baseUrl,
      require: require,
      requireAll: requireAll,
      out: out,
    );
  }

  final String directory;
  final String baseUrl;
  final List<String> require;
  final bool requireAll;
  final String? out;
}

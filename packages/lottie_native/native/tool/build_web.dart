/// Builds the web files of `lottie_native` into a directory:
///
/// ```sh
/// dart native/tool/build_web.dart --out web/dist
/// ```
///
/// It writes `chat_lottie.wasm` (compiled with `+simd128`),
/// `chat_lottie.nosimd.wasm` (plain wasm32) and copies
/// `chat_lottie_core.mjs` and `chat_lottie_worker.js` next to them; the worker
/// picks the build with a `WebAssembly.validate` probe. The output is not
/// committed. Needs `cargo` and the Rust target (`rustup target add
/// wasm32-unknown-unknown`); it never installs anything.
library;

import 'dart:io';

import '../../hook/src/cargo_build.dart';

const _triple = 'wasm32-unknown-unknown';

/// The JS files copied from `web/` beside the wasm files.
const _scripts = ['chat_lottie_core.mjs', 'chat_lottie_worker.js'];

Future<void> main(List<String> args) async {
  exitCode = await runBuildWeb(
    args,
    native: File.fromUri(Platform.script).parent.parent,
    environment: Platform.environment,
    out: stdout,
  );
}

/// The command line of this tool. [native] is the `native/` folder; the JS
/// sources are read from its sibling `web/`. Returns the exit code.
Future<int> runBuildWeb(
  List<String> args, {
  required Directory native,
  required Map<String, String> environment,
  required StringSink out,
}) async {
  final outDir = _outArgument(args);
  if (outDir == null) {
    out.writeln('usage: dart native/tool/build_web.dart --out <dir>');
    return 64;
  }
  final String cargo;
  try {
    cargo = findCargo(environment: environment);
  } on CargoNotFound catch (e) {
    out.writeln(e);
    return 1;
  }
  final web = Directory('${native.parent.path}/web');
  for (final script in _scripts) {
    if (!File('${web.path}/$script').existsSync()) {
      out.writeln('missing ${web.path}/$script');
      return 1;
    }
  }
  Directory(outDir).createSync(recursive: true);
  // Two target directories: cargo keys its cache on the flags only loosely,
  // and sharing one would rebuild the crate on every switch.
  final builds = [
    (name: 'chat_lottie.nosimd.wasm', dir: 'wasm', flags: null),
    (
      name: 'chat_lottie.wasm',
      dir: 'wasm-simd',
      flags: '-C target-feature=+simd128',
    ),
  ];
  for (final build in builds) {
    final problem = await _cargoBuild(
      cargo: cargo,
      native: native,
      environment: environment,
      targetDir: '${native.path}/target/${build.dir}',
      rustFlags: build.flags,
    );
    if (problem != null) {
      out.writeln(problem);
      return 1;
    }
    File(
      '${native.path}/target/${build.dir}/$_triple/release/chat_lottie.wasm',
    ).copySync('$outDir/${build.name}');
  }
  for (final script in _scripts) {
    File('${web.path}/$script').copySync('$outDir/$script');
  }
  out.writeln(
    'wrote ${builds.map((b) => b.name).join(', ')} and '
    '${_scripts.join(', ')} to $outDir',
  );
  return 0;
}

String? _outArgument(List<String> args) {
  if (args.length != 2 || args[0] != '--out' || args[1].isEmpty) return null;
  return args[1];
}

/// Runs cargo for the wasm target; returns the failure message, or null.
///
/// Both flag variables are cleared so the build depends on [rustFlags] alone:
/// a developer's `RUSTFLAGS` with `+simd128` would otherwise turn the "plain"
/// build into a SIMD one, and `CARGO_ENCODED_RUSTFLAGS` outranks `RUSTFLAGS`.
Future<String?> _cargoBuild({
  required String cargo,
  required Directory native,
  required Map<String, String> environment,
  required String targetDir,
  required String? rustFlags,
}) async {
  final arguments = [
    'build',
    '--release',
    '--locked',
    '--target',
    _triple,
    '--target-dir',
    targetDir,
    '--manifest-path',
    '${native.path}/Cargo.toml',
  ];
  final env = {...environment}
    ..remove('RUSTFLAGS')
    ..remove('CARGO_ENCODED_RUSTFLAGS');
  if (rustFlags != null) env['RUSTFLAGS'] = rustFlags;
  final result = await Process.run(
    cargo,
    arguments,
    environment: env,
    includeParentEnvironment: false,
  );
  if (result.exitCode == 0) return null;
  final output = '${result.stdout}\n${result.stderr}';
  final hint = missingTargetHint(output, _triple);
  return 'cargo failed building the wasm (exit ${result.exitCode}).\n'
      '$output${hint == null ? '' : '\n$hint'}';
}

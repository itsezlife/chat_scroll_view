import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/rebuild_inputs.dart';

void main() {
  late Directory root;

  void write(String path) => File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync('x');

  Set<String> inputs() => {
    for (final uri in rebuildInputs(root.uri))
      uri.toFilePath().substring(root.path.length + 1),
  };

  setUp(() {
    root = Directory.systemTemp.createTempSync('rebuild_inputs_test');
    [
      'native/Cargo.toml',
      'native/Cargo.lock',
      'native/prebuilts.json',
      'native/include/chat_lottie.h',
      'native/src/lib.rs',
      'native/src/deep/more.rs',
      'hook/build.dart',
      'hook/src/targets.dart',
    ].forEach(write);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('declares every file the build reads, one by one', () {
    expect(
      inputs(),
      containsAll([
        'native/Cargo.toml',
        'native/Cargo.lock',
        'native/prebuilts.json',
        'native/include/chat_lottie.h',
        'native/src/lib.rs',
        'native/src/deep/more.rs',
        'hook/build.dart',
        'hook/src/targets.dart',
      ]),
    );
  });

  test('declares files, never a directory (a directory misses edits)', () {
    rebuildInputs(root.uri).forEach((uri) {
      expect(
        FileSystemEntity.isFileSync(uri.toFilePath()),
        isTrue,
        reason: '$uri',
      );
    });
  });

  test('a file added later appears', () {
    expect(inputs(), isNot(contains('native/src/new.rs')));

    write('native/src/new.rs');
    write('hook/src/new_step.dart');

    expect(
      inputs(),
      containsAll(['native/src/new.rs', 'hook/src/new_step.dart']),
    );
  });

  test('leaves out what is not an input', () {
    write('native/target/debug/x');
    write('native/tests/t.rs');
    write('lib/lottie_native.dart');

    expect(
      inputs().where(
        (p) =>
            p.startsWith('native/target') ||
            p.startsWith('native/tests') ||
            p.startsWith('lib'),
      ),
      isEmpty,
    );
  });

  test('tolerates a missing manifest', () {
    File('${root.path}/native/prebuilts.json').deleteSync();

    expect(inputs(), isNot(contains('native/prebuilts.json')));
  });

  test('covers every source file of this package', () {
    final real = {
      for (final f in Directory('native/src').listSync(recursive: true))
        if (f is File) f.absolute.path,
      for (final f in Directory('hook').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) f.absolute.path,
    };

    final declared = {
      for (final uri in rebuildInputs(Directory.current.uri)) uri.toFilePath(),
    };

    expect(declared, containsAll(real));
  });
}

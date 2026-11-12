import 'dart:io';

import 'package:test/test.dart';

// "No way to obtain an unloaded store" is a property of the types, so it is
// checked where it is enforced: by the analyzer, on code a host could write.

Future<ProcessResult> _analyze(String source) async {
  // Inside the package, so `package:content_model` resolves.
  final probe = File(
    '${Directory.current.path}/test/_probe_${DateTime.now().microsecondsSinceEpoch}.dart',
  )..writeAsStringSync(source);
  try {
    return await Process.run(Platform.resolvedExecutable, [
      'analyze',
      probe.path,
    ]);
  } finally {
    probe.deleteSync();
  }
}

void main() {
  const imports = "import 'package:content_model/content_model.dart';\n";

  test('a host can create a recents store only through load', () async {
    final result = await _analyze('''
$imports
Future<RecentsStore> make(KeyValueStore storage) =>
    KeyValueRecentsStore.load(storage, namespace: 'host');
''');

    expect(result.stdout, contains('No issues found'));
  });

  test('a host cannot construct a recents store directly', () async {
    for (final construction in [
      'KeyValueRecentsStore()',
      'KeyValueRecentsStore._(null, "", null, null)',
    ]) {
      final result = await _analyze('''
$imports
Object make() => $construction;
''');

      expect(result.exitCode, isNot(0), reason: construction);
      expect(result.stdout, contains('KeyValueRecentsStore'));
    }
  });

  test('a host can create a preference store only through load', () async {
    final result = await _analyze('''
$imports
Future<PreferenceStore> make(KeyValueStore storage) =>
    KeyValuePreferenceStore.load(storage, namespace: 'host');
''');

    expect(result.stdout, contains('No issues found'));
  });

  test('a host cannot construct a preference store directly', () async {
    for (final construction in [
      'KeyValuePreferenceStore()',
      'KeyValuePreferenceStore._(null, "")',
    ]) {
      final result = await _analyze('''
$imports
Object make() => $construction;
''');

      expect(result.exitCode, isNot(0), reason: construction);
      expect(result.stdout, contains('KeyValuePreferenceStore'));
    }
  });

  test('a host can create a content library only through load', () async {
    final result = await _analyze('''
$imports
Future<ContentLibrary> make(LibraryStorage storage) =>
    StoredContentLibrary.load(
      storage,
      limits: const LibraryLimits(favouriteStickers: 5, savedGifs: 200),
    );
''');

    expect(result.stdout, contains('No issues found'));
  });

  test('a host cannot construct a content library directly', () async {
    for (final construction in [
      'StoredContentLibrary()',
      'StoredContentLibrary._(null)',
    ]) {
      final result = await _analyze('''
$imports
Object make() => $construction;
''');

      expect(result.exitCode, isNot(0), reason: construction);
      expect(result.stdout, contains('StoredContentLibrary'));
    }
  });
}

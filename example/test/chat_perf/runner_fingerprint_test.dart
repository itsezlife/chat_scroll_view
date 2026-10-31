import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/chat_perf/build_fingerprint.dart';

List<int> _b(String s) => utf8.encode(s);

void main() {
  final files = {'a.dart': _b('one'), 'b.dart': _b('two')};
  const defines = ['CHAT_PERF_BACKEND=impeller'];

  test('is stable for the same sources and defines', () {
    expect(
      buildFingerprint(files, defines),
      buildFingerprint({...files}, [...defines]),
    );
  });

  test('changing a source file changes it', () {
    expect(
      buildFingerprint({...files, 'b.dart': _b('three')}, defines),
      isNot(buildFingerprint(files, defines)),
    );
  });

  test('adding, removing or renaming a file changes it', () {
    expect(
      buildFingerprint({...files, 'c.dart': _b('')}, defines),
      isNot(buildFingerprint(files, defines)),
    );
    expect(
      buildFingerprint({'a.dart': _b('one'), 'z.dart': _b('two')}, defines),
      isNot(buildFingerprint(files, defines)),
    );
  });

  test('changing the define set changes it, its order does not', () {
    expect(
      buildFingerprint(files, ['CHAT_PERF_BACKEND=skia']),
      isNot(buildFingerprint(files, defines)),
    );
    expect(
      buildFingerprint(files, ['A=1', 'B=2']),
      buildFingerprint(files, ['B=2', 'A=1']),
    );
  });

  test('the label is not an input: defines carry none', () {
    final d = buildDefines(backend: 'impeller', scenario: 'scroll.*');
    expect(d.any((e) => e.toLowerCase().contains('label')), isFalse);
    expect(buildDefines(backend: 'skia'), [
      'CHAT_PERF_BACKEND=skia',
      'CHAT_PERF_DISPOSE_BUILT_PAINTERS=true',
    ]);
  });
}

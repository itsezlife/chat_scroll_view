/// The cached build's key (spec 9): a fingerprint of the sources and the
/// dart-define set. The run label is never an input and never a define.
library;

/// The dart-defines compiled into the build. No label: a define is baked into
/// the cached APK, so a reused APK would keep the old label.
List<String> buildDefines({
  required String backend,
  String? scenario,
  String? history,
}) => [
  'CHAT_PERF_BACKEND=$backend',
  if (scenario != null && scenario.isNotEmpty) 'CHAT_PERF_SCENARIO=$scenario',
  if (history != null && history.isNotEmpty) 'CHAT_PERF_HISTORY=$history',
];

/// Two 32-bit FNV-1a hashes (different seeds) over the sorted defines, then
/// the files in path order (path and content), as 16 hex digits. 32-bit lanes
/// stay exact on every Dart platform.
String buildFingerprint(Map<String, List<int>> files, List<String> defines) {
  const prime = 0x01000193;
  var h1 = 0x811c9dc5;
  var h2 = 0x9747b28c;
  void feed(List<int> bytes) {
    for (final b in [...bytes, 0xff]) {
      // The 0xff is a field separator: `ab`+`c` differs from `a`+`bc`.
      h1 = ((h1 ^ b) * prime) & 0xffffffff;
      h2 = ((h2 ^ (b + 1)) * prime) & 0xffffffff;
    }
  }

  for (final d in [...defines]..sort()) {
    feed(d.codeUnits);
  }
  for (final path in files.keys.toList()..sort()) {
    feed(path.codeUnits);
    feed(files[path]!);
  }
  String hex(int v) => v.toRadixString(16).padLeft(8, '0');
  return '${hex(h1)}${hex(h2)}';
}

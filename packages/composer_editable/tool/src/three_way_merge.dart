// Three-way merge of one file, by `git merge-file`: the exact tool for it
// (foundation 1.3), present wherever this repo is checked out.

import 'dart:io';

/// The merge of [fork] over a change from [oldBase] to [newBase].
class MergeResult {
  const MergeResult(this.text, this.conflicts);

  /// The merged text; conflict hunks carry `<<<<<<<` markers.
  final String text;

  /// How many hunks conflict; 0 is a clean merge.
  final int conflicts;
}

/// Merges the three texts. [label] names the file in the conflict markers.
/// With [favorFork] a conflicting hunk takes the fork's side and no markers
/// remain; [MergeResult.conflicts] still counts them.
MergeResult threeWayMerge({
  required String fork,
  required String oldBase,
  required String newBase,
  required String label,
  bool favorFork = false,
}) {
  final dir = Directory.systemTemp.createTempSync('revendor_merge_');
  try {
    File('${dir.path}/fork').writeAsStringSync(fork);
    File('${dir.path}/old').writeAsStringSync(oldBase);
    File('${dir.path}/new').writeAsStringSync(newBase);
    final result = Process.runSync('git', [
      'merge-file',
      '-p',
      if (favorFork) '--ours',
      '-L',
      'fork $label',
      '-L',
      'old baseline',
      '-L',
      'new baseline',
      '${dir.path}/fork',
      '${dir.path}/old',
      '${dir.path}/new',
    ]);
    // Exit status is the conflict count (capped at 127); negative is an error.
    final code = result.exitCode;
    if (code < 0 || code > 127) {
      throw ProcessException('git', ['merge-file'], '${result.stderr}', code);
    }
    return MergeResult(result.stdout as String, code);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

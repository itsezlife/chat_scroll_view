// Renders DIVERGENCES.md: the hand-written purposes (the template) plus the
// facts the tool measures, so the origin label and the size of each divergence
// cannot drift from the sources (a hand-kept label once had).

import 'dart:convert';
import 'dart:io';

import 'stock_renamer.dart';
import 'vendored_files.dart';

/// Where a baseline came from, kept beside it as `SDK.json`.
class BaselineOrigin {
  const BaselineOrigin({
    required this.version,
    required this.channel,
    required this.revision,
  });

  /// Reads the fields of an SDK's `bin/cache/flutter.version.json`.
  factory BaselineOrigin.fromSdkJson(Map<String, Object?> json) =>
      BaselineOrigin(
        version: json['frameworkVersion']! as String,
        channel: json['channel']! as String,
        revision: json['frameworkRevision']! as String,
      );

  factory BaselineOrigin.fromJson(Map<String, Object?> json) => BaselineOrigin(
    version: json['version']! as String,
    channel: json['channel']! as String,
    revision: json['revision']! as String,
  );

  final String version;
  final String channel;

  /// The full framework commit.
  final String revision;

  Map<String, Object?> toJson() => {
    'version': version,
    'channel': channel,
    'revision': revision,
  };
}

/// `+added -removed` lines of [fork] against [baseline], by `git diff`.
({int added, int removed}) diffSize(File baseline, File fork) {
  final result = Process.runSync('git', [
    'diff',
    '--no-index',
    '--numstat',
    baseline.path,
    fork.path,
  ]);
  // Exit status 1 means "differs", 0 "same"; anything else is an error.
  if (result.exitCode > 1) {
    throw ProcessException(
      'git',
      ['diff'],
      '${result.stderr}',
      result.exitCode,
    );
  }
  final out = (result.stdout as String).trim();
  if (out.isEmpty) return (added: 0, removed: 0);
  final parts = out.split(RegExp(r'\s+'));
  return (added: int.parse(parts[0]), removed: int.parse(parts[1]));
}

/// The document for the package at [packageRoot], built from [template], the
/// baseline in [baselineDir] and the vendored files as they are now.
String renderDivergences({
  required String template,
  required BaselineOrigin origin,
  required Directory baselineDir,
  required Directory packageRoot,
}) {
  final vendoredFrom =
      '''
```
Flutter ${origin.version} • channel ${origin.channel}
Framework revision ${origin.revision.substring(0, 10)}
```

The sources are copies of that SDK's text input files, renamed, fixed and
formatted into the **baseline** kept in `tool/baseline/${origin.version}/`. The
package is that baseline plus the divergences below; `tool/revendor.dart` moves
it to another SDK by a three-way merge.''';

  final rows = StringBuffer()
    ..writeln('| Vendored file | Lines added | Lines removed |')
    ..writeln('| --- | ---: | ---: |');
  for (final file in vendoredFiles) {
    final size = diffSize(
      File('${baselineDir.path}/${file.baseline}'),
      File('${packageRoot.path}/${file.fork}'),
    );
    rows.writeln('| `${file.fork}` | ${size.added} | ${size.removed} |');
  }
  final baselineDiff =
      '''
Against its baseline, each vendored file changed by (git diff, lines):

${rows.toString().trimRight()}

The four handle-control files (`material/` and `cupertino/`
`*text_selection.dart`) differ from the baseline only in their imports and
assert messages, so the controls extend `ExtendedTextSelectionControls`
(divergence I). `rendering/editable.dart` is subclassed by
`ExtendedRenderEditable`, not copied.''';

  final renameRows = StringBuffer()
    ..writeln('  | Stock name | Package name |')
    ..writeln('  | --- | --- |');
  for (final entry in renames.entries) {
    renameRows.writeln('  | `${entry.key}` | `${entry.value}` |');
  }

  return template
      .replaceFirst('{{vendored_from}}', vendoredFrom)
      .replaceFirst('{{baseline_diff}}', baselineDiff)
      .replaceFirst('{{renames}}', renameRows.toString().trimRight());
}

/// Reads `SDK.json` from [baselineDir].
BaselineOrigin readOrigin(Directory baselineDir) => BaselineOrigin.fromJson(
  jsonDecode(File('${baselineDir.path}/SDK.json').readAsStringSync())
      as Map<String, Object?>,
);

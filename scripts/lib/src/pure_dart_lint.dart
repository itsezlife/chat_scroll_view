import 'package:workspace_check/src/library_file.dart';
import 'package:workspace_check/src/violation.dart';
import 'package:workspace_check/src/workspace.dart';

/// Keeps the pure-Dart packages free of Flutter.
///
/// `content_model` is depended on by every other package, including logic
/// packages that must run and be tested without a Flutter engine, so a single
/// Flutter import there would drag the engine into all of them.
/// `emoji_catalog_pack` and `emoji_data` are the emoji logic over it: data
/// readers, sources and the glyph probe take bytes and strings, and the host
/// supplies the asset bundle and the rasteriser. Two things are reported:
///
/// - **A Flutter SDK dependency**, in `dependencies:` or `dev_dependencies:`
///   (`flutter`, `flutter_test`, `flutter_web_plugins`, ...). It also forces
///   `flutter test` where `dart test` suffices.
/// - **An import or export** under `lib/` of a Flutter library
///   (`package:flutter/...`, `package:flutter_*/...`) or of `dart:ui` /
///   `dart:ui_web`, which only a Flutter engine provides. Conditional
///   directives are checked on every branch.
///
/// Rules naming a package that is not in the workspace yet are inert, like the
/// other lints.
abstract final class PureDartLint {
  static const Set<String> _pureDart = <String>{
    'content_model',
    'emoji_catalog_pack',
    'emoji_data',
  };

  // `package:flutter/` and `package:flutter_<name>/`, but not a package that
  // merely starts with the word (`flutterish`).
  static final RegExp _flutterLibrary = RegExp(
    r'^(package:flutter(_[a-z0-9_]+)?/|dart:ui(_web)?$)',
  );

  /// SDK-dependency breaches first, then import breaches in file and source
  /// order, per member in member order.
  static List<Violation> check(WorkspaceGraph graph) => <Violation>[
    for (final member in graph.members)
      if (_pureDart.contains(member.name)) ...[
        if (member.usesFlutter)
          Violation(
            LintRule.flutterInPureDartPackage,
            '${member.name} depends on the Flutter SDK',
          ),
        for (final file in LibraryFile.allIn(graph, member))
          for (final directive in file.directives)
            for (final uri in directive.uris)
              if (_flutterLibrary.hasMatch(uri))
                Violation(
                  LintRule.flutterInPureDartPackage,
                  '${file.repoPath} imports $uri',
                ),
      ],
  ];
}

import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

import 'fixture_workspace.dart';

void main() {
  late FixtureWorkspace fixture;

  setUp(() => fixture = FixtureWorkspace());
  tearDown(() => fixture.dispose());

  List<Violation> lint() =>
      PureDartLint.check(WorkspaceGraph.load(fixture.path));

  test('passes for a pure-Dart content_model', () {
    fixture.member(
      'content_model',
      dependencies: ['meta'],
      files: {
        'lib/content_model.dart':
            "import 'dart:async';\n"
            "import 'package:meta/meta.dart';\n"
            "export 'src/key.dart';\n",
      },
    );

    expect(lint(), isEmpty);
  });

  for (final name in ['emoji_catalog_pack', 'emoji_data']) {
    test('holds $name to the same rules', () {
      fixture.member(
        name,
        dependencies: ['flutter'],
        files: {'lib/$name.dart': "import 'package:flutter/services.dart';\n"},
      );

      expect(lint().map((v) => v.subject), [
        '$name depends on the Flutter SDK',
        'packages/$name/lib/$name.dart imports package:flutter/services.dart',
      ]);
    });
  }

  test('reports a Flutter SDK dependency', () {
    fixture.member(
      'content_model',
      dependencies: ['flutter'],
      files: {'lib/content_model.dart': ''},
    );

    final violations = lint();

    expect(violations.map((v) => v.rule), [LintRule.flutterInPureDartPackage]);
    expect(
      violations.single.subject,
      'content_model depends on the Flutter SDK',
    );
  });

  test('reports Flutter reached through a dev dependency', () {
    fixture.member(
      'content_model',
      devDependencies: ['flutter_test'],
      files: {'lib/content_model.dart': ''},
    );

    expect(lint().map((v) => v.rule), [LintRule.flutterInPureDartPackage]);
  });

  test('reports an import of a Flutter library', () {
    fixture.member(
      'content_model',
      files: {
        'lib/content_model.dart':
            "import 'package:flutter/foundation.dart';\n"
            "import 'package:flutter_web_plugins/url_strategy.dart';\n",
      },
    );

    final violations = lint();

    expect(violations.map((v) => v.rule), [
      LintRule.flutterInPureDartPackage,
      LintRule.flutterInPureDartPackage,
    ]);
    expect(violations.map((v) => v.subject), [
      'packages/content_model/lib/content_model.dart imports '
          'package:flutter/foundation.dart',
      'packages/content_model/lib/content_model.dart imports '
          'package:flutter_web_plugins/url_strategy.dart',
    ]);
  });

  test('reports dart:ui, which only a Flutter engine provides', () {
    fixture.member(
      'content_model',
      files: {
        'lib/src/paint.dart':
            "import 'dart:ui';\n"
            "export 'dart:ui_web';\n",
      },
    );

    expect(lint().map((v) => v.subject), [
      'packages/content_model/lib/src/paint.dart imports dart:ui',
      'packages/content_model/lib/src/paint.dart imports dart:ui_web',
    ]);
  });

  test('reports a Flutter branch of a conditional import', () {
    fixture.member(
      'content_model',
      files: {
        'lib/content_model.dart':
            "import 'stub.dart' if (dart.library.ui) 'package:flutter/ui.dart';\n",
      },
    );

    expect(lint().map((v) => v.rule), [LintRule.flutterInPureDartPackage]);
  });

  test('does not mistake a package that merely starts with the word', () {
    fixture.member(
      'content_model',
      dependencies: ['flutterish'],
      files: {
        'lib/content_model.dart': "import 'package:flutterish/x.dart';\n",
      },
    );

    expect(lint(), isEmpty);
  });

  test('leaves every other member free to use Flutter', () {
    fixture
      ..member(
        'content_model',
        files: {'lib/content_model.dart': "import 'dart:core';\n"},
      )
      ..member(
        'chrome_foundation',
        dependencies: ['flutter'],
        files: {
          'lib/chrome_foundation.dart':
              "import 'package:flutter/widgets.dart';\n",
        },
      );

    expect(lint(), isEmpty);
  });

  test('is inert while the pure-Dart package is not in the workspace', () {
    fixture.member(
      'other',
      dependencies: ['flutter'],
      files: {'lib/other.dart': "import 'package:flutter/widgets.dart';\n"},
    );

    expect(lint(), isEmpty);
  });
}

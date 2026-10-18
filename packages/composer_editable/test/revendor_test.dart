import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/divergences_doc.dart';
import '../tool/src/sdk_pins.dart';
import '../tool/src/stock_renamer.dart';
import '../tool/src/three_way_merge.dart';
import '../tool/src/vendored_files.dart';

/// The re-vendor tool's parts, and the facts it keeps true: the baseline is
/// the one the pin names, DIVERGENCES.md is what the tool writes, and every
/// place that pins the SDK pins the same one. The whole run (SDK copy,
/// `dart fix`, merge, suite) is a command, not a test; see the package README.
void main() {
  group('rename', () {
    test('replaces whole words only', () {
      expect(
        renameSymbols('EditableText EditableTextState _EditableTextState'),
        'ExtendedEditableText ExtendedEditableTextState _EditableTextState',
      );
      expect(
        renameSymbols('TextField TextFieldTapRegion TextFieldState'),
        'ExtendedTextField TextFieldTapRegion TextFieldState',
      );
    });

    test('a longer name is not eaten by the name inside it', () {
      expect(
        renameSymbols('TextSelectionHandleControls TextSelectionControls'),
        'ExtendedTextSelectionHandleControls ExtendedTextSelectionControls',
      );
      expect(
        renameSymbols('TextSelectionOverlay SelectionOverlay'),
        'ExtendedTextSelectionOverlay ExtendedSelectionOverlay',
      );
    });

    test('lower-case instances follow their types', () {
      expect(
        renameSymbols(
          'emptyTextSelectionControls materialTextSelectionControls',
        ),
        'extendedEmptyTextSelectionControls '
        'extendedMaterialTextSelectionControls',
      );
    });

    test('Flutter-owned names are kept', () {
      const kept =
          'ClipboardStatus TextEditingController TextSelectionDelegate';
      expect(renameSymbols(kept), kept);
    });

    test('no replacement is itself renamed again', () {
      for (final to in renames.values) {
        expect(renameSymbols(to), to);
      }
    });
  });

  group('relative imports', () {
    const editable = VendoredFile(
      'widgets/editable_text.dart',
      'lib/src/widget/editable_text.dart',
    );
    const field = VendoredFile(
      'material/text_field.dart',
      'lib/src/material/text_field.dart',
    );

    test('a vendored sibling becomes a package URI of this package', () {
      expect(
        rewriteRelativeImports("import 'text_selection.dart';", editable),
        "import 'package:composer_editable/src/widget/text_selection.dart';",
      );
    });

    test('anything else becomes a package:flutter/src URI', () {
      expect(
        rewriteRelativeImports("import 'actions.dart';", editable),
        "import 'package:flutter/src/widgets/actions.dart';",
      );
      expect(
        rewriteRelativeImports("import '../widgets/basic.dart';", field),
        "import 'package:flutter/src/widgets/basic.dart';",
      );
      expect(
        rewriteRelativeImports(
          "import '../widgets/editable_text.dart';",
          field,
        ),
        "import 'package:composer_editable/src/widget/editable_text.dart';",
      );
    });

    test('package and dart URIs and configuration URIs stay', () {
      const source =
          "import 'dart:ui';\n"
          "import 'package:flutter/foundation.dart';\n"
          "import '_web_browser_detection_io.dart'\n"
          "    if (dart.library.js_interop) '_web_browser_detection_web.dart';";
      expect(
        rewriteRelativeImports(source, editable),
        "import 'dart:ui';\n"
        "import 'package:flutter/foundation.dart';\n"
        "import 'package:composer_editable/src/widget/_web_browser_detection_io.dart'\n"
        "    if (dart.library.js_interop) '_web_browser_detection_web.dart';",
      );
    });
  });

  group('three-way merge', () {
    test('takes a change on one side and keeps the other', () {
      final result = threeWayMerge(
        fork: 'a\nfork\nc\nd\ne\n',
        oldBase: 'a\nb\nc\nd\ne\n',
        newBase: 'a\nb\nc\nd\nupstream\n',
        label: 'x',
      );
      expect(result.conflicts, 0);
      expect(result.text, 'a\nfork\nc\nd\nupstream\n');
    });

    test('counts the hunks both sides changed', () {
      final result = threeWayMerge(
        fork: 'fork1\nm\nm\nm\nm\nm\nfork2\n',
        oldBase: 'a\nm\nm\nm\nm\nm\nb\n',
        newBase: 'up1\nm\nm\nm\nm\nm\nup2\n',
        label: 'x',
      );
      expect(result.conflicts, 2);
      expect(result.text, contains('<<<<<<< fork x'));
      expect(result.text, contains('>>>>>>> new baseline'));
    });

    test('an unchanged baseline leaves the fork as it is', () {
      const text = 'a\nb\nc\n';
      final result = threeWayMerge(
        fork: 'a\nmine\nc\n',
        oldBase: text,
        newBase: text,
        label: 'x',
      );
      expect(result.conflicts, 0);
      expect(result.text, 'a\nmine\nc\n');
    });
  });

  group('SDK pins', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('pins_');
      addTearDown(() => root.deleteSync(recursive: true));
      void write(String path, String text) => File('${root.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
      write(
        'packages/composer_editable/pubspec.yaml',
        'environment:\n  sdk: ^3.11.0\n  flutter: 3.41.7\n',
      );
      write(
        'pubspec.yaml',
        'environment:\n  sdk: ^3.11.0\n  flutter: 3.41.7\n',
      );
      write('.fvmrc', '{\n  "flutter": "3.41.7"\n}\n');
      write(
        '.github/workflows/check.yml',
        'steps:\n  - with:\n      flutter-version: 3.41.7\n      cache: true\n',
      );
    });

    test('are read from every file that exists', () {
      final pins = readPins(root);
      expect(pins['pubspec.yaml'], '3.41.7');
      expect(pins['.fvmrc'], '3.41.7');
      expect(pins['.github/workflows/check.yml'], '3.41.7');
      expect(pins['.github/workflows/benchmarks.yml'], isNull);
    });

    test('are raised together and nothing else changes', () {
      writePins(root, '3.44.0');
      expect(readPins(root).values.whereType<String>().toSet(), {'3.44.0'});
      expect(
        File('${root.path}/.github/workflows/check.yml').readAsStringSync(),
        'steps:\n  - with:\n      flutter-version: 3.44.0\n      cache: true\n',
      );
    });

    test('a file without its version line is an error, not a skip', () {
      File('${root.path}/.fvmrc').writeAsStringSync('{}');
      expect(() => writePins(root, '3.44.0'), throwsStateError);
    });
  });

  group('this repository', () {
    final packageRoot = Directory.current;
    final repoRoot = findRepoRoot(packageRoot);

    test('pins one SDK everywhere', () {
      final pins = readPins(repoRoot);
      expect(pins.values, everyElement(isNotNull), reason: '$pins');
      expect(pins.values.toSet(), hasLength(1), reason: '$pins');
    });

    test('keeps the baseline of the pinned SDK, for every vendored file', () {
      final pinned = readPin(repoRoot, sdkPins.first)!;
      final dir = Directory('tool/baseline/$pinned');
      expect(readOrigin(dir).version, pinned);
      for (final file in vendoredFiles) {
        expect(
          File('${dir.path}/${file.baseline}').existsSync(),
          isTrue,
          reason: file.baseline,
        );
        expect(File(file.fork).existsSync(), isTrue, reason: file.fork);
      }
      expect(
        Directory('tool/baseline').listSync().whereType<Directory>(),
        hasLength(1),
        reason: 'only the pinned SDK keeps a baseline',
      );
    });

    test('DIVERGENCES.md is what the tool writes', () {
      final pinned = readPin(repoRoot, sdkPins.first)!;
      final dir = Directory('tool/baseline/$pinned');
      final expected = renderDivergences(
        template: File('tool/divergences.template.md').readAsStringSync(),
        origin: readOrigin(dir),
        baselineDir: dir,
        packageRoot: packageRoot,
      );
      expect(
        File('DIVERGENCES.md').readAsStringSync(),
        expected,
        reason:
            'edit tool/divergences.template.md and run '
            'dart tool/revendor.dart --baseline-only',
      );
    });

    test('never grows a lib/src/widgets directory', () {
      expect(Directory('lib/src/widgets').existsSync(), isFalse);
    });
  });
}

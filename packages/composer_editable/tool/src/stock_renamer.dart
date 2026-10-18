// Turns a stock Flutter source into its renamed form: the text the fork starts
// from before any divergence. Pure text in, text out; the re-vendor tool runs
// `dart fix` and `dart format` afterwards.

import 'vendored_files.dart';

/// The names the package carries under an `Extended` prefix.
///
/// Whole-word replacements, longest first so a prefix never wins over the name
/// it is part of. Private names (`_TextFieldState`) are untouched: `_` is a word
/// character, so no boundary stands before the capital.
const Map<String, String> renames = {
  'EditableTextContextMenuBuilder': 'ExtendedEditableTextContextMenuBuilder',
  'EditableTextState': 'ExtendedEditableTextState',
  'EditableText': 'ExtendedEditableText',
  'TextField': 'ExtendedTextField',
  'TextSelectionGestureDetectorBuilderDelegate':
      'ExtendedTextSelectionGestureDetectorBuilderDelegate',
  'TextSelectionGestureDetectorBuilder':
      'ExtendedTextSelectionGestureDetectorBuilder',
  'TextSelectionGestureDetector': 'ExtendedTextSelectionGestureDetector',
  'TextSelectionHandleControls': 'ExtendedTextSelectionHandleControls',
  'TextSelectionControls': 'ExtendedTextSelectionControls',
  'TextSelectionOverlay': 'ExtendedTextSelectionOverlay',
  'SelectionOverlay': 'ExtendedSelectionOverlay',
  'ClipboardStatusNotifier': 'ExtendedClipboardStatusNotifier',
  'EmptyTextSelectionControls': 'ExtendedEmptyTextSelectionControls',
  'emptyTextSelectionControls': 'extendedEmptyTextSelectionControls',
  'ToolbarItemsParentData': 'ExtendedToolbarItemsParentData',
  'ToolbarBuilder': 'ExtendedToolbarBuilder',
  'MaterialTextSelectionHandleControls':
      'ExtendedMaterialTextSelectionHandleControls',
  'MaterialTextSelectionControls': 'ExtendedMaterialTextSelectionControls',
  'DesktopTextSelectionHandleControls':
      'ExtendedDesktopTextSelectionHandleControls',
  'DesktopTextSelectionControls': 'ExtendedDesktopTextSelectionControls',
  'CupertinoTextSelectionHandleControls':
      'ExtendedCupertinoTextSelectionHandleControls',
  'CupertinoTextSelectionControls': 'ExtendedCupertinoTextSelectionControls',
  'CupertinoDesktopTextSelectionHandleControls':
      'ExtendedCupertinoDesktopTextSelectionHandleControls',
  'CupertinoDesktopTextSelectionControls':
      'ExtendedCupertinoDesktopTextSelectionControls',
  'materialTextSelectionHandleControls':
      'extendedMaterialTextSelectionHandleControls',
  'materialTextSelectionControls': 'extendedMaterialTextSelectionControls',
  'desktopTextSelectionHandleControls':
      'extendedDesktopTextSelectionHandleControls',
  'desktopTextSelectionControls': 'extendedDesktopTextSelectionControls',
  'cupertinoTextSelectionHandleControls':
      'extendedCupertinoTextSelectionHandleControls',
  'cupertinoTextSelectionControls': 'extendedCupertinoTextSelectionControls',
  'cupertinoDesktopTextSelectionHandleControls':
      'extendedCupertinoDesktopTextSelectionHandleControls',
  'cupertinoDesktopTextSelectionControls':
      'extendedCupertinoDesktopTextSelectionControls',
};

final RegExp _renamePattern = RegExp('\\b(${renames.keys.join('|')})\\b');

/// Applies [renames] to [source] in one pass, so a replacement is never
/// rewritten again.
String renameSymbols(String source) =>
    source.replaceAllMapped(_renamePattern, (m) => renames[m[1]]!);

/// The package URI the fork imports `file` by.
String _forkUri(VendoredFile file) =>
    'package:composer_editable/${file.fork.substring('lib/'.length)}';

// A relative `import 'x.dart'`. A configuration URI (`if (...) 'x.dart'`) is
// left relative: the analyzer's `always_use_package_imports` does not see it.
final RegExp _relativeImport = RegExp(
  "^(import|export) '([^':]+)'",
  multiLine: true,
);

/// Rewrites the relative imports of [file] to package URIs: a sibling that is
/// vendored too becomes `package:composer_editable/...`, anything else
/// `package:flutter/src/...`.
String rewriteRelativeImports(String source, VendoredFile file) =>
    source.replaceAllMapped(_relativeImport, (m) {
      final resolved = _normalize('${file.stockDir}/${m[2]}');
      final vendored = vendoredFiles.where((v) => v.stock == resolved);
      final uri = vendored.isNotEmpty
          ? _forkUri(vendored.first)
          : 'package:flutter/src/$resolved';
      return "${m[1]} '$uri'";
    });

String _normalize(String path) {
  final out = <String>[];
  for (final part in path.split('/')) {
    if (part == '..') {
      out.removeLast();
    } else if (part != '.') {
      out.add(part);
    }
  }
  return out.join('/');
}

/// [source] renamed and with package imports, not yet formatted.
String renameStockSource(String source, VendoredFile file) =>
    renameSymbols(rewriteRelativeImports(source, file));

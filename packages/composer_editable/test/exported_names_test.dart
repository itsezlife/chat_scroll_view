import 'dart:io';

import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The copied selection types sit beside Flutter's own under `Extended` names.
///
/// The sources are whole copies of Flutter files, so the types they declare
/// used to carry Flutter's names: a host importing both libraries had to hide
/// one, and a stock `TextSelectionControls` would not type-check against the
/// copy for a reason the import never showed. The prefix makes both visible at
/// the import.
void main() {
  group('type identity', () {
    // A list of one type is a list of the other only if the first is a
    // subtype of the second, so this checks the types without needing an
    // instance of the abstract or overlay ones.
    test('no Extended selection type is a Flutter selection type', () {
      expect(
        <ExtendedTextSelectionControls>[],
        isNot(isA<List<TextSelectionControls>>()),
      );
      expect(
        <ExtendedTextSelectionHandleControls>[],
        isNot(isA<List<TextSelectionHandleControls>>()),
      );
      expect(
        <ExtendedSelectionOverlay>[],
        isNot(isA<List<SelectionOverlay>>()),
      );
      expect(
        <ExtendedTextSelectionOverlay>[],
        isNot(isA<List<TextSelectionOverlay>>()),
      );
      expect(
        <ExtendedClipboardStatusNotifier>[],
        isNot(isA<List<ClipboardStatusNotifier>>()),
      );
    });

    test('the handle-control instances are not Flutter controls', () {
      final instances = <Object>[
        extendedEmptyTextSelectionControls,
        extendedMaterialTextSelectionControls,
        extendedMaterialTextSelectionHandleControls,
        extendedDesktopTextSelectionControls,
        extendedDesktopTextSelectionHandleControls,
        extendedCupertinoTextSelectionControls,
        extendedCupertinoTextSelectionHandleControls,
        extendedCupertinoDesktopTextSelectionControls,
        extendedCupertinoDesktopTextSelectionHandleControls,
      ];

      for (final instance in instances) {
        expect(instance, isA<ExtendedTextSelectionControls>());
        expect(instance, isNot(isA<TextSelectionControls>()));
      }
      expect(
        extendedMaterialTextSelectionHandleControls,
        isA<ExtendedTextSelectionHandleControls>(),
      );
    });
  });

  group('names', () {
    // Every identifier in the barrel's `show` lists.
    final exported = <String>{
      for (final show in RegExp(
        r'\bshow\b([^;]*);',
      ).allMatches(File('lib/composer_editable.dart').readAsStringSync()))
        ...RegExp(
          r'[A-Za-z_]\w*',
        ).allMatches(show.group(1)!).map((m) => m.group(0)!),
    };

    // Top-level names Flutter's widgets, material and cupertino libraries
    // declare, found in the SDK the tests run on.
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final declaration = RegExp(
      r'^(?:(?:abstract|sealed|final|base|interface|mixin)\s+)*'
      r'(?:class|enum|typedef|mixin|extension type)\s+([A-Za-z]\w*)|'
      r'^(?:const|final)\s+(?:[\w<>?,]+\s+)?([A-Za-z]\w*)\s*=|'
      r'^[A-Za-z][\w<>?,.]*\s+([A-Za-z]\w*)\(',
      multiLine: true,
    );

    test('are not Flutter widgets, material or cupertino names', () {
      expect(flutterRoot, isNotNull, reason: 'flutter test sets FLUTTER_ROOT');
      final flutterNames = <String>{
        for (final library in const ['widgets', 'material', 'cupertino'])
          for (final entity in Directory(
            '$flutterRoot/packages/flutter/lib/src/$library',
          ).listSync())
            if (entity is File && entity.path.endsWith('.dart'))
              for (final match in declaration.allMatches(
                entity.readAsStringSync(),
              ))
                match.group(1) ?? match.group(2) ?? match.group(3)!,
      };
      expect(flutterNames, contains('TextSelectionControls'), reason: 'scan');

      expect(exported.intersection(flutterNames), isEmpty);
      expect(exported, contains('ExtendedTextField'));
    });
  });
}

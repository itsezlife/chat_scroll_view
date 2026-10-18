import 'dart:io';
import 'dart:ui' as ui;

import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The selection chrome reads only what a release build also has.
///
/// The framework's pipeline-phase flags (`debugActiveLayout`,
/// `debugDoingPaint`, ...) are set only inside asserts, so a runtime branch on
/// them takes a different path in release than in the tests. The former guards
/// are gone; these tests cover the paths they protected, and a source check
/// keeps the flags out.
void main() {
  group('source', () {
    final sources = <File>[
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart')) entity,
    ];

    test('does not branch on a debug-only pipeline flag', () {
      final flags = RegExp(
        r'debugActiveLayout|debugDoingThisLayout|debugDoingThisResize|'
        r'debugDoingPaint|debugDoingThisLayoutWithCallback',
      );

      final offenders = <String>[
        for (final file in sources)
          if (flags.hasMatch(file.readAsStringSync())) file.path,
      ];

      expect(offenders, isEmpty);
    });

    test('does not write to the framework\'s visibility notifiers', () {
      final downcast = RegExp(r'is!? ValueNotifier');

      final offenders = <String>[
        for (final file in sources)
          if (downcast.hasMatch(file.readAsStringSync())) file.path,
      ];

      expect(offenders, isEmpty);
    });
  });

  group('selection chrome', () {
    const lineCount = 30;
    final text = [for (var i = 0; i < lineCount; i++) 'line $i'].join('\n');

    late TextEditingController controller;
    late ScrollController scroll;

    Future<ExtendedRenderEditable> pumpTallField(WidgetTester tester) async {
      controller = TextEditingController(text: text);
      scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: ExtendedTextField(
                  controller: controller,
                  scrollController: scroll,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 16, height: 1.25),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .state<ExtendedEditableTextState>(find.byType(ExtendedEditableText))
          .renderEditable;
    }

    Future<void> scrollTo(WidgetTester tester, double pixels) async {
      scroll.jumpTo(pixels);
      await tester.pump();
    }

    testWidgets('keeps the toolbar for a selection whose ends are off screen', (
      tester,
    ) async {
      final render = await pumpTallField(tester);
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
      await tester.pump();

      await scrollTo(tester, scroll.position.maxScrollExtent / 2);

      expect(render.startHandleInViewport.value, isFalse);
      expect(render.endHandleInViewport.value, isFalse);
      expect(
        render.selectionIntersectsViewport.value,
        isTrue,
        reason: 'the middle of the selection is still on screen',
      );
    });

    testWidgets('hides everything once the selection scrolls out of view', (
      tester,
    ) async {
      final render = await pumpTallField(tester);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );
      await scrollTo(tester, 0);
      expect(render.startHandleInViewport.value, isTrue);
      expect(render.selectionIntersectsViewport.value, isTrue);

      await scrollTo(tester, scroll.position.maxScrollExtent);

      expect(render.startHandleInViewport.value, isFalse);
      expect(render.endHandleInViewport.value, isFalse);
      expect(render.selectionIntersectsViewport.value, isFalse);
    });

    testWidgets('a handle stays while its line is only partly cropped', (
      tester,
    ) async {
      final render = await pumpTallField(tester);
      // Start on line 1, then scroll half a line past its top edge: the
      // caret's top is outside the text area, the rest of it is inside.
      controller.selection = const TextSelection(
        baseOffset: 7,
        extentOffset: 14,
      );
      await tester.pump();
      await scrollTo(tester, render.preferredLineHeight * 1.5);

      expect(
        render.selectionStartInViewport.value,
        isFalse,
        reason: 'stock asks only about the top edge of the caret',
      );
      expect(render.startHandleInViewport.value, isTrue);
    });

    testWidgets('paints the stock highlight, as wide as the widest line', (
      tester,
    ) async {
      final render = await pumpTallField(tester);
      controller.text = 'ab\nabcdefghijklmnop';
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.pump();

      expect(render.painter, isNull);
      expect(render.selectionColor, isNotNull);
      expect(render.selectionWidthStyle, ui.BoxWidthStyle.max);
      final boxes = render.getBoxesForSelection(controller.selection);
      expect(
        boxes[1].right,
        closeTo(boxes.last.right, 0.5),
        reason: 'a tight highlight would stop at the end of "ab"',
      );
    });

    testWidgets('a selection change under a scrolled field settles in a frame', (
      tester,
    ) async {
      final render = await pumpTallField(tester);

      await scrollTo(tester, render.preferredLineHeight * 10);
      controller.selection = const TextSelection(
        baseOffset: 70,
        extentOffset: 77,
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(render.selectionIntersectsViewport.value, isTrue);
    });
  });
}

/// The composer's field is the leaf editable (`ExtendedTextField`): its
/// scroll mirror, its overscroll handoff and its Material handles.
///
/// **Seam:** a [ComposerView] over a [ComposerController], observed through
/// the controller's `fieldScroll`, a parent scrollable around the view, and
/// the selection controls the editable runs with.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

// More lines than the field's maximum, so the field scrolls.
final _sixLines = RichText(
  List.generate(12, (i) => 'line $i').join('\n'),
  const [],
);

void main() {
  late ComposerController controller;

  setUp(() => controller = ComposerController());
  tearDown(() => controller.dispose());

  ExtendedEditableText editable(WidgetTester tester) =>
      tester.widget<ExtendedEditableText>(find.byType(ExtendedEditableText));

  group('scroll', () {
    late ScrollController page;

    setUp(() => page = ScrollController());
    tearDown(() => page.dispose());

    // The composer over a taller page, as it sits over a scrolling chat.
    Future<void> pumpOverPage(WidgetTester tester) async {
      await tester.pumpWidget(
        composerHarness(
          SizedBox(
            height: 700,
            child: SingleChildScrollView(
              controller: page,
              child: Column(
                children: [
                  const SizedBox(height: 300),
                  ComposerView(controller: controller, spec: ComposerSpec()),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      );
      controller
        ..restore(_sixLines)
        ..requestFocus();
      await tester.pumpAndSettle();
    }

    testWidgets('fieldScroll is the mirror of the field: jumpTo moves it', (
      tester,
    ) async {
      await pumpOverPage(tester);
      final position = controller.fieldScroll.position;
      expect(position.maxScrollExtent, greaterThan(0));

      double firstLineTop() => tester
          .state<ExtendedEditableTextState>(find.byType(ExtendedEditableText))
          .renderEditable
          .getLocalRectForCaret(const TextPosition(offset: 0))
          .top;
      // The draft's caret is at its end, so the field starts scrolled to it.
      expect(firstLineTop(), lessThan(-30));
      controller.fieldScroll.jumpTo(30);
      await tester.pump();

      expect(controller.fieldScroll.position.pixels, 30);
      expect(firstLineTop(), closeTo(-30, 0.5));
    });

    testWidgets('a drag past the field\'s end hands the rest to the parent', (
      tester,
    ) async {
      await pumpOverPage(tester);
      page.jumpTo(100);
      controller.fieldScroll.jumpTo(
        controller.fieldScroll.position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
      final pageBefore = page.offset;

      await tester.drag(find.byType(ExtendedTextField), const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(
        controller.fieldScroll.position.pixels,
        controller.fieldScroll.position.maxScrollExtent,
      );
      expect(page.offset, greaterThan(pageBefore));
    });

    testWidgets('the field hands overscroll off and adds no content padding', (
      tester,
    ) async {
      await pumpOverPage(tester);
      final field = tester.widget<ExtendedTextField>(
        find.byType(ExtendedTextField),
      );

      expect(field.delegateOverscrollToParent, isTrue);
      expect(field.contentScrollPadding, EdgeInsets.zero);
    });
  });

  group('handles', () {
    testWidgets(
      'are the Material ones on a touch platform, iOS included',
      (tester) async {
        await tester.pumpWidget(
          composerHarness(
            ComposerView(controller: controller, spec: ComposerSpec()),
          ),
        );

        expect(
          editable(tester).selectionControls,
          same(extendedMaterialTextSelectionHandleControls),
        );
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  });
}

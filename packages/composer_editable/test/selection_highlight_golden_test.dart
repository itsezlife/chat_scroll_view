import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Regenerate with `flutter test --update-goldens test/selection_highlight_golden_test.dart`.
// Generated on macOS with the test font, at the default device pixel ratio.
// Compared exactly: a seam is a one pixel row, which any tolerance would hide.
void main() {
  late GoldenFileComparator saved;

  setUp(() {
    saved = goldenFileComparator;
    goldenFileComparator = LocalFileComparator(
      Uri.file('test/selection_highlight_golden_test.dart'),
    );
  });

  tearDown(() {
    goldenFileComparator = saved;
  });

  testWidgets(
    'a multi-line selection on desktop is one shape',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(240, 190));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = TextEditingController(
        text: 'lwfwefewfwf\nfkwlefwlfklwfwf\nwf\nwf\nwf\nw',
      );
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            textSelectionTheme: const TextSelectionThemeData(
              selectionColor: Color(0x665588FF),
            ),
          ),
          home: RepaintBoundary(
            key: const ValueKey('golden'),
            child: ColoredBox(
              color: const Color(0xFF1F2428),
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ExtendedTextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    maxLines: null,
                    showCursor: false,
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 12,
                      height: 1.3,
                    ),
                    decoration: const InputDecoration.collapsed(hintText: null),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.pump();

      await expectLater(
        find.byKey(const ValueKey('golden')),
        matchesGoldenFile('goldens/selection_highlight_multiline.png'),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

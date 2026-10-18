import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A context menu returned inside `ExtendedSelfFadingToolbar` is not faded by
/// the toolbar wrapper; any other menu is.
///
/// **Seam:** an `ExtendedTextField` whose menu builder returns a probe, with
/// the selection shown and then hidden by a scroll in the field.
void main() {
  const text = 'one two three four';

  Future<ExtendedEditableTextState> pumpField(
    WidgetTester tester,
    ExtendedEditableTextContextMenuBuilder menu,
  ) async {
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExtendedTextField(
            controller: controller,
            contextMenuBuilder: menu,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ExtendedTextField));
    await tester.pump();
    final editable = tester.state<ExtendedEditableTextState>(
      find.byType(ExtendedEditableText),
    );
    editable.userUpdateTextEditingValue(
      editable.textEditingValue.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 3),
      ),
      SelectionChangedCause.longPress,
    );
    await tester.pump();
    editable.showToolbar();
    return editable;
  }

  double fadeOf(WidgetTester tester) {
    final fades = tester.widgetList<FadeTransition>(
      find.ancestor(
        of: find.byKey(const Key('probe')),
        matching: find.byType(FadeTransition),
      ),
    );
    return fades.fold<double>(
      1,
      (product, fade) => product * fade.opacity.value,
    );
  }

  testWidgets('a plain menu is faded in by the wrapper over 150 ms', (
    tester,
  ) async {
    await pumpField(
      tester,
      (context, editable) =>
          const SizedBox(key: Key('probe'), width: 40, height: 40),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));

    expect(fadeOf(tester), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(fadeOf(tester), 1);
  });

  testWidgets('a self-fading menu gets no wrapper fade and the visibility', (
    tester,
  ) async {
    ValueListenable<bool>? seen;
    await pumpField(
      tester,
      (context, editable) => ExtendedSelfFadingToolbar(
        builder: (context, visibility) {
          seen = visibility;
          return const SizedBox(key: Key('probe'), width: 40, height: 40);
        },
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('probe')), findsOneWidget);
    expect(fadeOf(tester), 1);
    expect(seen, isNotNull);
    expect(seen!.value, isTrue);
  });
}

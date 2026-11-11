/// The scroll keys of a surface routed to its viewports.
///
/// **Seam:** [ViewportScrollRouter] over a primary and a pointer
/// [ViewportScrollKeys] viewport and a text field, driven by key presses
/// and a mouse; observed through the scroll requests each viewport makes and
/// the field's caret and focus.
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viewport_scroll/viewport_scroll.dart';

void main() {
  late List<String> calls;
  late TextEditingController text;
  late FocusNode field;
  late FocusNode other;
  late ValueNotifier<int> refocus;

  setUp(() {
    calls = [];
    text = TextEditingController();
    field = FocusNode();
    other = FocusNode();
    refocus = ValueNotifier(0);
    addTearDown(refocus.dispose);
    addTearDown(text.dispose);
    addTearDown(field.dispose);
    addTearDown(other.dispose);
  });

  Widget viewport(String name, ViewportScrollRole role, {Key? key}) => SizedBox(
    key: key,
    width: 200,
    height: 200,
    child: ViewportScrollKeys(
      role: role,
      onScrollBy: (pixels) => calls.add('$name $pixels'),
      onScrollToStart: () => calls.add('$name start'),
      onScrollToEnd: () => calls.add('$name end'),
      pageExtent: 100,
      child: const SizedBox.expand(),
    ),
  );

  Future<void> pump(WidgetTester tester, {bool holdsFocus = false}) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => ViewportScrollRouter(
          holdsFocus: holdsFocus,
          focusFallback: holdsFocus ? () => field : null,
          refocusOn: refocus,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              viewport('chat', ViewportScrollRole.primary),
              viewport(
                'panel',
                ViewportScrollRole.pointer,
                key: const Key('panel'),
              ),
              SizedBox(
                width: 200,
                height: 20,
                child: EditableText(
                  controller: text,
                  focusNode: field,
                  style: const TextStyle(),
                  cursorColor: const Color(0xFF000000),
                  backgroundCursorColor: const Color(0xFF000000),
                ),
              ),
              Focus(focusNode: other, child: const SizedBox(height: 10)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key, platform: 'macos');
    await tester.pump();
  }

  testWidgets('with no viewport focused, the keys go to the primary one', (
    tester,
  ) async {
    await pump(tester);
    other.requestFocus();
    await tester.pump();

    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.pageUp);
    await press(tester, LogicalKeyboardKey.end);

    expect(calls, ['chat 60.0', 'chat -100.0', 'chat end']);
  });

  testWidgets('the pointer viewport under the mouse takes them', (
    tester,
  ) async {
    await pump(tester);
    other.requestFocus();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('panel'))));
    await tester.pump();

    await press(tester, LogicalKeyboardKey.arrowDown);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(calls, ['panel 60.0', 'chat 60.0']);
  });

  testWidgets('an empty field hands every scroll key on', (tester) async {
    await pump(tester);
    field.requestFocus();
    await tester.pump();

    for (final key in [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
    ]) {
      await press(tester, key);
    }

    expect(calls, hasLength(6));
    expect(field.hasFocus, isTrue);
  });

  testWidgets('a field with text keeps the arrows that move its caret and '
      'Home / End; it hands on the arrows at its ends and the page keys', (
    tester,
  ) async {
    await pump(tester);
    field.requestFocus();
    text.value = const TextEditingValue(
      text: 'abc',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tester.pump();

    await press(tester, LogicalKeyboardKey.home);
    await press(tester, LogicalKeyboardKey.end);
    expect(calls, isEmpty);

    text.selection = const TextSelection.collapsed(offset: 0);
    await press(tester, LogicalKeyboardKey.arrowUp);
    text.selection = const TextSelection.collapsed(offset: 3);
    await press(tester, LogicalKeyboardKey.arrowDown);
    text.selection = const TextSelection.collapsed(offset: 1);
    await press(tester, LogicalKeyboardKey.pageDown);

    expect(calls, ['chat -60.0', 'chat 60.0', 'chat 100.0']);
  });

  testWidgets('holding the focus: the fallback has it when the surface '
      'shows, the router when the field is left, the fallback again when '
      'asked', (tester) async {
    await pump(tester, holdsFocus: true);
    await tester.pump();
    expect(field.hasFocus, isTrue, reason: 'the fallback from the start');

    field.unfocus();
    await tester.pump();
    await tester.pump();
    expect(field.hasFocus, isFalse);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'ViewportScrollRouter',
    );
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(calls, ['chat -60.0'], reason: 'the keys keep an owner');

    refocus.value++;
    await tester.pump();
    await tester.pump();
    expect(field.hasFocus, isTrue);
  });
}

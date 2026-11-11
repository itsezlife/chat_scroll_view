import 'package:chat_composer/chat_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

/// What the focused field sends the platform's text input while nobody types.
///
/// The field keeps its input connection the whole time it has focus, panel
/// open or not. Over that connection it reports what the platform positions
/// the IME by: its size and transform, and its caret and marked-text rects. A
/// report goes out only when its value changed, so a frame in which the field
/// stays put sends nothing, however much else on screen moves.
void main() {
  late ComposerController controller;
  late ValueNotifier<double> lift;
  late ScrollController chat;

  setUp(() {
    controller = ComposerController();
    lift = ValueNotifier<double>(0);
    chat = ScrollController();
  });
  tearDown(() {
    controller.dispose();
    lift.dispose();
    chat.dispose();
  });

  // A scrolling list behind a composer the test can raise by [lift], the way a
  // docked panel raises it.
  Future<void> pumpFocused(WidgetTester tester) async {
    await tester.pumpWidget(
      composerHarness(
        ValueListenableBuilder<double>(
          valueListenable: lift,
          builder: (context, value, child) => Padding(
            padding: EdgeInsets.only(bottom: value),
            child: child,
          ),
          child: ComposerView(
            controller: controller,
            spec: ComposerSpec(),
            autofocus: false,
          ),
        ),
        behind: ListView.builder(
          controller: chat,
          itemExtent: 48,
          itemCount: 200,
          itemBuilder: (context, index) => Text('message $index'),
        ),
      ),
    );
    controller.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.hasFocus, isTrue);
    tester.testTextInput.log.clear();
  }

  List<String> sent(WidgetTester tester) =>
      tester.testTextInput.log.map((call) => call.method).toList();

  testWidgets(
    'frames in which nothing moves send nothing',
    (tester) async {
      await pumpFocused(tester);

      for (var i = 0; i < 30; i++) {
        tester.binding.scheduleFrame();
        await tester.pump(const Duration(milliseconds: 8));
      }

      expect(sent(tester), isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'the chat scrolling behind the composer sends nothing',
    (tester) async {
      await pumpFocused(tester);

      for (var i = 0; i < 30; i++) {
        chat.jumpTo(chat.offset + 37.3);
        await tester.pump(const Duration(milliseconds: 8));
      }

      expect(chat.offset, greaterThan(1000));
      expect(sent(tester), isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a composer raised by whole pixels sends its transform once a frame',
    (tester) async {
      await pumpFocused(tester);

      for (var i = 0; i < 10; i++) {
        lift.value += 10;
        await tester.pump(const Duration(milliseconds: 8));
      }

      expect(sent(tester), [
        for (var i = 0; i < 10; i++) 'TextInput.setEditableSizeAndTransform',
      ]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a composer raised by fractions of a pixel also re-sends its caret and '
    'marked-text rects, and nothing else',
    (tester) async {
      await pumpFocused(tester);

      for (var i = 0; i < 10; i++) {
        lift.value += 10.37;
        await tester.pump(const Duration(milliseconds: 8));
      }

      // The rects are local to the field, but each is snapped to the
      // physical pixel grid at the field's place on screen, so a move by a
      // fraction of a pixel shifts them by that fraction. The text, the
      // selection and the connection stay as they were.
      expect(sent(tester).toSet(), {
        'TextInput.setEditableSizeAndTransform',
        'TextInput.setMarkedTextRect',
        'TextInput.setCaretRect',
      });
      expect(sent(tester), hasLength(lessThanOrEqualTo(3 * 10)));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

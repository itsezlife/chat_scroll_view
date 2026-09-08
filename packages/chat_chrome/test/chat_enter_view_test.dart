import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode(debugLabel: 'ChatEnterViewTest');
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('default path mounts the stock text field', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChatEnterView(
          controller: controller,
          focusNode: focusNode,
          onSend: () {},
          onEmojiPressed: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('inputBuilder replaces the stock row', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChatEnterView(
          controller: controller,
          focusNode: focusNode,
          onSend: () {},
          onEmojiPressed: () {},
          inputBuilder: (context, field) => const Text(
            key: Key('custom-enter-row'),
            'custom row',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('custom-enter-row')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'inputBuilder field handle uses the same controller and focusNode',
    (tester) async {
      ChatEnterFieldHandle? seen;

      await tester.pumpWidget(
        _harness(
          ChatEnterView(
            controller: controller,
            focusNode: focusNode,
            onSend: () {},
            onEmojiPressed: () {},
            inputBuilder: (context, field) {
              seen = field;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      expect(seen, isNotNull);
      expect(identical(seen!.controller, controller), isTrue);
      expect(identical(seen!.focusNode, focusNode), isTrue);
    },
  );
}

Widget _harness(Widget child) {
  return MaterialApp(
    home: ChatChromeTheme(
      colors: const ChatChromeColors(),
      child: Scaffold(body: child),
    ),
  );
}

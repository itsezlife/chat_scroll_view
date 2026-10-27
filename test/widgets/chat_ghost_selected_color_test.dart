import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const normalColor = Color(0xFF212121);
  const selectedColor = Color(0xFF2B5278);

  RenderChatMessageChangeTransition box(WidgetTester tester) =>
      tester.renderObject(find.byType(ChatMessageChangeTransition));

  Future<void> pumpRow(
    WidgetTester tester,
    ChatSelectionController controller, {
    int id = 10,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: ChatScrollTheme(
            data: const ChatScrollThemeData(),
            child: SelectableMessage(
              id: id,
              allowed: ChatSelectionAllowed.all,
              controller: controller,
              child: ChatMessageChangeTransition(
                contentIdentity: 'body-$id',
                outgoing: false,
                color: normalColor,
                selectedColor: selectedColor,
                borderRadius: BorderRadius.circular(16),
                content: Text('body-$id'),
                metaBuilder: (context, opacity) => const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'desktop: clear leaves selectProgress frozen but bubble color must snap off',
    (tester) async {
      final controller = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(controller.dispose);

      await pumpRow(tester, controller);
      expect(box(tester).color, normalColor);

      controller.startSelection(10);
      await tester.pumpAndSettle();
      expect(controller.isSelected(10), isTrue);
      expect(box(tester).color, selectedColor);

      controller.clear();
      await tester.pump();
      expect(controller.isSelected(10), isFalse);
      expect(controller.isSelectionMode, isFalse);
      expect(
        box(tester).color,
        normalColor,
        reason:
            'ghost selectedColor: membership empty but bubble still selected paint',
      );

      await tester.pumpAndSettle();
      expect(box(tester).color, normalColor);
    },
  );

  testWidgets('desktop: last-item toggle must not leave ghost selectedColor', (
    tester,
  ) async {
    final controller = ChatSelectionController(
      policy: const ChatSelectionPolicy.desktop(),
    );
    addTearDown(controller.dispose);

    await pumpRow(tester, controller);
    controller.startSelection(10);
    await tester.pumpAndSettle();
    expect(box(tester).color, selectedColor);

    controller.toggle(10);
    await tester.pump();
    expect(controller.isSelected(10), isFalse);
    expect(
      box(tester).color,
      normalColor,
      reason: 'last toggle must clear bubble selectedColor immediately',
    );
  });

  testWidgets(
    'desktop: clearDrag mid mode-enter must not leave ghost selectedColor',
    (tester) async {
      final controller = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(controller.dispose);

      await pumpRow(tester, controller);
      controller.updateDragSelection({10});
      await tester.pump(); // mid mode-enter — do not settle
      expect(box(tester).color, selectedColor);

      controller.clearDragSelection();
      await tester.pump();
      expect(controller.isSelected(10), isFalse);
      expect(controller.isSelectionMode, isFalse);

      final scope = tester
          .widget<ChatSelectionStateScope>(find.byType(ChatSelectionStateScope))
          .state;
      expect(scope.isSelected, isFalse);

      expect(
        box(tester).color,
        normalColor,
        reason:
            'clearDrag during mode-enter must not leave ghost selectedColor',
      );

      await tester.pumpAndSettle();
      expect(box(tester).color, normalColor);
    },
  );

  testWidgets('desktop: clearDrag after settled mode drops selectedColor', (
    tester,
  ) async {
    final controller = ChatSelectionController(
      policy: const ChatSelectionPolicy.desktop(),
    );
    addTearDown(controller.dispose);

    await pumpRow(tester, controller);
    controller.updateDragSelection({10});
    await tester.pumpAndSettle();
    controller.clearDragSelection();
    await tester.pump();
    expect(controller.isSelected(10), isFalse);
    expect(box(tester).color, normalColor);
  });

  testWidgets(
    'desktop: recycle SelectableMessage id after frozen selectProgress',
    (tester) async {
      final controller = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(controller.dispose);

      await pumpRow(tester, controller, id: 10);
      controller.startSelection(10);
      await tester.pumpAndSettle();
      controller.clear();
      await tester.pumpAndSettle();

      await pumpRow(tester, controller, id: 11);
      await tester.pumpAndSettle();
      expect(controller.isSelected(11), isFalse);
      expect(
        box(tester).color,
        normalColor,
        reason: 'recycled row must not keep prior selectedColor',
      );
    },
  );
}

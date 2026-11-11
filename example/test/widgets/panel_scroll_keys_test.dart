/// On a desktop the scroll keys reach the panel's catalogue while the mouse
/// is over it, not the chat beside it; a field the user types in keeps them.
///
/// **Seam:** the chat's input set with the desktop policy on macOS, beside
/// the chat's own keyboard shortcuts (`ChatKeyboardShortcuts` over a chat
/// stand-in, as the screen mounts them), driven by one mouse and the keys;
/// observed through the catalogue's offset and the chat controller's scroll
/// events.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_presentation/panel_presentation.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

void main() {
  testWidgets('the arrows, the page keys and Home / End scroll the panel '
      'under the mouse, not the chat; the composer keeps its keys', (
    tester,
  ) async {
    final services = (await tester.runAsync(createTestServices))!;
    addTearDown(services.dispose);
    final chat = ChatScrollController();
    addTearDown(chat.dispose);
    final chatScrolls = <double>[];
    chat.addScrollListener((event) {
      if (event case ChatProgrammaticScroll(:final delta)) {
        chatScrolls.add(delta);
      }
    });
    final rig = await InputRig.pump(
      tester,
      services: services,
      policy: const PanelPresentationPolicy$Desktop(),
      size: const Size(1000, 800),
      chat: ChatKeyboardShortcuts(
        controller: chat,
        reverse: true,
        preserveExternalFocus: true,
        child: const ColoredBox(
          key: ValueKey('chat'),
          color: Color(0xFF203040),
          child: SizedBox.expand(),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(4, 4));
    addTearDown(mouse.removePointer);

    // The chat holds the keys (as after a message selection gave them to
    // it): its own focus node has the focus.
    tester
        .widget<Focus>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Focus &&
                widget.focusNode?.debugLabel == 'ChatKeyboardShortcuts',
          ),
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(chatScrolls, isNotEmpty, reason: 'the chat has the keys');
    chatScrolls.clear();

    // The panel, opened by hovering its button.
    await mouse.moveTo(tester.getCenter(rig.action(ChatComposerActions.panel)));
    await rig.settle(tester);
    expect(rig.set.presentation.state.value, isA<PanelVisibility$Shown>());
    final viewport = find.byType(PanelCatalogViewport);
    PanelCatalogController catalog() =>
        tester.widget<PanelCatalogViewport>(viewport).controller;
    for (var i = 0; i < 100 && catalog().maxScrollExtent < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(catalog().maxScrollExtent, greaterThan(200));

    await mouse.moveTo(tester.getCenter(viewport));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(catalog().offset, 60);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(catalog().offset, greaterThan(60));
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(catalog().offset, catalog().maxScrollExtent);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(catalog().offset, 0);
    expect(chatScrolls, isEmpty);
    expect(catalog().focusedLeaf, isNull, reason: 'no cell is focused');

    // Off the panel, the keys go back to the chat.
    await mouse.moveTo(
      tester.getTopLeft(find.byKey(const ValueKey('chat'))) +
          const Offset(100, 100),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(chatScrolls, isNotEmpty);
    await mouse.moveTo(tester.getCenter(viewport));
    await tester.pump();

    // With the caret inside a text in the composer, the field keeps the
    // arrows it moves the caret with; the page keys still reach the panel.
    rig.set.composer.requestFocus();
    await tester.pump();
    rig.set.composer
      ..insertText('ab')
      ..select(const TextSelection.collapsed(offset: 1));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(catalog().offset, 0);
    expect(rig.set.composer.selection.baseOffset, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(catalog().offset, greaterThan(0));
    expect(rig.set.composer.hasFocus, isTrue);
  }, variant: _macOS);
}

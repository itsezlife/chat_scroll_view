/// Who owns the text, the keyboard and back while the attach sheet is up
/// over the chat, and after it closes.
///
/// **Seam:** [ChatAttach.open] over the app's test services, its keyboard
/// hand-off given as callbacks standing in for the chat's input set (a
/// claim stands in for the panel's); back is the native pre-IME back.
library;

import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:bulletins/bulletins.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatPreImeBackBinding, ChatPreImeBackClaim;
import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_attach.dart';
import 'package:content_model/content_model.dart' as content;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_services.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The chat under the sheet: its composer, a panel that stands in for the
/// keyboard when asked (its claim under the sheet's), the sent messages.
final class _Chat {
  _Chat(this.services);

  final AppServices services;
  final composer = ComposerController();
  final sent = <String>[];
  ChatPreImeBackClaim? panelClaim;
  int panelBacks = 0;
  int yields = 0;
  int returns = 0;
  bool keyboardUp = true;
  final owned = <bool>[];
  late BuildContext home;
  late final ChatAttach attach;

  Future<void> pump(WidgetTester tester) async {
    final bulletins = BulletinController(
      policy: const BulletinPolicy.android(),
    );
    addTearDown(bulletins.dispose);
    addTearDown(composer.dispose);
    attach = ChatAttach(
      services: services,
      composer: composer,
      bulletins: bulletins,
      send: (text) async => sent.add(text),
      yieldKeyboard: () {
        yields++;
        // As the chat answers: only a raised keyboard gives its place.
        if (!keyboardUp) return false;
        panelClaim = ChatPreImeBackClaim.push(() async {
          panelBacks++;
          return true;
        });
        return true;
      },
      returnKeyboard: () => returns++,
      keyboardUp: () => keyboardUp,
      ownKeyboard: owned.add,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppChrome(services: services, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              home = context;
              return Center(
                child: SizedBox(
                  width: 300,
                  child: ComposerView(
                    controller: composer,
                    autofocus: false,
                    spec: ComposerSpec(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    attach.open(home).ignore();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);
  }
}

void main() {
  late _Chat chat;

  Future<_Chat> start(WidgetTester tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    // The device's plugins answer nothing here.
    for (final name in [
      'dev.mpx.device_signals',
      'dev.mpx.library',
      'dev.mpx.library/events',
    ]) {
      final channel = MethodChannel(name);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
    addTearDown(ChatPreImeBackBinding.debugReset);
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(createTestServices))!;
    addTearDown(services.dispose);
    chat = _Chat(services);
    await chat.pump(tester);
    return chat;
  }

  // The caption controller of the open sheet.
  ComposerController caption(WidgetTester tester) => tester
      .widget<ComposerView>(find.byKey(const ValueKey('attach-caption')))
      .controller;

  testWidgets("one text: the chat's field keeps its text while the sheet is "
      'up, the caption shows it, and an unchanged cancel leaves the field '
      'as it was', (tester) async {
    final chat = await start(tester);
    chat.composer.restore(const content.RichText.plain('hello'));
    await chat.open(tester);
    expect(chat.composer.richText.plain, 'hello', reason: 'not cleared');

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(AttachSheet), findsNothing);
    expect(chat.composer.richText.plain, 'hello');
  });

  testWidgets('the caption edited becomes the chat text after a cancel', (
    tester,
  ) async {
    final chat = await start(tester);
    chat.composer.restore(const content.RichText.plain('hello'));
    await chat.open(tester);
    // The caption shows only with a selection.
    final selection = tester
        .widget<AttachSheet>(find.byType(AttachSheet))
        .selection;
    selection.toggle(AttachItems.file('f'));
    await _settle(tester);
    final sheet = AttachSheetController.of(
      tester.element(find.byType(AttachCaptionBar).first),
    );
    expect(caption(tester).richText.plain, 'hello', reason: 'the same text');
    caption(tester).restore(const content.RichText.plain('hello there'));
    selection.clear();
    await _settle(tester);
    // Its future ends with the close's motion, which only pumping runs.
    sheet.close(const AttachOutcome.cancelled()).ignore();
    await _settle(tester);
    expect(chat.composer.richText.plain, 'hello there');
  });

  testWidgets("the keyboard's place goes to the chat's panel as the sheet "
      'opens; back takes the sheet first, then the panel; after the sheet '
      'the keyboard comes back in the panel place', (tester) async {
    final chat = await start(tester);
    chat.composer.focusNode.requestFocus();
    await tester.pump();
    await chat.open(tester);
    expect(chat.yields, 1);
    expect(chat.composer.focusNode.hasFocus, isFalse, reason: 'the sheet owns');

    expect(await ChatPreImeBackBinding.handleNativeBack(), isTrue);
    await _settle(tester);
    expect(find.byType(AttachSheet), findsNothing);
    expect(chat.panelBacks, 0, reason: 'the sheet took back first');
    expect(chat.returns, 1, reason: 'the keyboard back in the panel place');

    expect(await ChatPreImeBackBinding.handleNativeBack(), isTrue);
    expect(chat.panelBacks, 1);
    chat.panelClaim?.pop();
  });

  testWidgets('no keyboard before the sheet, no keyboard after: a field '
      'focused with its keyboard down is not given the keyboard on close; '
      'the sheet owns the keyboard while it is up', (tester) async {
    final chat = await start(tester);
    chat.keyboardUp = false;
    chat.composer.focusNode.requestFocus();
    await tester.pump();
    await chat.open(tester);
    expect(chat.owned, [true]);
    expect(chat.yields, 1, reason: 'asked; the chat answers as it is');

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(AttachSheet), findsNothing);
    expect(chat.owned, [true, false]);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(chat.returns, 0);
    expect(chat.composer.focusNode.hasFocus, isFalse, reason: 'no keyboard');
  });
}

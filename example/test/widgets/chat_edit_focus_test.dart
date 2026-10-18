/// Starting an edit hands the composer the caret, and on a touch platform the
/// soft keyboard.
///
/// **Seam:** the chat's input set (with its bottom chrome, composer included)
/// against the platform's text input channel: the type the field attached to
/// the platform with, and whether the platform was told to show its keyboard.
/// Reference: Android `ChatActivityEnterView.setEditingMessageObject` (focus,
/// caret at the end, `openKeyboard`), iOS `setupEditMessage` (input mode
/// text, `ensureInputViewFocused`), Desktop `HistoryWidget::editMessage`
/// (cursor at the end, `setInnerFocus`).
library;

import 'package:chat_scroll_view_example/src/features/chat/data/chat_draft_store.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

const _mobile = PanelPresentationPolicy$Mobile();
const _desktop = PanelPresentationPolicy$Desktop();

final _touch = TargetPlatformVariant.mobile();
final _pointer = TargetPlatformVariant.desktop();

// The input type the platform's text input was last attached with: the type
// of the latest `TextInput.setClient` (a configuration update does not count,
// because the platform keeps the type a client attached with). Null before
// any attach.
String? _attachedType(WidgetTester tester) {
  final attaches = tester.testTextInput.log.where(
    (call) => call.method == 'TextInput.setClient',
  );
  if (attaches.isEmpty) return null;
  final config =
      (attaches.last.arguments as List<Object?>)[1]! as Map<String, dynamic>;
  final type = config['inputType']! as Map<String, dynamic>;
  return '${type['name']}';
}

/// Whether the platform's soft keyboard is up: the field attached with a
/// keyboard type and the platform was asked to show it. `isVisible` alone is
/// not enough, because the field asks even when it attached with no keyboard
/// type, which the platform answers with nothing.
bool _keyboardUp(WidgetTester tester) =>
    tester.testTextInput.isVisible &&
    (_attachedType(tester)?.startsWith('TextInputType.multiline') ?? false);

Future<InputRig> _pump(
  WidgetTester tester, {
  required PanelPresentationPolicy policy,
}) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  final rig = await InputRig.pump(tester, services: services, policy: policy);
  await rig.settle(tester);
  return rig;
}

/// Lets the keyboard request, which is answered after a frame and may take a
/// second to re-attach, run its course.
Future<void> _settle(WidgetTester tester, InputRig rig) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
  await rig.settle(tester);
}

void main() {
  group('on a touch platform', () {
    testWidgets('opening the chat takes focus but keeps the keyboard down', (
      tester,
    ) async {
      final rig = await _pump(tester, policy: _mobile);

      expect(rig.set.composer.hasFocus, isTrue);
      expect(_attachedType(tester), 'TextInputType.none');
      expect(_keyboardUp(tester), isFalse);
    }, variant: _touch);

    testWidgets(
      'Edit from the message menu focuses the composer, puts the caret at the '
      'end of the loaded text and raises the keyboard',
      (tester) async {
        final rig = await _pump(tester, policy: _mobile);

        rig.set.beginEdit(7, 'make it **loud**');
        await _settle(tester, rig);

        expect(rig.set.composer.hasFocus, isTrue);
        expect(
          rig.set.composer.text.selection,
          const TextSelection.collapsed(offset: 'make it loud'.length),
        );
        expect(_keyboardUp(tester), isTrue);
      },
      variant: _touch,
    );

    testWidgets(
      'Edit from the selection bar, which unmounts the composer meanwhile, '
      'raises the keyboard once the composer is back',
      (tester) async {
        final rig = await _pump(tester, policy: _mobile);
        rig.selection.toggle(7);
        await tester.pump();
        expect(rig.set.composer.hasFocus, isFalse);

        // What the screen does: the selection clears, then the edit begins,
        // in one go, before the composer has been built again.
        rig.selection.clear();
        rig.set.beginEdit(7, 'hello');
        await _settle(tester, rig);

        expect(rig.set.editing.value?.id, 7);
        expect(rig.set.composer.hasFocus, isTrue);
        expect(
          rig.set.composer.text.selection,
          const TextSelection.collapsed(offset: 5),
        );
        expect(_keyboardUp(tester), isTrue);
      },
      variant: _touch,
    );

    testWidgets(
      'Edit while the panel is open hands the slot over to the keyboard',
      (tester) async {
        final rig = await _pump(tester, policy: _mobile);
        await rig.tapAction(tester, ChatComposerActions.panel);
        await rig.settle(tester);
        expect(
          rig.set.presentation.state.value,
          isA<PanelVisibility$Shown>(),
          reason: 'the panel is open first',
        );
        expect(_keyboardUp(tester), isFalse);

        rig.set.beginEdit(7, 'hello');
        await _settle(tester, rig);

        expect(rig.set.composer.hasFocus, isTrue);
        expect(_keyboardUp(tester), isTrue);
        // The panel lets go once the platform's keyboard has risen to its
        // place.
        rig.keyboard.rest(rig.set.presentation.occupancy.value.bottom);
        await rig.settle(tester);
        expect(rig.set.presentation.state.value, isA<PanelVisibility$Hidden>());
        expect(
          rig.set.composer.text.selection,
          const TextSelection.collapsed(offset: 5),
        );
      },
      variant: _touch,
    );

    testWidgets(
      'a draft that restores into edit mode does not take focus or raise the '
      'keyboard',
      (tester) async {
        final storage = FakeKeyValueStore();
        await ChatDraftStore(
          storage,
        ).write('chat', const ChatDraft(markdown: 'hello', editing: 7));
        final services = (await tester.runAsync(
          () => createTestServices(storage: storage),
        ))!;
        addTearDown(services.dispose);
        final rig = await InputRig.pump(
          tester,
          services: services,
          policy: _mobile,
        );
        rig.set.composer.unfocus();
        await tester.pump();

        await rig.set.bindDrafts(services.drafts, 'chat');
        await _settle(tester, rig);

        expect(rig.set.editing.value?.id, 7);
        expect(rig.set.composer.text.text, 'hello');
        expect(rig.set.composer.hasFocus, isFalse);
        expect(_keyboardUp(tester), isFalse);
      },
      variant: _touch,
    );
  });

  group('on a pointer platform', () {
    testWidgets('Edit focuses the composer and puts the caret at the end', (
      tester,
    ) async {
      final rig = await _pump(tester, policy: _desktop);
      rig.set.composer.unfocus();
      await tester.pump();
      expect(rig.set.composer.hasFocus, isFalse);

      rig.set.beginEdit(7, 'make it **loud**');
      await _settle(tester, rig);

      expect(rig.set.composer.hasFocus, isTrue);
      expect(
        rig.set.composer.text.selection,
        const TextSelection.collapsed(offset: 'make it loud'.length),
      );
    }, variant: _pointer);

    testWidgets(
      'Edit from the selection bar focuses the composer once it is back',
      (tester) async {
        final rig = await _pump(tester, policy: _desktop);
        rig.selection.toggle(7);
        await tester.pump();
        expect(rig.set.composer.hasFocus, isFalse);

        rig.selection.clear();
        rig.set.beginEdit(7, 'hello');
        await _settle(tester, rig);

        expect(rig.set.composer.hasFocus, isTrue);
        expect(
          rig.set.composer.text.selection,
          const TextSelection.collapsed(offset: 5),
        );
      },
      variant: _pointer,
    );

    testWidgets(
      'a draft that restores into edit mode does not take focus',
      (tester) async {
        final storage = FakeKeyValueStore();
        await ChatDraftStore(
          storage,
        ).write('chat', const ChatDraft(markdown: 'hello', editing: 7));
        final services = (await tester.runAsync(
          () => createTestServices(storage: storage),
        ))!;
        addTearDown(services.dispose);
        final rig = await InputRig.pump(
          tester,
          services: services,
          policy: _desktop,
        );
        rig.set.composer.unfocus();
        await tester.pump();

        await rig.set.bindDrafts(services.drafts, 'chat');
        await _settle(tester, rig);

        expect(rig.set.editing.value?.id, 7);
        expect(rig.set.composer.hasFocus, isFalse);
      },
      variant: _pointer,
    );
  });
}

import 'dart:async';

import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

/// Telegram Desktop's key set: key, whether Shift joins the modifier, and the
/// Intent it binds.
final _bindings = <(LogicalKeyboardKey, bool, Intent)>[
  (LogicalKeyboardKey.keyB, false, const ToggleStyleIntent(EntityStyle.bold)),
  (LogicalKeyboardKey.keyI, false, const ToggleStyleIntent(EntityStyle.italic)),
  (
    LogicalKeyboardKey.keyU,
    false,
    const ToggleStyleIntent(EntityStyle.underline),
  ),
  (LogicalKeyboardKey.keyX, true, const ToggleStyleIntent(EntityStyle.strike)),
  (LogicalKeyboardKey.keyM, true, const ToggleStyleIntent(EntityStyle.code)),
  (LogicalKeyboardKey.keyP, true, const ToggleStyleIntent(EntityStyle.spoiler)),
  (LogicalKeyboardKey.keyK, false, const ApplyLinkIntent()),
  (LogicalKeyboardKey.period, true, const ToggleStyleIntent(EntityStyle.quote)),
  (
    LogicalKeyboardKey.digit7,
    true,
    const ToggleListIntent(EntityListKind.ordered),
  ),
  (
    LogicalKeyboardKey.digit8,
    true,
    const ToggleListIntent(EntityListKind.bullet),
  ),
  (LogicalKeyboardKey.keyN, true, const ClearFormattingIntent()),
];

String _describe(Intent intent) => switch (intent) {
  ToggleStyleIntent(:final style) => 'style ${style.name}',
  ToggleListIntent(:final listKind) => 'list ${listKind.name}',
  _ => intent.runtimeType.toString(),
};

void main() {
  group('formatting bindings', () {
    for (final policy in <String, ComposerShortcutPolicy>{
      'desktop': const ComposerShortcutPolicy.desktop(),
      'desktop in a browser': const ComposerShortcutPolicy.desktop(
        inBrowser: true,
      ),
      'mobile': const ComposerShortcutPolicy.mobile(),
    }.entries) {
      for (final (key, shift, intent) in _bindings) {
        for (final modifier in ['control', 'meta']) {
          testWidgets(
            '${policy.key}: $modifier${shift ? '+shift' : ''}+${key.keyLabel} '
            'is ${_describe(intent)}',
            (tester) async {
              final seen = <Intent>[];
              await tester.pumpWidget(
                MaterialApp(
                  home: Shortcuts(
                    shortcuts: policy.value.shortcuts,
                    child: Actions(
                      actions: {
                        for (final type in [
                          ToggleStyleIntent,
                          ToggleListIntent,
                          ApplyLinkIntent,
                          ClearFormattingIntent,
                          ToggleCodeBlockIntent,
                        ])
                          type: CallbackAction<Intent>(
                            onInvoke: (intent) {
                              seen.add(intent);
                              return null;
                            },
                          ),
                      },
                      child: const Focus(
                        autofocus: true,
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              );
              final modifierKey = modifier == 'control'
                  ? LogicalKeyboardKey.controlLeft
                  : LogicalKeyboardKey.metaLeft;

              await tester.sendKeyDownEvent(modifierKey);
              if (shift)
                await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
              await tester.sendKeyEvent(key);
              if (shift)
                await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
              await tester.sendKeyUpEvent(modifierKey);

              expect(seen, hasLength(1));
              expect(seen.single.runtimeType, intent.runtimeType);
              switch (intent) {
                case ToggleStyleIntent(:final style):
                  expect((seen.single as ToggleStyleIntent).style, style);
                case ToggleListIntent(:final listKind):
                  expect((seen.single as ToggleListIntent).listKind, listKind);
                default:
              }
            },
          );
        }
      }
    }

    test('the code block has no default key; the reference has none', () {
      final intents = const ComposerShortcutPolicy.desktop().shortcuts.values;

      expect(intents.whereType<ToggleCodeBlockIntent>(), isEmpty);
    });

    test('the existing keys are kept', () {
      final shortcuts = const ComposerShortcutPolicy.desktop().shortcuts;

      expect(
        shortcuts[const SingleActivator(
          LogicalKeyboardKey.keyV,
          control: true,
          shift: true,
        )],
        isA<PastePlainTextIntent>(),
      );
      expect(
        shortcuts[const SingleActivator(LogicalKeyboardKey.enter)],
        isA<SubmitComposerIntent>(),
      );
      expect(
        shortcuts[const SingleActivator(LogicalKeyboardKey.escape)],
        isA<DismissComposerHeaderIntent>(),
      );
    });
  });

  group('ComposerView formatting shortcuts', () {
    late ComposerController controller;

    setUp(() => controller = ComposerController());
    tearDown(() => controller.dispose());

    Future<void> show(
      WidgetTester tester, {
      Map<ShortcutActivator, Intent>? shortcuts,
      ComposerLinkPrompt? linkPrompt,
    }) async {
      await tester.pumpWidget(
        composerHarness(
          ComposerView(
            controller: controller,
            spec: ComposerSpec(linkPrompt: linkPrompt),
            shortcuts:
                shortcuts ?? const ComposerShortcutPolicy.desktop().shortcuts,
          ),
        ),
      );
      controller.requestFocus();
      await tester.pump();
    }

    void load(RichText text, int from, [int? to]) => controller.text.restore(
      text,
      selection: TextSelection(baseOffset: from, extentOffset: to ?? from),
    );

    Future<void> chord(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      bool shift = false,
      LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
    }) async {
      await tester.sendKeyDownEvent(modifier);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }

    testWidgets('Ctrl+B bolds the selection and Ctrl+B again unbolds it', (
      tester,
    ) async {
      await show(tester);
      load(const RichText.plain('hello world'), 0, 5);

      await chord(tester, LogicalKeyboardKey.keyB);

      expect(
        controller.richText,
        RichText('hello world', const [Entity(0, 5, EntityKind.bold)]),
      );

      await chord(tester, LogicalKeyboardKey.keyB);

      expect(controller.richText, const RichText.plain('hello world'));
    });

    testWidgets('Cmd+B does the same', (tester) async {
      await show(tester);
      load(const RichText.plain('hello world'), 0, 5);

      await chord(
        tester,
        LogicalKeyboardKey.keyB,
        modifier: LogicalKeyboardKey.metaLeft,
      );

      expect(
        controller.richText,
        RichText('hello world', const [Entity(0, 5, EntityKind.bold)]),
      );
    });

    testWidgets('Ctrl+Shift+M over bold text makes it code, not bold', (
      tester,
    ) async {
      await show(tester);
      load(
        RichText('hello world', const [Entity(0, 5, EntityKind.bold)]),
        0,
        5,
      );

      await chord(tester, LogicalKeyboardKey.keyM, shift: true);

      expect(
        controller.richText,
        RichText('hello world', const [Entity(0, 5, EntityKind.code)]),
      );
    });

    testWidgets('with a caret Ctrl+B does nothing', (tester) async {
      await show(tester);
      load(const RichText.plain('hello world'), 3);

      await chord(tester, LogicalKeyboardKey.keyB);

      expect(controller.richText, const RichText.plain('hello world'));
    });

    testWidgets('with a caret Ctrl+Shift+. quotes the caret\'s line', (
      tester,
    ) async {
      await show(tester);
      load(const RichText.plain('one\ntwo\nthree'), 5);

      await chord(tester, LogicalKeyboardKey.period, shift: true);

      expect(
        controller.richText,
        RichText('one\ntwo\nthree', const [Entity(4, 3, EntityKind.quote)]),
      );
    });

    testWidgets('Ctrl+Shift+N clears the formatting of the selection', (
      tester,
    ) async {
      await show(tester);
      load(
        RichText('hello world', const [Entity(0, 11, EntityKind.bold)]),
        0,
        11,
      );

      await chord(tester, LogicalKeyboardKey.keyN, shift: true);

      expect(controller.richText, const RichText.plain('hello world'));
    });

    testWidgets('ToggleCodeBlockIntent toggles a code block on the lines', (
      tester,
    ) async {
      await show(
        tester,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyE, control: true):
              ToggleCodeBlockIntent(),
        },
      );
      load(const RichText.plain('one\ntwo'), 5);

      await chord(tester, LogicalKeyboardKey.keyE);

      expect(
        controller.richText,
        RichText('one\ntwo', const [Entity(4, 3, EntityKind.codeBlock())]),
      );

      await chord(tester, LogicalKeyboardKey.keyE);

      expect(controller.richText, const RichText.plain('one\ntwo'));
    });

    group('link', () {
      testWidgets('Ctrl+K asks the prompt and links the selection to its URL', (
        tester,
      ) async {
        var asked = 0;
        await show(
          tester,
          linkPrompt: (context, _) async {
            asked++;
            return 'https://example.com';
          },
        );
        load(const RichText.plain('hello world'), 0, 5);

        await chord(tester, LogicalKeyboardKey.keyK);
        await tester.pump();

        expect(asked, 1);
        expect(
          controller.richText,
          RichText('hello world', const [
            Entity(0, 5, EntityKind.link('https://example.com')),
          ]),
        );
      });

      testWidgets('a cancelled prompt changes nothing', (tester) async {
        await show(tester, linkPrompt: (context, _) async => null);
        load(const RichText.plain('hello world'), 0, 5);

        await chord(tester, LogicalKeyboardKey.keyK);
        await tester.pump();

        expect(controller.richText, const RichText.plain('hello world'));
      });

      testWidgets('at a caret the URL goes in as linked text', (tester) async {
        await show(tester, linkPrompt: (context, _) async => 'https://a.b');
        load(const RichText.plain('hi '), 3);

        await chord(tester, LogicalKeyboardKey.keyK);
        await tester.pump();

        expect(
          controller.richText,
          RichText('hi https://a.b', const [
            Entity(3, 11, EntityKind.link('https://a.b')),
          ]),
        );
      });

      testWidgets('without a prompt Ctrl+K does nothing', (tester) async {
        await show(tester);
        load(const RichText.plain('hello world'), 0, 5);

        await chord(tester, LogicalKeyboardKey.keyK);
        await tester.pump();

        expect(controller.richText, const RichText.plain('hello world'));
      });

      testWidgets('over code it does not ask', (tester) async {
        var asked = 0;
        await show(
          tester,
          linkPrompt: (context, _) async {
            asked++;
            return 'https://a.b';
          },
        );
        load(
          RichText('hello world', const [Entity(0, 5, EntityKind.code)]),
          0,
          5,
        );

        await chord(tester, LogicalKeyboardKey.keyK);

        expect(asked, 0);
      });

      testWidgets('the URL is not applied if the text changed under the '
          'prompt', (tester) async {
        late Completer<String?> answer;
        await show(
          tester,
          linkPrompt: (context, _) {
            answer = Completer<String?>();
            return answer.future;
          },
        );
        load(const RichText.plain('hello world'), 0, 5);

        await chord(tester, LogicalKeyboardKey.keyK);
        controller.text.restore(const RichText.plain('other'));
        answer.complete('https://a.b');
        await tester.pump();

        expect(controller.richText, const RichText.plain('other'));
      });
    });

    testWidgets('a host map that rebinds bold wins over the default', (
      tester,
    ) async {
      final map = {...const ComposerShortcutPolicy.desktop().shortcuts};
      map
        ..remove(const SingleActivator(LogicalKeyboardKey.keyB, control: true))
        ..[const SingleActivator(LogicalKeyboardKey.keyJ, control: true)] =
            const ToggleStyleIntent(EntityStyle.bold);
      await show(tester, shortcuts: map);
      load(const RichText.plain('hello world'), 0, 5);

      await chord(tester, LogicalKeyboardKey.keyB);

      expect(controller.richText, const RichText.plain('hello world'));

      await chord(tester, LogicalKeyboardKey.keyJ);

      expect(
        controller.richText,
        RichText('hello world', const [Entity(0, 5, EntityKind.bold)]),
      );
    });

    group('the shortcut and the command give one RichText', () {
      final cases =
          <
            String,
            (
              Intent,
              LogicalKeyboardKey,
              bool,
              void Function(ComposerTextController),
            )
          >{
            'bold': (
              const ToggleStyleIntent(EntityStyle.bold),
              LogicalKeyboardKey.keyB,
              false,
              (c) => c.toggleStyle(EntityStyle.bold),
            ),
            'quote': (
              const ToggleStyleIntent(EntityStyle.quote),
              LogicalKeyboardKey.period,
              true,
              (c) => c.toggleStyle(EntityStyle.quote),
            ),
            'clear formatting': (
              const ClearFormattingIntent(),
              LogicalKeyboardKey.keyN,
              true,
              (c) => c.clearFormatting(),
            ),
            'code block': (
              const ToggleCodeBlockIntent(),
              LogicalKeyboardKey.keyE,
              false,
              (c) => c.toggleCodeBlock(),
            ),
            'link': (
              const ApplyLinkIntent(),
              LogicalKeyboardKey.keyK,
              false,
              (c) => c.applyLink('https://a.b'),
            ),
          };

      for (final entry in cases.entries) {
        testWidgets(entry.key, (tester) async {
          final (_, key, shift, command) = entry.value;
          await show(
            tester,
            shortcuts: {
              ...const ComposerShortcutPolicy.desktop().shortcuts,
              const SingleActivator(LogicalKeyboardKey.keyE, control: true):
                  const ToggleCodeBlockIntent(),
            },
            linkPrompt: (context, _) async => 'https://a.b',
          );
          final start = RichText('one two\nthree', const [
            Entity(0, 3, EntityKind.bold),
          ]);
          load(start, 0, 7);
          final reference = ComposerTextController(initial: start)
            ..selection = const TextSelection(baseOffset: 0, extentOffset: 7);
          addTearDown(reference.dispose);

          command(reference);
          await chord(tester, key, shift: shift);
          await tester.pump();

          expect(controller.richText, reference.richText);
        });
      }
    });
  });
}

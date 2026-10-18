/// The apply-formatting toast after a plain paste whose text reads as
/// markdown.
///
/// **Seam:** the chat's input set under the app's scopes (`InputRig`), a paste
/// through the composer's clipboard, the toast on screen, and typing.
library;

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

const _toast = 'Apply formatting';

Future<(InputRig, FakeRichClipboard)> _pumpRig(WidgetTester tester) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  final rig = await InputRig.pump(tester, services: services);
  return (rig, services.clipboard as FakeRichClipboard);
}

Future<void> _paste(
  WidgetTester tester,
  InputRig rig,
  FakeRichClipboard clipboard,
  String text,
) async {
  clipboard.putPlainText(text);
  rig.set.composer.requestFocus();
  await tester.pump();
  await rig.set.composer.paste();
  await tester.pumpAndSettle();
}

void main() {
  group('after a plain paste', () {
    testWidgets('markdown offers to apply formatting, and the tap does', (
      tester,
    ) async {
      final (rig, clipboard) = await _pumpRig(tester);

      await _paste(tester, rig, clipboard, '**a** and _b_');

      expect(find.text(_toast), findsOneWidget);
      expect(rig.set.composer.richText.plain, '**a** and _b_');

      await tester.tap(find.text(_toast));
      await tester.pumpAndSettle();

      expect(
        rig.set.composer.richText,
        RichText('a and b', const [
          Entity(0, 1, EntityKind.bold),
          Entity(6, 1, EntityKind.italic),
        ]),
      );
      expect(find.text(_toast), findsNothing);
    });

    testWidgets('only the pasted range is replaced', (tester) async {
      final (rig, clipboard) = await _pumpRig(tester);
      await rig.typeInField(tester, 'see  end');
      rig.set.composer.select(const TextSelection.collapsed(offset: 4));

      await _paste(tester, rig, clipboard, '`x`');
      await tester.tap(find.text(_toast));
      await tester.pumpAndSettle();

      expect(
        rig.set.composer.richText,
        RichText('see x end', const [Entity(4, 1, EntityKind.code)]),
      );
    });

    testWidgets('plain text offers nothing', (tester) async {
      final (rig, clipboard) = await _pumpRig(tester);

      await _paste(tester, rig, clipboard, 'hello');

      expect(find.text(_toast), findsNothing);
      expect(rig.set.composer.richText.plain, 'hello');
    });

    testWidgets('a rich paste offers nothing', (tester) async {
      final (rig, clipboard) = await _pumpRig(tester);
      await clipboard.write(
        RichText('**a**', const [Entity(2, 1, EntityKind.italic)]),
      );
      rig.set.composer.requestFocus();
      await tester.pump();

      await rig.set.composer.paste();
      await tester.pump();

      expect(find.text(_toast), findsNothing);
    });

    testWidgets('typing a character dismisses it', (tester) async {
      final (rig, clipboard) = await _pumpRig(tester);
      await _paste(tester, rig, clipboard, '**a**');
      expect(find.text(_toast), findsOneWidget);

      await rig.typeInField(tester, '**a**!');
      await tester.pumpAndSettle();

      expect(find.text(_toast), findsNothing);
      expect(rig.set.composer.richText.plain, '**a**!');
    });

    testWidgets('moving the caret keeps it', (tester) async {
      final (rig, clipboard) = await _pumpRig(tester);
      await _paste(tester, rig, clipboard, '**a**');

      rig.set.composer.select(const TextSelection.collapsed(offset: 1));
      await tester.pump();

      expect(find.text(_toast), findsOneWidget);
    });

    testWidgets('goes away by itself after nine seconds', (tester) async {
      final (rig, clipboard) = await _pumpRig(tester);
      await _paste(tester, rig, clipboard, '**a**');

      await tester.pump(const Duration(seconds: 8));
      expect(find.text(_toast), findsOneWidget);

      await tester.pump(const Duration(seconds: 1, milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text(_toast), findsNothing);
      expect(rig.set.composer.richText.plain, '**a**');
    });
  });
}

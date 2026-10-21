/// The link preview in the composer's header strip: a debounced reading of
/// the typed text, never an entity in it.
///
/// **Seam:** the chat's input set under the app's scopes (`InputRig`), typing
/// into the field on a fake clock.
library;

import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

Future<InputRig> _pumpRig(WidgetTester tester) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  return InputRig.pump(tester, services: services);
}

/// Types [text] one character at a time, as a keyboard does.
Future<void> _typeSlowly(WidgetTester tester, InputRig rig, String text) async {
  final typed = StringBuffer(rig.set.composer.text.text);
  for (final character in text.split('')) {
    typed.write(character);
    await rig.typeInField(tester, typed.toString());
  }
}

void main() {
  testWidgets('a space after a URL shows its preview at once', (tester) async {
    final rig = await _pumpRig(tester);

    await rig.typeInField(tester, 'see https://a.b ');
    await tester.pump();

    expect(find.text('a.b'), findsOneWidget);
    expect(find.text('https://a.b'), findsOneWidget);
  });

  testWidgets('a URL typed without a space shows it after one second', (
    tester,
  ) async {
    final rig = await _pumpRig(tester);
    await rig.typeInField(tester, 'see ');

    await _typeSlowly(tester, rig, 'https://a.b');
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('a.b'), findsNothing);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.text('a.b'), findsOneWidget);
  });

  testWidgets('a paste, a jump of more than two characters, is at once', (
    tester,
  ) async {
    final rig = await _pumpRig(tester);

    await rig.typeInField(tester, 'https://a.b');
    await tester.pump();

    expect(find.text('a.b'), findsOneWidget);
  });

  testWidgets('shows the first URL, and goes with it', (tester) async {
    final rig = await _pumpRig(tester);
    await rig.typeInField(tester, 'https://a.b and https://c.d ');
    await tester.pump();
    expect(find.text('a.b'), findsOneWidget);
    expect(find.text('c.d'), findsNothing);

    await rig.typeInField(tester, 'no links ');
    await tester.pump();

    expect(find.text('a.b'), findsNothing);
  });

  testWidgets('the close control hides it until the URL changes', (
    tester,
  ) async {
    final rig = await _pumpRig(tester);
    await rig.typeInField(tester, 'https://a.b ');
    await tester.pump();

    rig.set.linkPreview.dismiss();
    await tester.pump();
    expect(find.text('a.b'), findsNothing);

    await rig.typeInField(tester, 'https://a.b and more ');
    await tester.pump();
    expect(find.text('a.b'), findsNothing);

    await rig.typeInField(tester, 'https://c.d ');
    await tester.pump();
    expect(find.text('c.d'), findsOneWidget);
  });

  testWidgets('never puts an entity in the composer text', (tester) async {
    final rig = await _pumpRig(tester);

    await rig.typeInField(tester, 'see https://a.b @name #tag ');
    await tester.pump(const Duration(seconds: 2));

    expect(rig.set.linkPreview.card.value?.url, 'https://a.b');
    expect(rig.set.composer.richText.entities, isEmpty);
    expect(
      rig.set.composer.richText,
      const RichText.plain('see https://a.b @name #tag '),
    );
  });

  testWidgets('goes when the message is sent', (tester) async {
    final rig = await _pumpRig(tester);
    await rig.typeInField(tester, 'https://a.b ');
    await tester.pump();

    await rig.set.submit();
    await tester.pump();

    expect(find.text('a.b'), findsNothing);
  });
}

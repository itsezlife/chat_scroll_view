/// The demo composer's `@` and `#` suggestion panels, and what a pick puts in
/// the text.
///
/// **Seam:** the chat's input set under the app's scopes (`InputRig`), typing
/// into the field and tapping a suggestion.
library;

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

Future<InputRig> _pumpRig(WidgetTester tester) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  return InputRig.pump(tester, services: services);
}

void main() {
  group('typing @', () {
    testWidgets('opens the username panel, and a pick inserts a mention', (
      tester,
    ) async {
      final rig = await _pumpRig(tester);

      await rig.typeInField(tester, 'hi @al');
      await tester.pumpAndSettle();

      expect(rig.set.composer.query.value?.kind.id, 'username');
      expect(find.text('@alice'), findsOneWidget);
      expect(find.text('@alan'), findsOneWidget);
      expect(find.text('@dana'), findsNothing);

      await tester.tap(find.text('@alice'));
      await tester.pumpAndSettle();

      expect(
        rig.set.composer.richText,
        RichText('hi @alice ', const [Entity(3, 6, EntityKind.mention('u1'))]),
      );
      expect(find.text('@alice'), findsNothing);
    });

    testWidgets('a picked mention is sent as the user the host resolved', (
      tester,
    ) async {
      final rig = await _pumpRig(tester);
      await rig.typeInField(tester, '@al');
      await tester.pumpAndSettle();
      await tester.tap(find.text('@alice'));
      await tester.pumpAndSettle();

      await rig.set.submit();

      expect(rig.sent, ['[@alice](mention:u1)']);
    });

    testWidgets('a user with no username is mentioned by name', (tester) async {
      final rig = await _pumpRig(tester);

      await rig.typeInField(tester, '@da');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dana Lee'));
      await tester.pumpAndSettle();

      expect(
        rig.set.composer.richText,
        RichText('Dana Lee ', const [Entity(0, 8, EntityKind.mention('u3'))]),
      );
    });

    testWidgets('shows no panel when nobody matches', (tester) async {
      final rig = await _pumpRig(tester);

      await rig.typeInField(tester, '@zzz');
      await tester.pumpAndSettle();

      expect(rig.set.composer.query.value?.kind.id, 'username');
      expect(find.byType(ListView), findsNothing);
    });
  });

  group('typing #', () {
    testWidgets('opens the hashtag panel, and a pick inserts a hashtag', (
      tester,
    ) async {
      final rig = await _pumpRig(tester);

      await rig.typeInField(tester, '#ta');
      await tester.pumpAndSettle();

      expect(rig.set.composer.query.value?.kind.id, 'hashtag');
      expect(find.text('#tasks'), findsOneWidget);
      expect(find.text('#travel'), findsNothing);

      await tester.tap(find.text('#tasks'));
      await tester.pumpAndSettle();

      expect(
        rig.set.composer.richText,
        RichText('#tasks ', const [Entity(0, 6, EntityKind.hashtag('tasks'))]),
      );
    });
  });

  group('a pasted mention', () {
    testWidgets('is kept when the host knows the user, else sent as a name', (
      tester,
    ) async {
      final services = (await tester.runAsync(createTestServices))!;
      addTearDown(services.dispose);
      final rig = await InputRig.pump(tester, services: services);
      final clipboard = services.clipboard as FakeRichClipboard;
      await clipboard.write(
        RichText('@alice @ghost', const [
          Entity(0, 6, EntityKind.mention('u1')),
          Entity(7, 6, EntityKind.mention('u99')),
        ]),
      );
      rig.set.composer.requestFocus();
      await tester.pump();

      await rig.set.composer.paste();
      await tester.pump();

      expect(
        rig.set.composer.sendableText,
        RichText('@alice @ghost', const [
          Entity(0, 6, EntityKind.mention('u1')),
          Entity(7, 6, EntityKind.username('ghost')),
        ]),
      );
    });
  });
}

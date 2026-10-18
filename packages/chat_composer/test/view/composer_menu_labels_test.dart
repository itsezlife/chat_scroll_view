/// The language of the composer's menus: every label, the clipboard rows
/// included, comes from the host's `ChromeStrings`, in the touch toolbar and in
/// the desktop pointer menu, whatever the Material localisations say.
///
/// **Seam:** a `ComposerView` under a host whose Material localisations are
/// replaced by a recognisable stand-in, or are English under a Russian app,
/// read through the labels the menus draw.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';
import '../support/selection_menu_harness.dart';

/// Material localisations whose clipboard labels cannot be mistaken for
/// anything a host's own strings say.
final class _StandIn extends DefaultMaterialLocalizations {
  const _StandIn();

  @override
  String get cutButtonLabel => 'MATERIAL-CUT';

  @override
  String get copyButtonLabel => 'MATERIAL-COPY';

  @override
  String get pasteButtonLabel => 'MATERIAL-PASTE';

  @override
  String get selectAllButtonLabel => 'MATERIAL-SELECT-ALL';
}

final class _StandInDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _StandInDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(const _StandIn());

  @override
  bool shouldReload(_StandInDelegate old) => false;
}

void main() {
  final russian = ChromeStringsPresets.russian;
  final edit = russian.editMenu;

  setUp(() {
    // The toolbar offers Paste while the platform says it has text.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => call.method == 'Clipboard.hasStrings'
              ? <String, Object?>{'value': true}
              : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Iterable<String> drawn(WidgetTester tester) => [
    for (final text in tester.widgetList<Text>(find.byType(Text)))
      if (text.data != null) text.data!,
  ];

  group('the touch toolbar', () {
    testWidgets('reads its clipboard labels from ChromeStrings, not from '
        'MaterialLocalizations', (tester) async {
      await MenuRig.show(
        tester,
        size: const Size(900, 700),
        strings: russian,
        clipboard: FakeRichClipboard(),
        localizationsDelegates: const [_StandInDelegate()],
      );

      final labels = drawn(tester).toList();
      expect(
        labels,
        containsAll([
          edit.cutAction,
          edit.copyAction,
          edit.pasteAction,
          edit.selectAllAction,
          russian.composer.pastePlainAction,
        ]),
      );
      expect(labels.where((l) => l.contains('MATERIAL')), isEmpty);
    });

    testWidgets('speaks them too', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await MenuRig.show(
        tester,
        size: const Size(900, 700),
        strings: russian,
        clipboard: FakeRichClipboard(),
        localizationsDelegates: const [_StandInDelegate()],
      );

      // The row holds Cut and Copy; Paste and the rest are on the page.
      for (final label in [edit.cutAction, edit.copyAction]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      await rig.openMore();
      for (final label in [edit.pasteAction, edit.selectAllAction]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(find.bySemanticsLabel(RegExp('MATERIAL')), findsNothing);
      handle.dispose();
    });

    testWidgets('a Russian app whose Material localisations are English still '
        'reads Russian', (tester) async {
      // The example's situation: no Russian Material delegate, so Material
      // falls back to English while the host's strings are Russian.
      await MenuRig.show(
        tester,
        size: const Size(900, 700),
        strings: russian,
        locale: const Locale('ru'),
      );

      expect(
        MaterialLocalizations.of(tester.element(MenuRig.card)).cutButtonLabel,
        'Cut',
        reason: 'the host has no Russian Material localisation',
      );
      final labels = drawn(tester).toList();
      expect(labels, contains(edit.cutAction));
      expect(labels, contains(edit.copyAction));
      expect(labels, isNot(contains('Cut')));
      expect(labels, isNot(contains('Copy')));
    });

    testWidgets('draws a label without the pointer menu\'s mnemonic marks', (
      tester,
    ) async {
      // The English preset marks access letters: Cu&t, &Copy, &Paste.
      await MenuRig.show(tester, size: const Size(900, 700));

      final labels = drawn(tester).toList();
      expect(labels, containsAll(['Cut', 'Copy', 'Paste']));
      expect(labels.where((l) => l.contains('&')), isEmpty);
    });

    testWidgets('a label with a literal ampersand keeps it', (tester) async {
      final strings = ChromeStrings(
        panel: russian.panel,
        composer: russian.composer,
        formatting: russian.formatting,
        editMenu: EditMenuStrings(
          undoAction: edit.undoAction,
          redoAction: edit.redoAction,
          cutAction: 'Cut && go',
          copyAction: edit.copyAction,
          pasteAction: edit.pasteAction,
          deleteAction: edit.deleteAction,
          selectAllAction: edit.selectAllAction,
          formattingMenu: edit.formattingMenu,
          boldAction: edit.boldAction,
          italicAction: edit.italicAction,
          underlineAction: edit.underlineAction,
          strikethroughAction: edit.strikethroughAction,
          quoteAction: edit.quoteAction,
          monospaceAction: edit.monospaceAction,
          spoilerAction: edit.spoilerAction,
          createLinkAction: edit.createLinkAction,
          editLinkAction: edit.editLinkAction,
          clearFormattingAction: edit.clearFormattingAction,
          pastePlainAction: edit.pastePlainAction,
          codeBlockAction: edit.codeBlockAction,
          removeLinkAction: edit.removeLinkAction,
          bulletListAction: edit.bulletListAction,
          numberedListAction: edit.numberedListAction,
          spellingMenu: edit.spellingMenu,
          addToDictionaryAction: edit.addToDictionaryAction,
          ignoreWordAction: edit.ignoreWordAction,
          removeFromDictionaryAction: edit.removeFromDictionaryAction,
        ),
        semantics: russian.semantics,
      );
      await MenuRig.show(tester, size: const Size(900, 700), strings: strings);

      expect(drawn(tester), contains('Cut & go'));
    });

    testWidgets('the formatting rows are in the host\'s language too', (
      tester,
    ) async {
      final rig = await MenuRig.show(
        tester,
        size: const Size(900, 700),
        strings: russian,
        localizationsDelegates: const [_StandInDelegate()],
      );
      await rig.openMore();

      final labels = drawn(tester).toList();
      expect(
        labels,
        containsAll([
          russian.formatting.boldAction,
          russian.formatting.italicAction,
          russian.formatting.backAction,
        ]),
      );
    });
  });

  group('the desktop pointer menu', () {
    testWidgets('reads the same strings whatever Material says', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(900, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      final composer = ComposerController(clipboard: FakeRichClipboard());
      addTearDown(composer.dispose);
      await tester.pumpWidget(
        composerHarness(
          ComposerView(
            controller: composer,
            menuPolicy: ComposerMenuPolicy.forPlatform(
              TargetPlatform.macOS,
              isWeb: false,
            ),
            spec: ComposerSpec(),
          ),
          strings: russian,
          motionSpeed: ChromeMotionSpeed.instant,
          localizationsDelegates: const [_StandInDelegate()],
        ),
      );
      composer
        ..requestFocus()
        ..restore(
          const RichText.plain('one two three'),
          selection: const TextSelection(baseOffset: 4, extentOffset: 7),
        );
      await tester.pump();

      final mouse = await tester.startGesture(
        tester.getCenter(find.byType(ExtendedTextField)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();

      expect(find.byKey(const PointerMenuPanelKey(0)), findsOneWidget);
      // The pointer menu draws its access letters apart, so it is read as it
      // is spoken: the label with its marks removed.
      for (final label in [
        edit.cutAction,
        edit.copyAction,
        edit.selectAllAction,
      ]) {
        expect(
          find.bySemanticsLabel(PointerMenuLabel.parse(label).text),
          findsWidgets,
          reason: label,
        );
      }
      expect(find.bySemanticsLabel(RegExp('MATERIAL')), findsNothing);
      handle.dispose();
    });
  });
}

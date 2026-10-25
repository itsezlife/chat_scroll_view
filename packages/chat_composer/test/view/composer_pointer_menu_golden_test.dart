/// Goldens of the composer's pointer menu, one per kind of target: a caret
/// (everything that needs a selection greyed), a selection with the Formatting
/// submenu open, a link under the pointer, a misspelled word with Spelling on
/// top and at the bottom, and the night theme.
///
/// **macOS-generated**, drawn with the test font (every glyph a square): they
/// check geometry, hints, the greyed and highlighted states and the token
/// colours. Rounded edges and the blurred shadow are anti-aliased, hence the
/// 1% pixel tolerance. Regenerate with `flutter test --update-goldens
/// test/view/composer_pointer_menu_golden_test.dart`.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';
import '../support/tolerant_golden_comparator.dart';

const _tolerance = 0.01;

final class _Speller implements ComposerSpellChecker {
  @override
  Future<ComposerWordSpelling> check(String word) async =>
      const ComposerWordSpelling(
        isCorrect: false,
        suggestions: ['hello', 'help', 'hero'],
      );

  @override
  Future<void> addToDictionary(String word) async {}

  @override
  Future<void> ignore(String word) async {}

  @override
  Future<void> removeFromDictionary(String word) async {}
}

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

final _english = ChromeStringsPresets.english;

// The English preset with the pointer menu's Clear row as the baselines were
// drawn. The test font draws every glyph as a square, so a label's length is
// pixels, and the baselines are the CI runner's: the preset's "Plain text"
// (the desktop client's wording) waits for a regeneration there.
final _baselineStrings = ChromeStrings(
  panel: _english.panel,
  composer: _english.composer,
  formatting: _english.formatting,
  semantics: _english.semantics,
  editMenu: EditMenuStrings(
    undoAction: _english.editMenu.undoAction,
    redoAction: _english.editMenu.redoAction,
    cutAction: _english.editMenu.cutAction,
    copyAction: _english.editMenu.copyAction,
    pasteAction: _english.editMenu.pasteAction,
    deleteAction: _english.editMenu.deleteAction,
    selectAllAction: _english.editMenu.selectAllAction,
    formattingMenu: _english.editMenu.formattingMenu,
    boldAction: _english.editMenu.boldAction,
    italicAction: _english.editMenu.italicAction,
    underlineAction: _english.editMenu.underlineAction,
    strikethroughAction: _english.editMenu.strikethroughAction,
    quoteAction: _english.editMenu.quoteAction,
    monospaceAction: _english.editMenu.monospaceAction,
    spoilerAction: _english.editMenu.spoilerAction,
    createLinkAction: _english.editMenu.createLinkAction,
    editLinkAction: _english.editMenu.editLinkAction,
    pastePlainAction: _english.editMenu.pastePlainAction,
    codeBlockAction: _english.editMenu.codeBlockAction,
    removeLinkAction: _english.editMenu.removeLinkAction,
    bulletListAction: _english.editMenu.bulletListAction,
    numberedListAction: _english.editMenu.numberedListAction,
    spellingMenu: _english.editMenu.spellingMenu,
    addToDictionaryAction: _english.editMenu.addToDictionaryAction,
    ignoreWordAction: _english.editMenu.ignoreWordAction,
    removeFromDictionaryAction: _english.editMenu.removeFromDictionaryAction,
    clearFormattingAction: 'Clear formatting',
  ),
);

void main() {
  setUpAll(() {
    goldenFileComparator = TolerantGoldenComparator(
      Uri.file('test/view/composer_pointer_menu_golden_test.dart'),
      tolerance: _tolerance,
    );
  });

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    RichText text = const RichText.plain('helo world and more words'),
    TextSelection selection = const TextSelection.collapsed(offset: 0),
    int click = 1,
    bool atTop = true,
    bool richClipboard = true,
    bool spell = false,
    Brightness brightness = Brightness.light,
    Size size = const Size(640, 560),
    Object? openSubmenu,
    Object? hover,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.hasStrings'
          ? <String, Object?>{'value': true}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final clipboard = richClipboard ? FakeRichClipboard() : null;
    clipboard?.putPlainText('clip');
    final composer = ComposerController(clipboard: clipboard);
    addTearDown(composer.dispose);
    await tester.pumpWidget(
      composerHarness(
        ComposerView(
          controller: composer,
          spec: ComposerSpec(
            spellChecker: spell ? _Speller() : null,
            linkPrompt: (context, url) async => null,
          ),
        ),
        brightness: brightness,
        textDirection: direction,
        anchoredTop: atTop,
        motionSpeed: ChromeMotionSpeed.instant,
        strings: _baselineStrings,
      ),
    );
    composer
      ..requestFocus()
      ..restore(text, selection: selection);
    await tester.pump();

    final render = tester
        .state<ExtendedEditableTextState>(find.byType(ExtendedEditableText))
        .renderEditable;
    final box = render
        .getBoxesForSelection(
          TextSelection(baseOffset: click, extentOffset: click + 1),
        )
        .first;
    final at = render.localToGlobal(box.toRect().center);
    final mouse = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.up();
    await tester.pumpAndSettle();

    Future<void> glide(Object id) async {
      final to = tester.getCenter(find.byKey(PointerMenuRowKey(id)));
      final from = at;
      for (var i = 1; i <= 8; i++) {
        await mouse.moveTo(Offset.lerp(from, to, i / 8)!);
      }
      await tester.pump();
    }

    if (openSubmenu != null) await glide(openSubmenu);
    if (hover != null) await glide(hover);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/composer_pointer_menu_$name.png'),
    );
  }

  testWidgets('a caret: everything that needs a selection is greyed', (
    tester,
  ) async {
    await shoot(tester, 'caret', richClipboard: false);
  }, variant: _windows);

  testWidgets('a selection with the Formatting submenu open, a row '
      'highlighted', (tester) async {
    await shoot(
      tester,
      'selection_formatting',
      selection: const TextSelection(baseOffset: 5, extentOffset: 10),
      click: 17,
      openSubmenu: ComposerMenuAction.formatting,
      hover: ComposerMenuAction.italic,
    );
  }, variant: _windows);

  testWidgets('the pointer over a link offers Edit link and Remove link', (
    tester,
  ) async {
    await shoot(
      tester,
      'link',
      text: RichText('go to site now', const [
        Entity(6, 4, EntityKind.link('https://a.example')),
      ]),
      click: 7,
      openSubmenu: ComposerMenuAction.formatting,
    );
  }, variant: _windows);

  testWidgets('a misspelled word puts Spelling on top, its submenu open', (
    tester,
  ) async {
    await shoot(
      tester,
      'spelling_top',
      spell: true,
      click: 1,
      openSubmenu: ComposerMenuAction.spelling,
    );
  }, variant: _windows);

  testWidgets('at the bottom of the screen the menu opens upward with '
      'Spelling at the bottom', (tester) async {
    await shoot(
      tester,
      'spelling_bottom',
      spell: true,
      click: 1,
      atTop: false,
      size: const Size(640, 520),
    );
  }, variant: _windows);

  testWidgets('the night theme', (tester) async {
    await shoot(
      tester,
      'night',
      brightness: Brightness.dark,
      selection: const TextSelection(baseOffset: 5, extentOffset: 10),
      click: 17,
      hover: ComposerMenuAction.copy,
    );
  }, variant: _windows);

  testWidgets('right-to-left mirrors the menu', (tester) async {
    await shoot(
      tester,
      'rtl',
      direction: TextDirection.rtl,
      selection: const TextSelection(baseOffset: 5, extentOffset: 10),
      click: 17,
      openSubmenu: ComposerMenuAction.formatting,
    );
  }, variant: _windows);
}

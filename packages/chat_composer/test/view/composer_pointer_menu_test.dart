/// The composer's pointer menu on desktop: a secondary click in the field
/// opens the reference client's context menu at the pointer, over a selection
/// it leaves alone.
///
/// **Seam:** a `ComposerView` over a `ComposerController` under a macOS or
/// Windows platform variant, driven by a mouse `TestGesture` (real pointer
/// events, press and release apart), read through the pointer menu's panel and
/// row keys, the semantics tree, the clipboard fake and the controller.
library;

import 'dart:ui' show Tristate;

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';
import '../support/selection_menu_harness.dart';

const _both = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.windows,
});

final class _Fake implements ComposerSpellChecker {
  _Fake(this.verdicts);

  final Map<String, ComposerWordSpelling> verdicts;
  final calls = <String>[];

  @override
  Future<ComposerWordSpelling> check(String word) async =>
      verdicts[word] ?? const ComposerWordSpelling(isCorrect: true);

  @override
  Future<void> addToDictionary(String word) async => calls.add('add $word');

  @override
  Future<void> ignore(String word) async => calls.add('ignore $word');

  @override
  Future<void> removeFromDictionary(String word) async =>
      calls.add('remove $word');
}

final class _Rig {
  _Rig(this.tester, this.composer, this.prompts);

  final WidgetTester tester;
  final ComposerController composer;
  final List<String?> prompts;
  TestGesture? _mouse;

  static String? answer;

  static Future<_Rig> pump(
    WidgetTester tester, {
    RichText text = const RichText.plain('one two three four five'),
    TextSelection selection = const TextSelection.collapsed(offset: 0),
    FakeRichClipboard? clipboard,
    ComposerSpellChecker? spellChecker,
    bool lists = false,
    bool atTop = false,
    Set<ComposerFormattingOption> formatting =
        ComposerFormattingOption.standard,
    ComposerMenuPolicy? menuPolicy,
    Size size = const Size(900, 700),
    ChromeMotionSpeed motionSpeed = ChromeMotionSpeed.instant,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final composer = ComposerController(
      text: ComposerTextController(lists: lists),
      clipboard: clipboard,
    );
    addTearDown(composer.dispose);
    final prompts = <String?>[];
    // The platform clipboard answers "nothing to paste": its channel has no
    // engine behind it in a test, and a call to it would never return.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.hasStrings'
          ? <String, Object?>{'value': false}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final view = ComposerView(
      controller: composer,
      menuPolicy: menuPolicy,
      spec: ComposerSpec(
        formatting: formatting,
        spellChecker: spellChecker,
        linkPrompt: (context, url) async {
          prompts.add(url);
          return answer;
        },
      ),
    );
    await tester.pumpWidget(
      composerHarness(
        view,
        motionSpeed: motionSpeed,
        // At the bottom a menu always flips upward, so a test of the downward
        // layout lifts the composer.
        anchoredTop: atTop,
      ),
    );
    composer
      ..requestFocus()
      ..restore(text, selection: selection);
    await tester.pump();
    return _Rig(tester, composer, prompts);
  }

  ExtendedRenderEditable get render => tester
      .state<ExtendedEditableTextState>(find.byType(ExtendedEditableText))
      .renderEditable;

  /// A point over the character at [offset].
  Offset over(int offset) {
    final box = render
        .getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + 1),
        )
        .first;
    return render.localToGlobal(box.toRect().center);
  }

  /// The middle of the text field.
  Offset get fieldCenter => tester.getCenter(find.byType(ExtendedTextField));

  static Finder get panel => find.byKey(const PointerMenuPanelKey(0));

  Finder row(Object id) => find.byKey(PointerMenuRowKey(id));

  bool isOpen() => panel.evaluate().isNotEmpty;

  /// Presses the secondary button at [at]; [release] lifts it.
  Future<void> press(Offset at, {bool release = true}) async {
    _mouse = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    _last = at;
    await tester.pump();
    await tester.pump();
    if (release) await lift();
  }

  Future<void> lift() async {
    await _mouse!.up();
    await tester.pump();
    await tester.pump();
  }

  /// A full right click, opened and settled.
  Future<void> rightClick(Offset at) async {
    await press(at);
    await tester.pumpAndSettle();
  }

  bool enabled(Object id) =>
      tester
          .getSemantics(row(id))
          .getSemanticsData()
          .flagsCollection
          .isEnabled ==
      Tristate.isTrue;

  /// Moves the mouse onto [id] in steps, so the pointer guard is satisfied.
  Future<void> hover(Object id) async {
    final to = tester.getCenter(row(id));
    final from = _last ?? tester.getRect(panel).topLeft;
    for (var i = 1; i <= 8; i++) {
      await _mouse!.moveTo(Offset.lerp(from, to, i / 8)!);
    }
    _last = to;
    await tester.pump();
  }

  Offset? _last;

  Future<void> choose(Object id) async {
    await hover(id);
    await tester.tapAt(
      tester.getCenter(row(id)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  TextSelection get selection => composer.selection;
}

/// A test that reads the semantics tree: the handle is released before the
/// test ends, which is when the framework checks.
void semanticsTest(
  String name,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(name, (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      handle.dispose();
    }
  }, variant: _both);
}

void main() {
  group('opening', () {
    testWidgets('opens at the pointer, 5 px right of it and level with it', (
      tester,
    ) async {
      final rig = await _Rig.pump(tester, atTop: true);
      final at = rig.over(5);

      await rig.rightClick(at);

      expect(_Rig.panel, findsOneWidget);
      expect(tester.getTopLeft(_Rig.panel), at + const Offset(5, 0));
    }, variant: _both);

    testWidgets('opens on the press on macOS and on the release on Windows', (
      tester,
    ) async {
      final rig = await _Rig.pump(tester);

      await rig.press(rig.over(5), release: false);
      final onPress = rig.isOpen();
      await rig.lift();
      await tester.pumpAndSettle();

      expect(
        onPress,
        debugDefaultTargetPlatformOverride == TargetPlatform.macOS,
      );
      expect(rig.isOpen(), isTrue);
    }, variant: _both);

    testWidgets('leaves a selection where it was, whatever is clicked', (
      tester,
    ) async {
      final rig = await _Rig.pump(
        tester,
        selection: const TextSelection(baseOffset: 0, extentOffset: 3),
      );

      await rig.rightClick(rig.over(15));

      expect(
        rig.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
    }, variant: _both);

    testWidgets('leaves a caret where it was', (tester) async {
      final rig = await _Rig.pump(
        tester,
        selection: const TextSelection.collapsed(offset: 2),
      );

      await rig.rightClick(rig.over(15));

      expect(rig.selection, const TextSelection.collapsed(offset: 2));
    }, variant: _both);

    testWidgets('shows the pointer menu, not the floating toolbar', (
      tester,
    ) async {
      final rig = await _Rig.pump(tester);

      await rig.rightClick(rig.over(5));

      expect(MenuRig.card, findsNothing);
      expect(_Rig.panel, findsOneWidget);
    }, variant: _both);

    testWidgets('the field keeps focus while the menu is up', (tester) async {
      final rig = await _Rig.pump(tester);

      await rig.rightClick(rig.over(5));

      expect(rig.composer.hasFocus, isTrue);
    }, variant: _both);

    testWidgets('a press on an unfocused field gives it focus', (tester) async {
      final rig = await _Rig.pump(tester);
      rig.composer.unfocus();
      await tester.pump();

      await rig.rightClick(rig.over(5));

      expect(rig.composer.hasFocus, isTrue);
      expect(_Rig.panel, findsOneWidget);
    }, variant: _both);

    testWidgets('a second right click while it is up closes it', (
      tester,
    ) async {
      final rig = await _Rig.pump(tester);
      await rig.rightClick(rig.over(5));

      await rig.press(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(rig.isOpen(), isFalse);
    }, variant: _both);

    testWidgets('Escape closes it and the field keeps its selection', (
      tester,
    ) async {
      final rig = await _Rig.pump(
        tester,
        selection: const TextSelection(baseOffset: 4, extentOffset: 7),
      );
      await rig.rightClick(rig.over(15));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(rig.isOpen(), isFalse);
      expect(rig.composer.hasFocus, isTrue);
      expect(
        rig.selection,
        const TextSelection(baseOffset: 4, extentOffset: 7),
      );
    }, variant: _both);

    testWidgets('the mobile policy opens no pointer menu', (tester) async {
      final rig = await _Rig.pump(
        tester,
        menuPolicy: const ComposerMenuPolicy.mobile(),
      );

      await rig.rightClick(rig.over(5));

      expect(rig.isOpen(), isFalse);
    }, variant: _both);

    testWidgets('the Menu key opens it at the caret', (tester) async {
      final rig = await _Rig.pump(
        tester,
        selection: const TextSelection.collapsed(offset: 4),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();

      expect(_Rig.panel, findsOneWidget);
      final caret = rig.render
          .getLocalRectForCaret(const TextPosition(offset: 4))
          .bottomLeft;
      // The caret is near the bottom of the screen: the menu opens upward,
      // its bottom edge level with the caret's.
      final at = rig.render.localToGlobal(caret);
      final panel = tester.getRect(_Rig.panel);
      expect(panel.left, at.dx + 5);
      expect(panel.bottom, at.dy);
    }, variant: _both);

    testWidgets('Shift+F10 opens it too', (tester) async {
      await _Rig.pump(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(_Rig.panel, findsOneWidget);
    }, variant: _both);
  });

  group('which rows are live', () {
    semanticsTest('an empty field: only Formatting', (tester) async {
      final rig = await _Rig.pump(tester, text: RichText.empty);
      await rig.rightClick(rig.fieldCenter);

      for (final id in [
        ComposerMenuAction.undo,
        ComposerMenuAction.redo,
        ComposerMenuAction.cut,
        ComposerMenuAction.copy,
        ComposerMenuAction.delete,
        ComposerMenuAction.selectAll,
      ]) {
        expect(rig.enabled(id), isFalse, reason: '$id');
      }
      expect(rig.enabled(ComposerMenuAction.formatting), isTrue);
    });

    semanticsTest('a selection enables cut, copy, delete and select all', (
      tester,
    ) async {
      final rig = await _Rig.pump(
        tester,
        selection: const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      await rig.rightClick(rig.over(15));

      for (final id in [
        ComposerMenuAction.cut,
        ComposerMenuAction.copy,
        ComposerMenuAction.delete,
        ComposerMenuAction.selectAll,
      ]) {
        expect(rig.enabled(id), isTrue, reason: '$id');
      }
    });

    semanticsTest('a caret greys cut, copy and delete but not select all', (
      tester,
    ) async {
      final rig = await _Rig.pump(tester);
      await rig.rightClick(rig.over(15));

      expect(rig.enabled(ComposerMenuAction.cut), isFalse);
      expect(rig.enabled(ComposerMenuAction.copy), isFalse);
      expect(rig.enabled(ComposerMenuAction.delete), isFalse);
      expect(rig.enabled(ComposerMenuAction.selectAll), isTrue);
    });

    semanticsTest('paste follows the clipboard', (tester) async {
      final clipboard = FakeRichClipboard();
      final rig = await _Rig.pump(tester, clipboard: clipboard);
      await rig.rightClick(rig.over(5));
      expect(rig.enabled(ComposerMenuAction.paste), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      clipboard.putPlainText('hello');
      await rig.rightClick(rig.over(5));

      expect(rig.enabled(ComposerMenuAction.paste), isTrue);
      expect(rig.enabled(ComposerMenuAction.pastePlain), isTrue);
    });

    testWidgets('Paste as plain text appears only with a rich clipboard', (
      tester,
    ) async {
      final rig = await _Rig.pump(tester);
      await rig.rightClick(rig.over(5));

      expect(rig.row(ComposerMenuAction.pastePlain), findsNothing);
    }, variant: _both);
  });

  group('rows', () {
    testWidgets(
      'Copy keeps the selection and puts the text on the clipboard',
      (tester) async {
        final clipboard = FakeRichClipboard();
        final rig = await _Rig.pump(
          tester,
          clipboard: clipboard,
          selection: const TextSelection(baseOffset: 4, extentOffset: 7),
        );
        await rig.rightClick(rig.over(15));

        await rig.choose(ComposerMenuAction.copy);

        expect((await clipboard.read())?.plain, 'two');
        expect(
          rig.selection,
          const TextSelection(baseOffset: 4, extentOffset: 7),
        );
        expect(rig.isOpen(), isFalse);
        expect(rig.composer.hasFocus, isTrue);
      },
      variant: _both,
    );

    testWidgets('Cut removes the selection and fills the clipboard', (
      tester,
    ) async {
      final clipboard = FakeRichClipboard();
      final rig = await _Rig.pump(
        tester,
        clipboard: clipboard,
        selection: const TextSelection(baseOffset: 4, extentOffset: 8),
      );
      await rig.rightClick(rig.over(15));

      await rig.choose(ComposerMenuAction.cut);

      expect(rig.composer.text.text, 'one three four five');
      expect((await clipboard.read())?.plain, 'two ');
    }, variant: _both);

    testWidgets('Delete removes the selection and leaves the clipboard', (
      tester,
    ) async {
      final clipboard = FakeRichClipboard()..putPlainText('kept');
      final rig = await _Rig.pump(
        tester,
        clipboard: clipboard,
        selection: const TextSelection(baseOffset: 4, extentOffset: 8),
      );
      await rig.rightClick(rig.over(15));

      await rig.choose(ComposerMenuAction.delete);

      expect(rig.composer.text.text, 'one three four five');
      expect((await clipboard.read())?.plain, 'kept');
    }, variant: _both);

    testWidgets('Paste puts the clipboard at the caret', (tester) async {
      final clipboard = FakeRichClipboard()..putPlainText('XY');
      final rig = await _Rig.pump(
        tester,
        clipboard: clipboard,
        selection: const TextSelection.collapsed(offset: 3),
      );
      await rig.rightClick(rig.over(15));

      await rig.choose(ComposerMenuAction.paste);

      expect(rig.composer.text.text, 'oneXY two three four five');
    }, variant: _both);

    testWidgets('Paste as plain text drops the formatting', (tester) async {
      final clipboard = FakeRichClipboard();
      await clipboard.write(
        RichText('bold', const [Entity(0, 4, EntityKind.bold)]),
      );
      final rig = await _Rig.pump(
        tester,
        clipboard: clipboard,
        text: RichText.empty,
      );
      await rig.rightClick(rig.fieldCenter);

      await rig.choose(ComposerMenuAction.pastePlain);

      expect(rig.composer.richText, const RichText.plain('bold'));
    }, variant: _both);

    testWidgets('Select All selects everything and closes the menu', (
      tester,
    ) async {
      final rig = await _Rig.pump(tester);
      await rig.rightClick(rig.over(15));

      await rig.choose(ComposerMenuAction.selectAll);

      expect(
        rig.selection,
        const TextSelection(baseOffset: 0, extentOffset: 23),
      );
      expect(rig.isOpen(), isFalse);
    }, variant: _both);

    semanticsTest('Undo and Redo step the field\'s history', (tester) async {
      final rig = await _Rig.pump(tester, text: RichText.empty);
      rig.composer.select(const TextSelection.collapsed(offset: 0));
      await tester.pump(const Duration(seconds: 1));
      await enterFieldText(tester, 'typed');
      await tester.pump(const Duration(seconds: 1));
      await rig.rightClick(rig.fieldCenter);
      expect(rig.enabled(ComposerMenuAction.undo), isTrue);

      await rig.choose(ComposerMenuAction.undo);
      expect(rig.composer.text.text, '');

      await rig.rightClick(rig.fieldCenter);
      expect(rig.enabled(ComposerMenuAction.redo), isTrue);
      await rig.choose(ComposerMenuAction.redo);
      expect(rig.composer.text.text, 'typed');
    });

    testWidgets('a disabled row cannot be chosen', (tester) async {
      final rig = await _Rig.pump(tester);
      await rig.rightClick(rig.over(15));

      await rig.choose(ComposerMenuAction.cut);

      expect(rig.isOpen(), isTrue);
      expect(rig.composer.text.text, 'one two three four five');
    }, variant: _both);
  });

  group('the Formatting submenu', () {
    testWidgets('opens beside its row and formats the selection', (
      tester,
    ) async {
      final rig = await _Rig.pump(
        tester,
        selection: const TextSelection(baseOffset: 4, extentOffset: 7),
      );
      await rig.rightClick(rig.over(15));

      await rig.hover(ComposerMenuAction.formatting);
      expect(rig.row(ComposerMenuAction.bold), findsOneWidget);
      await rig.choose(ComposerMenuAction.bold);

      expect(
        rig.composer.richText.entities.single,
        const Entity(4, 3, EntityKind.bold),
      );
      expect(rig.isOpen(), isFalse);
    }, variant: _both);

    semanticsTest('over a caret every style row is greyed', (tester) async {
      final rig = await _Rig.pump(tester);
      await rig.rightClick(rig.over(15));

      await rig.hover(ComposerMenuAction.formatting);

      for (final id in [
        ComposerMenuAction.bold,
        ComposerMenuAction.quote,
        ComposerMenuAction.codeBlock,
        ComposerMenuAction.clearFormatting,
      ]) {
        expect(rig.enabled(id), isFalse, reason: '$id');
      }
      expect(rig.enabled(ComposerMenuAction.createLink), isTrue);
    });

    testWidgets('the arrow keys open it too', (tester) async {
      final rig = await _Rig.pump(tester);
      await rig.rightClick(rig.over(15));

      for (var i = 0; i < 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(rig.row(ComposerMenuAction.bold), findsOneWidget);
    }, variant: _both);
  });

  group('links', () {
    final linked = RichText('go to site now', const [
      Entity(6, 4, EntityKind.link('https://a.example')),
    ]);

    testWidgets('a right click on a link with nothing selected offers Edit '
        'link and edits it where it is', (tester) async {
      _Rig.answer = 'https://b.example';
      addTearDown(() => _Rig.answer = null);
      final rig = await _Rig.pump(
        tester,
        text: linked,
        selection: const TextSelection.collapsed(offset: 1),
      );
      await rig.rightClick(rig.over(7));
      await rig.hover(ComposerMenuAction.formatting);
      expect(rig.row(ComposerMenuAction.editLink), findsOneWidget);
      expect(rig.row(ComposerMenuAction.createLink), findsNothing);

      await rig.choose(ComposerMenuAction.editLink);
      await tester.pumpAndSettle();

      expect(rig.prompts, ['https://a.example']);
      expect(
        rig.composer.richText.entities.single.kind,
        const EntityKind.link('https://b.example'),
      );
      expect(rig.selection, const TextSelection.collapsed(offset: 1));
    }, variant: _both);

    testWidgets('a right click beside the link offers Create link', (
      tester,
    ) async {
      final rig = await _Rig.pump(
        tester,
        text: linked,
        selection: const TextSelection.collapsed(offset: 1),
      );
      await rig.rightClick(rig.over(1));
      await rig.hover(ComposerMenuAction.formatting);

      expect(rig.row(ComposerMenuAction.createLink), findsOneWidget);
      expect(rig.row(ComposerMenuAction.editLink), findsNothing);
    }, variant: _both);

    testWidgets('Remove link takes the link off the pointer\'s link', (
      tester,
    ) async {
      final rig = await _Rig.pump(
        tester,
        text: linked,
        selection: const TextSelection.collapsed(offset: 1),
      );
      await rig.rightClick(rig.over(7));
      await rig.hover(ComposerMenuAction.formatting);

      await rig.choose(ComposerMenuAction.removeLink);

      expect(rig.composer.richText, const RichText.plain('go to site now'));
    }, variant: _both);
  });

  group('spelling', () {
    testWidgets('without a checker there is no Spelling row', (tester) async {
      final rig = await _Rig.pump(tester, text: const RichText.plain('helo'));
      await rig.rightClick(rig.over(1));

      expect(rig.row(ComposerMenuAction.spelling), findsNothing);
    }, variant: _both);

    testWidgets('a wrong word under the pointer puts Spelling on top', (
      tester,
    ) async {
      final checker = _Fake({
        'helo': const ComposerWordSpelling(
          isCorrect: false,
          suggestions: ['hello'],
        ),
      });
      final rig = await _Rig.pump(
        tester,
        text: const RichText.plain('helo world'),
        spellChecker: checker,
        atTop: true,
      );
      await rig.rightClick(rig.over(1));

      final spelling = tester.getRect(rig.row(ComposerMenuAction.spelling));
      expect(spelling.top, tester.getTopLeft(_Rig.panel).dy + 8);

      await rig.hover(ComposerMenuAction.spelling);
      await rig.choose(const ComposerSuggestionId('hello'));
      expect(rig.composer.text.text, 'hello world');
    }, variant: _both);

    testWidgets('a number is not asked about', (tester) async {
      final checker = _Fake({});
      final rig = await _Rig.pump(
        tester,
        text: const RichText.plain('12345 world'),
        spellChecker: checker,
      );
      await rig.rightClick(rig.over(1));

      expect(rig.row(ComposerMenuAction.spelling), findsNothing);
    }, variant: _both);

    testWidgets('near the bottom the menu opens upward with Spelling at the '
        'bottom', (tester) async {
      final checker = _Fake({
        'helo': const ComposerWordSpelling(
          isCorrect: false,
          suggestions: ['hello'],
        ),
      });
      final rig = await _Rig.pump(
        tester,
        text: const RichText.plain('helo world'),
        spellChecker: checker,
        size: const Size(900, 360),
      );
      await rig.rightClick(rig.over(1));

      final spelling = tester.getRect(rig.row(ComposerMenuAction.spelling));
      final all = tester.getRect(rig.row(ComposerMenuAction.selectAll));
      expect(spelling.top, greaterThan(all.top));
    }, variant: _both);
  });

  group('touch', () {
    testWidgets('a long press on a touch screen still shows the floating '
        'toolbar', (tester) async {
      final rig = await _Rig.pump(
        tester,
        selection: const TextSelection(baseOffset: 4, extentOffset: 7),
      );

      tester
          .state<ExtendedEditableTextState>(find.byType(ExtendedEditableText))
          .showToolbar();
      await tester.pumpAndSettle();

      expect(MenuRig.card, findsOneWidget);
      expect(rig.isOpen(), isFalse);
    }, variant: _both);
  });
}

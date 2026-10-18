import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_pages.dart';
import 'package:chat_composer/src/menu/selection_menu_shell.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import 'composer_harness.dart';

/// A composer with the selection menu showing over a selection.
///
/// The menu is what [ComposerView]'s field mounts on `showToolbar`; the rig
/// drives it the way the platform does and hands back the pieces a test reads.
final class MenuRig {
  MenuRig._(this.tester, this.composer);

  final WidgetTester tester;

  /// The composer's input state.
  final ComposerController composer;

  /// The editable under the menu.
  ExtendedEditableTextState get editable => tester
      .state<ExtendedEditableTextState>(find.byType(ExtendedEditableText));

  /// The menu's card, or nothing while none is up.
  static Finder get card => find.byType(SelectionMenuCard);

  /// The item of [kind], wherever it is built.
  static Finder item(SelectionMenuItemKind kind) =>
      find.byKey(ValueKey<SelectionMenuItemKind>(kind));

  /// The More button of the main row.
  static Finder get more => find.byKey(SelectionMenuRootPage.moreKey);

  /// The Back tile of the More page.
  static Finder get back => find.byKey(SelectionMenuMorePage.backKey);

  /// The card's size.
  Size get cardSize => tester.getSize(card);

  /// Whether the More page is the one showing.
  bool get isOpen => back.hitTestable().evaluate().isNotEmpty;

  /// The opacity the editable's toolbar wrapper gives the menu: its fade for
  /// a scroll or a selection out of view.
  double get wrapperOpacity => tester
      .widgetList<FadeTransition>(
        find.ancestor(of: card, matching: find.byType(FadeTransition)),
      )
      .fold(1, (product, fade) => product * fade.opacity.value);

  /// The opacity of the menu's own enter and leave.
  double get cardOpacity => tester
      .widgetList<Opacity>(
        find.ancestor(of: card, matching: find.byType(Opacity)),
      )
      .fold(1, (product, opacity) => product * opacity.opacity);

  /// The card's opacity as the user sees it: both fades multiplied.
  double get opacity => wrapperOpacity * cardOpacity;

  /// Scrolls the More page until [kind] shows and taps it.
  Future<void> tapItem(SelectionMenuItemKind kind) async {
    var finder = item(kind);
    if (finder.hitTestable().evaluate().isEmpty && more.evaluate().isNotEmpty) {
      if (!isOpen) await openMore();
    }
    if (finder.hitTestable().evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        42,
        scrollable: find
            .descendant(of: card, matching: find.byType(Scrollable))
            .first,
      );
      finder = item(kind);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }
    await tester.tap(finder.hitTestable());
    await settle();
  }

  /// Lets everything the menu does after a choice run out.
  Future<void> settle() async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
  }

  /// Opens the More page and lets it settle.
  Future<void> openMore() async {
    await tester.tap(more);
    await tester.pumpAndSettle();
  }

  /// Pumps a composer holding [text] with [selection] chosen, shows the toolbar
  /// and, unless [enter] is false, lets it come in.
  static Future<MenuRig> show(
    WidgetTester tester, {
    RichText text = const RichText.plain('one two three four'),
    TextSelection selection = const TextSelection(
      baseOffset: 4,
      extentOffset: 7,
    ),
    ComposerSpec? spec,
    ComposerController? controller,
    FakeRichClipboard? clipboard,
    TextDirection textDirection = TextDirection.ltr,
    Brightness brightness = Brightness.light,
    ChromeMotionSpeed? motionSpeed,
    ChromeStrings? strings,
    Locale? locale,
    Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates,
    Size? size,
    bool enter = true,
  }) async {
    if (size != null) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    final composer = controller ?? ComposerController(clipboard: clipboard);
    if (controller == null) addTearDown(composer.dispose);
    await tester.pumpWidget(
      composerHarness(
        ComposerView(
          controller: composer,
          spec: spec ?? ComposerSpec(linkPrompt: (context, _) async => null),
          shortcuts: const ComposerShortcutPolicy.desktop().shortcuts,
        ),
        textDirection: textDirection,
        brightness: brightness,
        motionSpeed: motionSpeed,
        strings: strings,
        locale: locale,
        localizationsDelegates: localizationsDelegates,
      ),
    );
    composer
      ..requestFocus()
      ..restore(text, selection: selection);
    await tester.pump();
    final rig = MenuRig._(tester, composer);
    rig.editable.showToolbar();
    await tester.pump();
    if (enter) await tester.pumpAndSettle();
    return rig;
  }
}

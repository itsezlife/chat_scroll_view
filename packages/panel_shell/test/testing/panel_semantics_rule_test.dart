import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

ChromeStrings stringsWith({
  String Function(String)? tabLabel,
  String? searchFieldLabel,
}) {
  final base = ChromeStringsPresets.english;
  return ChromeStrings(
    panel: PanelStrings(
      tabLabel: tabLabel ?? base.panel.tabLabel,
      categoryTitle: base.panel.categoryTitle,
      recentlyUsedTitle: base.panel.recentlyUsedTitle,
      searchResultsTitle: base.panel.searchResultsTitle,
      searchHint: base.panel.searchHint,
      searchEmpty: base.panel.searchEmpty,
      clearRecentsTitle: base.panel.clearRecentsTitle,
      clearRecentsMessage: base.panel.clearRecentsMessage,
      clearAction: base.panel.clearAction,
      cancelAction: base.panel.cancelAction,
      copyAction: base.panel.copyAction,
      removeRecentAction: base.panel.removeRecentAction,
      clearRecentAction: base.panel.clearRecentAction,
      colorAllTitle: base.panel.colorAllTitle,
    ),
    composer: base.composer,
    formatting: base.formatting,
    semantics: SemanticsStrings(
      panelOpened: base.semantics.panelOpened,
      panelClosed: base.semantics.panelClosed,
      pageSelected: base.semantics.pageSelected,
      searchFieldLabel: searchFieldLabel ?? base.semantics.searchFieldLabel,
      searchResultCount: base.semantics.searchResultCount,
      backspaceAction: base.semantics.backspaceAction,
      variantsAction: base.semantics.variantsAction,
      categoryStripLabel: base.semantics.categoryStripLabel,
    ),
  );
}

void main() {
  final emoji = FakePanelPage(
    'emoji',
    search: true,
    actions: const [PageAction.backspace()],
  ).page;
  final stickers = FakePanelPage('stickers').page;

  group('PanelSemanticsRule', () {
    test('passes when everything resolves to text', () {
      expect(
        PanelSemanticsRule.violations(ChromeStringsPresets.english, [
          emoji,
          stickers,
        ]),
        isEmpty,
      );
      PanelSemanticsRule.expectLabelled(ChromeStringsPresets.russian, [
        emoji,
        stickers,
      ]);
    });

    test('fails for a tab whose label key resolves to nothing', () {
      final strings = stringsWith(
        tabLabel: (key) => key == 'stickers' ? '  ' : key,
      );

      expect(PanelSemanticsRule.violations(strings, [emoji, stickers]), [
        'page "stickers": tab label "stickers" is empty',
      ]);
      expect(
        () => PanelSemanticsRule.expectLabelled(strings, [emoji, stickers]),
        throwsA(isA<TestFailure>()),
      );
    });

    test('fails for an action with an empty label', () {
      final unlabelled = FakePanelPage(
        'gif',
        actions: const [
          PageAction(
            id: 'settings',
            icon: ChromeIconId('settings'),
            semanticLabel: _empty,
          ),
        ],
      ).page;

      expect(
        PanelSemanticsRule.violations(ChromeStringsPresets.english, [
          unlabelled,
        ]),
        ['page "gif": action "settings" has no label'],
      );
    });

    test('fails for a searchable page when the field has no label', () {
      final strings = stringsWith(searchFieldLabel: '');

      expect(PanelSemanticsRule.violations(strings, [emoji, stickers]), [
        'page "emoji": the search field has no label',
      ]);
    });
  });
}

String _empty(ChromeStrings strings) => '';

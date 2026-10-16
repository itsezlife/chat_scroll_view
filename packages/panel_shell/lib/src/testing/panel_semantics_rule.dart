import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/src/page/panel_page.dart';

/// The test rule behind "every page, tab and action carries a semantic
/// label": what the descriptors resolve to must be readable text.
///
/// The types already force a label to be supplied; this checks what the host's
/// strings turn it into, so a missing translation or an empty string fails a
/// test instead of leaving a silent control.
abstract final class PanelSemanticsRule {
  /// Describes each label of [pages] that [strings] resolves to nothing.
  ///
  /// Checks the tab name of every page, the label of every declared action
  /// and, for a page that declares search, the label of the search field.
  /// Empty when everything is labelled.
  static List<String> violations(
    ChromeStrings strings,
    Iterable<PanelPage> pages,
  ) {
    final found = <String>[];
    for (final page in pages) {
      if (strings.panel.tabLabel(page.tab.labelKey).trim().isEmpty) {
        found.add(
          'page "${page.id}": tab label "${page.tab.labelKey}" is empty',
        );
      }
      for (final action in page.capabilities.actions) {
        if (action.semanticLabel(strings).trim().isEmpty) {
          found.add('page "${page.id}": action "${action.id}" has no label');
        }
      }
      if (page.capabilities.search &&
          strings.semantics.searchFieldLabel.trim().isEmpty) {
        found.add('page "${page.id}": the search field has no label');
      }
    }
    return found;
  }

  /// Fails the test when [violations] finds anything.
  static void expectLabelled(ChromeStrings strings, Iterable<PanelPage> pages) {
    final found = violations(strings, pages);
    if (found.isNotEmpty) {
      fail('Unlabelled panel controls:\n${found.join('\n')}');
    }
  }
}

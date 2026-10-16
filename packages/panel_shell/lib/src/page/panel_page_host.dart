import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';
import 'package:panel_shell/src/controller/panel_search_state.dart';
import 'package:panel_shell/src/page/page_controller_registry.dart';
import 'package:panel_shell/src/scroll/page_scroll_activity.dart';

/// A page's whole connection to the shell, handed to its builder.
///
/// Everything flows through typed calls and listenables: the shell reaches
/// into no page state and a page reaches into no shell state. Which page a
/// host speaks for is fixed; the host of a page that is not selected keeps its
/// state readable but its reports (scroll activity, progress, counts) are
/// dropped, because only the selected page drives shared chrome.
abstract interface class PanelPageHost {
  /// The id of the page this host belongs to.
  String get pageId;

  /// The search state the page follows: when to show results, for which query.
  ///
  /// The query survives page switches, so a page that becomes selected while
  /// a search is open finds the current query here and shows its results.
  ValueListenable<PanelSearchState> get search;

  /// Whether this page is the selected one.
  ValueListenable<bool> get isActive;

  /// Signals when the user selects the tab of this page while it is already
  /// selected; pages conventionally scroll to their start.
  Listenable get reselected;

  /// Where the page keeps controllers that outlive its widget.
  PageControllerRegistry get controllers;

  /// Whether the panel is on screen, including while it slides in or out, as
  /// the presentation reported it.
  ///
  /// The pause signal of work that is pointless when nothing is seen, such as
  /// baking glyphs. The same observable for every page.
  ValueListenable<bool> get panelVisible;

  /// Whether the panel is moving in or out, as the presentation reported it.
  ///
  /// The pause signal of work that would drop frames during the motion.
  ValueListenable<bool> get panelOpening;

  /// Reports that the user picked [key] of [kind]; the shell publishes
  /// [ContentPicked] with [source].
  void pick(
    ContentKey key, {
    required SemanticKind kind,
    PickSource source = PickSource.collection,
  });

  /// Reports that the user asked to clear the recents of [kind]; the shell
  /// publishes [ClearRecentsRequested].
  void requestClearRecents(SemanticKind kind);

  /// Withdraws the search field's focus intent, keeping search open: the soft
  /// keyboard goes away so the user can see the results. A page calls it when
  /// the user takes hold of its content.
  ///
  /// Only the selected page is heard.
  void releaseSearchFocus();

  /// Reports what the page's scroll is doing; drives the bottom bar.
  void reportScrollActivity(PageScrollActivity activity);

  /// Reports whether a search for the current query is in flight; the search
  /// field shows progress while [busy].
  void reportSearchProgress({required bool busy});

  /// Reports that a search settled on [count] results; the shell announces it.
  void reportSearchResultCount(int count);
}

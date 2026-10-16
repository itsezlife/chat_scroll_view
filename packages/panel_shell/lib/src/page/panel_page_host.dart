import 'package:content_model/content_model.dart';
import 'package:panel_shell/src/controller/panel_search_state.dart';
import 'package:panel_shell/src/page/page_controller_registry.dart';
import 'package:panel_shell/src/scroll/page_scroll_activity.dart';

/// A page's whole connection to the shell, handed to its builder.
///
/// Everything flows through typed calls and observables: the shell reaches
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
  ValueObservable<PanelSearchState> get search;

  /// Whether this page is the selected one.
  ValueObservable<bool> get isActive;

  /// Signals when the user selects the tab of this page while it is already
  /// selected; pages conventionally scroll to their start.
  Observable get reselected;

  /// Where the page keeps controllers that outlive its widget.
  PageControllerRegistry get controllers;

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

  /// Reports what the page's scroll is doing; drives the bottom bar.
  void reportScrollActivity(PageScrollActivity activity);

  /// Reports whether a search for the current query is in flight; the search
  /// field shows progress while [busy].
  void reportSearchProgress({required bool busy});

  /// Reports that a search settled on [count] results; the shell announces it.
  void reportSearchResultCount(int count);
}

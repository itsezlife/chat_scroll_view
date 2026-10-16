import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/page/panel_page_host.dart';

/// Builds the content of a page below the shell.
///
/// [host] is the page's whole connection to the shell: the search state it
/// must follow, the place to report picks and scroll activity, and the
/// registry that keeps its controllers across presentation switches.
typedef PanelPageBuilder =
    Widget Function(BuildContext context, PanelPageHost host);

/// The **tab descriptor** of a page: how the type tabs name it.
///
/// A descriptor holds semantic ids, never glyphs or text. The shell maps
/// [labelKey] to a string through `ChromeStrings.panel.tabLabel` and [icon]
/// to a painter through the chrome icon registry, so the host owns both
/// language and style.
@immutable
final class PanelTab {
  /// A tab shown as [icon] or as the string [labelKey] resolves to.
  ///
  /// [labelKey] is required because every tab carries a semantic label, even
  /// where it paints an icon only.
  const PanelTab({required this.icon, required this.labelKey})
    : assert(labelKey != '', 'a tab label key must not be empty');

  /// The semantic icon of the tab.
  final ChromeIconId icon;

  /// The key `PanelStrings.tabLabel` resolves to the tab's name.
  final String labelKey;

  @override
  bool operator ==(Object other) =>
      other is PanelTab && other.icon == icon && other.labelKey == labelKey;

  @override
  int get hashCode => Object.hash(icon, labelKey);

  @override
  String toString() => 'PanelTab($icon, $labelKey)';
}

/// A button of the bottom bar's action row, declared by a page.
///
/// The bar shows the actions of the selected page only. Two ids have a meaning
/// of their own: [backspaceId] repeats [BackspaceRequested] while held, and
/// [searchId] opens search; every other id publishes [ActionInvoked].
@immutable
final class PageAction {
  /// An action named [id] (unique within its page) painted as [icon].
  ///
  /// [semanticLabel] is required: it resolves the spoken name of the button
  /// from the chrome strings, because an action has no visible text.
  const PageAction({
    required this.id,
    required this.icon,
    required this.semanticLabel,
    this.repeatOnHold = false,
  }) : assert(id != '', 'an action id must not be empty');

  /// The backspace action: [BackspaceRequested] on tap, repeating while held.
  const PageAction.backspace()
    : id = backspaceId,
      icon = ChromeIconId.backspace,
      semanticLabel = _backspaceLabel,
      repeatOnHold = true;

  /// The search action: opens search mode.
  const PageAction.search()
    : id = searchId,
      icon = ChromeIconId.search,
      semanticLabel = _searchLabel,
      repeatOnHold = false;

  /// Id of the action that publishes [BackspaceRequested].
  static const String backspaceId = 'backspace';

  /// Id of the action that opens search.
  static const String searchId = 'search';

  /// Identity of the action within its page.
  final String id;

  /// The semantic icon the action is painted as.
  final ChromeIconId icon;

  /// Resolves the spoken name of the action from the chrome strings.
  final String Function(ChromeStrings strings) semanticLabel;

  /// Whether holding the control repeats the action.
  final bool repeatOnHold;

  static String _backspaceLabel(ChromeStrings strings) =>
      strings.semantics.backspaceAction;

  static String _searchLabel(ChromeStrings strings) =>
      strings.semantics.searchFieldLabel;

  @override
  bool operator ==(Object other) =>
      other is PageAction &&
      other.id == id &&
      other.icon == icon &&
      other.repeatOnHold == repeatOnHold &&
      other.semanticLabel == semanticLabel;

  @override
  int get hashCode => Object.hash(id, icon, repeatOnHold, semanticLabel);

  @override
  String toString() => 'PageAction($id)';
}

/// What a page declares it can do, which the shell reads to decide what to
/// show around it.
@immutable
final class PageCapabilities {
  /// Capabilities of a page.
  const PageCapabilities({
    this.search = false,
    this.topStrip = false,
    this.actions = const [],
  });

  /// A page that declares nothing: no search field, no strip, no actions.
  static const PageCapabilities none = PageCapabilities();

  /// Whether the page maps the search query to results of its own. The shell
  /// shows its search field only above pages that declare it.
  final bool search;

  /// Whether the page draws a top strip (a category or set strip) inside its
  /// own content. The page owns and positions the strip; this is declared so
  /// a presentation can size around it.
  final bool topStrip;

  /// The action row of the bottom bar while the page is selected.
  final List<PageAction> actions;
}

/// One entry of the open page registry: a stable id, how it is named in the
/// type tabs, how its content is built and what it declares.
///
/// The shell takes an ordered list of pages and never imports a concrete
/// one; adding a kind of content is adding an entry, not editing the shell.
@immutable
final class PanelPage {
  /// A page named [id], shown in the tabs as [tab] and built by [builder].
  const PanelPage({
    required this.id,
    required this.tab,
    required this.builder,
    this.capabilities = PageCapabilities.none,
  }) : assert(id != '', 'a page id must not be empty');

  /// Stable identity of the page: persisted as the selected page and used as
  /// the key of its controllers. Unique within a registry.
  final String id;

  /// How the type tabs name the page.
  final PanelTab tab;

  /// Builds the page's content.
  final PanelPageBuilder builder;

  /// What the page declares it can do.
  final PageCapabilities capabilities;

  @override
  String toString() => 'PanelPage($id)';
}

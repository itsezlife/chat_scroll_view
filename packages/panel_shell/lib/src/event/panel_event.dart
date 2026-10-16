import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// The one outward effect type of the panel: everything the panel asks its
/// host to do or tells it has happened.
///
/// The host listens to `PanelShellController.events` with a single handler and
/// switches over this sealed family. The panel performs none of these
/// effects itself: it inserts nothing into a composer and writes no recents.
/// On [ContentPicked] the host inserts the content and calls
/// `RecentsStore.record`; on [BackspaceRequested] it edits its own input.
///
/// Events are facts about user intent, published after the shell's own state
/// already reflects them, so a handler reading the controller sees the state
/// the event is about.
@immutable
sealed class PanelEvent {
  const PanelEvent();
}

/// The user picked [key] of [kind] from [source].
///
/// The host decides whether the pick counts and reports it to a
/// `RecentsStore` with the same [kind] and [source]; a pick from
/// [PickSource.search] is ignored by the store by contract, so the host may
/// pass every pick through.
final class ContentPicked extends PanelEvent {
  /// A pick of [key], whose semantic kind is [kind], made from [source].
  const ContentPicked({
    required this.key,
    required this.kind,
    this.source = PickSource.collection,
  });

  /// Identity of the picked content.
  final ContentKey key;

  /// The kind recents are filed under.
  final SemanticKind kind;

  /// Where in the page the pick was made: a browsable collection, the recents
  /// list or search results.
  final PickSource source;

  @override
  bool operator ==(Object other) =>
      other is ContentPicked &&
      other.key == key &&
      other.kind == kind &&
      other.source == source;

  @override
  int get hashCode => Object.hash(key, kind, source);

  @override
  String toString() => 'ContentPicked($key, $kind, $source)';
}

/// The user asked to delete the previous character of the host's input.
///
/// Published for a page action that declares itself as the backspace action,
/// once per tap and once per repeat while the control is held.
final class BackspaceRequested extends PanelEvent {
  /// A request to delete one character.
  const BackspaceRequested();

  @override
  bool operator ==(Object other) => other is BackspaceRequested;

  @override
  int get hashCode => (BackspaceRequested).hashCode;

  @override
  String toString() => 'BackspaceRequested()';
}

/// The user invoked the bottom-bar action [actionId] of page [pageId].
///
/// Backspace and search actions have their own effects
/// ([BackspaceRequested], `PanelShellController.openSearch`) and do not
/// arrive here.
final class ActionInvoked extends PanelEvent {
  /// An invocation of the action [actionId] declared by page [pageId].
  const ActionInvoked({required this.pageId, required this.actionId});

  /// The page that declared the action.
  final String pageId;

  /// The action's id, unique within its page.
  final String actionId;

  @override
  bool operator ==(Object other) =>
      other is ActionInvoked &&
      other.pageId == pageId &&
      other.actionId == actionId;

  @override
  int get hashCode => Object.hash(pageId, actionId);

  @override
  String toString() => 'ActionInvoked($pageId, $actionId)';
}

/// The user asked to clear the recents of [kind].
///
/// The panel never clears them: the host confirms with the user if it wants
/// to, then calls `RecentsStore.clear(kind: kind)`.
final class ClearRecentsRequested extends PanelEvent {
  /// A request to clear the recents filed under [kind].
  const ClearRecentsRequested({required this.kind});

  /// The kind of the recents list the user long-pressed.
  final SemanticKind kind;

  @override
  bool operator ==(Object other) =>
      other is ClearRecentsRequested && other.kind == kind;

  @override
  int get hashCode => Object.hash(ClearRecentsRequested, kind);

  @override
  String toString() => 'ClearRecentsRequested($kind)';
}

/// The selected page changed to [pageId].
final class PageChanged extends PanelEvent {
  /// A change of the selected page to [pageId].
  const PageChanged(this.pageId);

  /// The page now selected.
  final String pageId;

  @override
  bool operator ==(Object other) =>
      other is PageChanged && other.pageId == pageId;

  @override
  int get hashCode => Object.hash(PageChanged, pageId);

  @override
  String toString() => 'PageChanged($pageId)';
}

/// Search mode opened.
///
/// A presentation that grows the panel for search, and one that hands the
/// keyboard over, reads this as its signal.
final class SearchOpened extends PanelEvent {
  /// Search mode opened.
  const SearchOpened();

  @override
  bool operator ==(Object other) => other is SearchOpened;

  @override
  int get hashCode => (SearchOpened).hashCode;

  @override
  String toString() => 'SearchOpened()';
}

/// Search mode closed.
final class SearchClosed extends PanelEvent {
  /// Search mode closed.
  const SearchClosed();

  @override
  bool operator ==(Object other) => other is SearchClosed;

  @override
  int get hashCode => (SearchClosed).hashCode;

  @override
  String toString() => 'SearchClosed()';
}

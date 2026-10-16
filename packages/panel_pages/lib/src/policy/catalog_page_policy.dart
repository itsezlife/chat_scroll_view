import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/page/catalog_strip.dart';
import 'package:panel_shell/panel_shell.dart';

/// What a page reports when the user picks a cell.
@immutable
final class CatalogPick {
  /// A pick of [key], whose semantic kind is [kind], made from [source].
  const CatalogPick({
    required this.key,
    required this.kind,
    required this.source,
  });

  /// Identity of the picked content.
  final ContentKey key;

  /// The kind recents are filed under.
  final SemanticKind kind;

  /// Where in the page the pick was made.
  final PickSource source;

  @override
  bool operator ==(Object other) =>
      other is CatalogPick &&
      other.key == key &&
      other.kind == kind &&
      other.source == source;

  @override
  int get hashCode => Object.hash(key, kind, source);

  @override
  String toString() => 'CatalogPick($key, $kind, $source)';
}

/// One entry of a context menu a policy offers for a cell.
///
/// Declarative on purpose: the policy says what the menu holds and, when an
/// item is chosen, is asked what it does ([CatalogPagePolicy.onMenuAction]);
/// the page draws the menu and owns its focus, keys and hold on auto-hide.
@immutable
sealed class CatalogMenuEntry {
  const CatalogMenuEntry();

  /// An item the user can choose; see [CatalogMenuItem].
  const factory CatalogMenuEntry.item({
    required String id,
    required String label,
    bool attention,
  }) = CatalogMenuItem;

  /// A line between two groups of items; see [CatalogMenuSeparator].
  const factory CatalogMenuEntry.separator() = CatalogMenuSeparator;
}

/// A choosable item of a context menu.
final class CatalogMenuItem extends CatalogMenuEntry {
  /// An item [label]led, answered by [id] when chosen.
  const CatalogMenuItem({
    required this.id,
    required this.label,
    this.attention = false,
  });

  /// Names the item to [CatalogPagePolicy.onMenuAction]; unique in its menu.
  final String id;

  /// The text of the item, in the language of the panel strings.
  final String label;

  /// Whether the item is drawn in the attention colour: one that throws
  /// something away.
  final bool attention;

  @override
  bool operator ==(Object other) =>
      other is CatalogMenuItem &&
      other.id == id &&
      other.label == label &&
      other.attention == attention;

  @override
  int get hashCode => Object.hash(id, label, attention);

  @override
  String toString() => 'CatalogMenuItem($id, $label)';
}

/// A separator line between two groups of items.
final class CatalogMenuSeparator extends CatalogMenuEntry {
  /// A separator.
  const CatalogMenuSeparator();

  @override
  bool operator ==(Object other) => other is CatalogMenuSeparator;

  @override
  int get hashCode => (CatalogMenuSeparator).hashCode;

  @override
  String toString() => 'CatalogMenuSeparator()';
}

/// One long press in progress, handed out by the policy at its start.
///
/// The page forwards the rest of the gesture to it and ends it when the
/// gesture does, or when the page goes away first. What a long press shows (a
/// variant picker, a sticker preview) is the session's business; the page only
/// carries the gesture to it.
///
/// A session may outlive the gesture: one that stays up after the button is
/// released (a picker that waits for the next click) keeps [isOpen] true until
/// it closes itself. The page keeps the cell the session belongs to pinned
/// (hover wash held, wheel locked) for as long as it is open.
abstract interface class CatalogLongPressSession {
  /// Whether the session still shows something; false once it is over, by a
  /// choice, a dismissal or [cancel].
  ValueListenable<bool> get isOpen;

  /// The finger moved.
  void update(LongPressMoveUpdateDetails details);

  /// The finger lifted. The session is over.
  void end(LongPressEndDetails details);

  /// The gesture was interrupted: the page left the tree, its snapshot dropped
  /// the cell, or another long press began. The session is over.
  void cancel();
}

/// What makes one kind of content (emoji, stickers, GIFs) a page: the
/// decisions a [CatalogPage] does not make for it.
///
/// A page scaffold turns [Collection]s into a catalogue, loads them as they
/// come near, searches, reports and forwards; a policy answers the questions
/// whose answer depends on the kind of content. Every method has a default
/// that suits a plain grid of described content, so a kind overrides only what
/// differs, and a page is a thin composition of a source and a policy.
///
/// Methods are pure functions of their arguments: the scaffold calls them
/// whenever it rebuilds the catalogue and may call them in any order and
/// repeatedly. A policy keeps no state a call depends on. `strings` are the
/// panel strings of the host's language at the time of the call.
///
/// ## Section identity
///
/// Each collection becomes one section whose id is [sectionIdOf]. The id is
/// the first half of a cell's identity (`CatalogLeafHit.sectionId`), so it
/// stays the same for the same collection across rebuilds.
abstract class CatalogPagePolicy {
  /// A policy with every default.
  const CatalogPagePolicy();

  // --- What the page declares -----------------------------------------------

  /// What the page declares to the shell: whether it maps the search query, has
  /// a top strip, and which bottom-bar actions it offers.
  ///
  /// Read when the page is registered (`PanelPage.capabilities`), before any
  /// widget exists.
  PageCapabilities get capabilities => PageCapabilities.none;

  // --- From collections to sections -----------------------------------------

  /// The collections shown while browsing, from everything [all] the source
  /// publishes, in display order.
  ///
  /// [searchOpen] is true while the shell's search is open with an empty
  /// query, when a page may show less (frequently used content only). It is
  /// never true under an arrangement that keeps the whole catalogue on screen
  /// with the field (`PanelArrangement.narrowsEmptySearch`), so clearing the
  /// text is all it takes to see the grid. The default shows everything.
  List<Collection> visibleCollections(
    List<Collection> all, {
    required bool searchOpen,
  }) => all;

  /// The id of the section that shows [collection].
  ///
  /// The default is the collection id's own text, which is unique within a
  /// source.
  String sectionIdOf(Collection collection) => collection.id.toString();

  /// The title painted in the section header.
  ///
  /// The default is the collection's own title, the panel strings' title for
  /// recents and for search results, and empty otherwise.
  String titleOf(Collection collection, PanelStrings strings) =>
      switch (collection.id) {
        CollectionId$Query() => strings.searchResultsTitle,
        CollectionId$WellKnown(:final list) when list == WellKnownList.recent =>
          strings.recentlyUsedTitle,
        _ => collection.metadata.title ?? '',
      };

  /// The geometry of the section, or null for the viewport's defaults.
  SectionLayout? layoutOf(Collection collection) => null;

  /// The box the section's content is drawn in, or null for what each cell's
  /// facts say.
  CatalogContentBox? contentBoxOf(Collection collection) => null;

  /// The stand-in of the section's cells, or null for what each cell's facts
  /// say.
  CatalogPlaceholderStyle? placeholderStyleOf(Collection collection) => null;

  /// How many skeleton cells the section paints while its collection loads or
  /// failed to, or null for one row.
  int? skeletonCountOf(Collection collection) => null;

  /// The message painted when the collection is loaded and empty, or null for
  /// the header alone.
  ///
  /// The default is the panel strings' text for empty search results.
  String? emptyMessageOf(Collection collection, PanelStrings strings) =>
      switch (collection.id) {
        CollectionId$Query() => strings.searchEmpty,
        _ => null,
      };

  /// The trailing action of the section's header, or null for a title alone.
  ///
  /// Its label and semantic label are in the language of [strings]. Under an
  /// [arrangement] that [PanelArrangement.usesContextMenu] a page may leave an
  /// action to its context menu instead.
  CatalogSectionAction? actionOf(
    Collection collection,
    PanelStrings strings, {
    PanelArrangement arrangement = PanelArrangement.touch,
  }) => null;

  /// The tag the default [leafOf] attaches to the cell of [item]: the host's
  /// opaque data, excluded from the cell's equality and never painted.
  Object? tagOf(CollectionItem item, Collection collection) => null;

  /// The cell for [item] of [collection].
  ///
  /// The default builds it from the item's descriptor when it has one, from the
  /// glyph for a bare unicode key, and from the key alone otherwise.
  CatalogLeaf leafOf(CollectionItem item, Collection collection) {
    final tag = tagOf(item, collection);
    final descriptor = item.descriptor;
    if (descriptor != null) {
      return CatalogLeaf.fromDescriptor(descriptor, tag: tag);
    }
    return switch (item.key) {
      ContentKey$Unicode(:final sequence) => CatalogLeaf.unicode(
        sequence,
        tag: tag,
      ),
      final key => CatalogLeaf(key: key, tag: tag),
    };
  }

  // --- Interaction ----------------------------------------------------------

  /// What a tap on [hit], a cell of [collection], picks; null for no pick.
  ///
  /// [searching] is true while the page shows search results. The default picks
  /// the cell's content under its own kind, from search when [searching], from
  /// recents for the recents collection and from a collection otherwise.
  CatalogPick? pickOf(
    CatalogLeafHit hit,
    Collection collection, {
    required bool searching,
  }) => CatalogPick(
    key: hit.leaf.key,
    kind: hit.leaf.semanticKind,
    source: searching
        ? PickSource.search
        : collection.id == CollectionId.recent
        ? PickSource.recents
        : PickSource.collection,
  );

  /// The entries of the context menu a secondary click on [hit], a cell of
  /// [collection], opens, in the language of [strings]; empty for no menu (the
  /// click then does nothing at all).
  ///
  /// Asked only under an [arrangement] that [PanelArrangement.usesContextMenu]
  /// answers true for; the default has no menu.
  List<CatalogMenuEntry> menuOf(
    CatalogLeafHit hit,
    Collection collection,
    PanelStrings strings, {
    required PanelArrangement arrangement,
  }) => const [];

  /// The user chose the menu item [itemId] of the menu [menuOf] built for
  /// [hit]. [host] is the page's connection to the shell, where an item that
  /// asks the host something answers.
  void onMenuAction(
    CatalogLeafHit hit,
    Collection collection,
    String itemId,
    PanelPageHost host,
  ) {}

  /// How long a press on [hit] by a pointer of [kind] must last to be a long
  /// press, or null for the platform's timeout.
  ///
  /// Asked only where [hasLongPress] answered true. [Duration.zero] opens the
  /// long press as the press lands.
  Duration? longPressDelayOf(
    CatalogLeafHit hit,
    Collection collection,
    PointerDeviceKind kind,
  ) => null;

  /// Whether a long press on [hit] does anything.
  ///
  /// A cell that answers false keeps tap only, so a tap is not delayed by a
  /// press that would do nothing. Asked for every cell a press starts on.
  bool hasLongPress(CatalogLeafHit hit, Collection collection) => false;

  /// Begins the long press on [hit], or returns null to decline it.
  ///
  /// Only called where [hasLongPress] answered true. [context] is the page's.
  /// [kind] is the pointer that pressed, and [cellBounds] and [viewportBounds]
  /// the pressed cell and the catalogue's box in global coordinates, so a
  /// surface can be placed against both.
  CatalogLongPressSession? beginLongPress(
    BuildContext context,
    CatalogLeafHit hit,
    Collection collection,
    LongPressStartDetails details, {
    required PointerDeviceKind kind,
    required Rect cellBounds,
    required Rect viewportBounds,
  }) => null;

  /// The user tapped the header action [actionId] of [collection]'s section.
  ///
  /// [host] is the page's connection to the shell, where an action that asks
  /// the host something answers (for example `host.requestClearRecents`).
  void onSectionAction(
    Collection collection,
    String actionId,
    PanelPageHost host,
  ) {}

  // --- Chrome inside the page -----------------------------------------------

  /// Whether the strip is pinned at the bottom of the page, below the
  /// catalogue, rather than over it at the top. Asked per [arrangement]: a page
  /// that answers true for one reports the strip's extent to the shell
  /// (`PanelPageHost.reportBottomExtent`), so floating chrome stays above it.
  /// The default keeps the strip on top.
  ///
  /// A strip at the bottom is a fixed part of the page's column: it neither
  /// slides away nor is measured by [stripExtent].
  bool stripAtBottom(PanelArrangement arrangement) => false;

  /// The height of the strip [buildStrip] builds where it is on top (where
  /// [stripAtBottom] is false), or 0 for a policy with none.
  ///
  /// The page draws that strip over the catalogue and pads the catalogue by this
  /// much, so the strip's own layout must be exactly this tall.
  double get stripExtent => 0;

  /// The strip (a category or set strip) shown with the catalogue while
  /// browsing, or null for none: over the top of it, or below it where
  /// [stripAtBottom].
  ///
  /// The page owns the strip: [strip] gives it the sections to show and the
  /// jump to one. It reads the arrangement it is drawn for from
  /// `PanelArrangementScope`. At the top it slides away as the user reads on
  /// and returns as they read back, and it is not part of the page while search
  /// is open or results are shown; at the bottom it stays, and only results
  /// take it away.
  Widget? buildStrip(BuildContext context, CatalogStripHandle strip) => null;
}

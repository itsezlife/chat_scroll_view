import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/emoji/emoji_category_strip.dart';
import 'package:panel_pages/src/emoji/emoji_tab_icons.dart';
import 'package:panel_pages/src/emoji/emoji_variant_picker.dart';
import 'package:panel_pages/src/page/catalog_strip.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_shell/panel_shell.dart';

/// What the emoji page knows about an emoji beyond its key: the entry the key
/// is the base or a variant of, or null for a key the catalogue does not hold.
///
/// The one answer the grid, the variant picker and search share, so they
/// cannot disagree about which emoji have variants. The emoji data layer
/// supplies it (`EmojiCollectionSource.entryOf`); this package never reads
/// the catalogue itself.
typedef EmojiEntryOf = EmojiEntry? Function(ContentKey key);

/// The decisions that make a catalogue page the emoji page.
///
/// - **Geometry.** Eight columns of [cellPitch] rows under a [headerExtent]
///   header, for the categories and the search results alike. Emoji are drawn
///   in the glyph box of the cell ([glyphBoxExtent]), which is also the size
///   the glyph atlas is baked for.
/// - **Sections.** One per category with the title the panel strings give the
///   category; the recents first, only while there are some. While search is
///   open with no query the page narrows to the recents (frequently used
///   emoji) when there are any.
/// - **Recents.** A header action asks the host to clear them
///   (`PanelPageHost.requestClearRecents`); the page never clears or records
///   anything itself.
/// - **Variants.** A long press on an emoji the catalogue holds variants for
///   opens the variant picker; releasing on an option picks it and remembers
///   it for the emoji's base through the `PreferenceStore`, so the grid shows
///   it from then on. An emoji with no variants has no long press.
/// - **Strip.** The category strip above the catalogue ([stripReady] defers
///   it).
final class EmojiPagePolicy extends CatalogPagePolicy {
  /// The emoji policy of the page behind [host].
  ///
  /// [entryOf] answers the catalogue's variants. [preferences] keeps the
  /// variant a user chose per base. [stripReady] gates the category strip: a
  /// page that mounts its chrome one frame at a time passes a listenable
  /// that turns true when the strip may mount; null mounts it at once.
  EmojiPagePolicy({
    required this.host,
    required this.entryOf,
    required this.preferences,
    this.stripReady,
  });

  /// What the page declares to the shell: search, placed inline among the
  /// content so it scrolls away with it and pins when search opens; a top
  /// strip; and backspace.
  static const PageCapabilities pageCapabilities = PageCapabilities(
    search: true,
    searchPlacement: SearchPlacement.inline,
    topStrip: true,
    actions: [PageAction.backspace()],
  );

  /// Columns of the grid.
  static const int columns = 8;

  /// Row height and nominal cell width of the grid.
  static const double cellPitch = 45;

  /// Height of a section header.
  static const double headerExtent = 27;

  /// The id of the header action that clears the recents.
  static const String clearRecentsActionId = 'clear-recents';

  /// The side of the box an emoji is drawn in: what a glyph atlas for this
  /// page is baked for.
  static final double glyphBoxExtent = catalogGlyphBoxExtent(
    cellPitch,
    cellPitch,
  );

  static const SectionLayout _layout = SectionLayout.grid(
    spanCount: columns,
    cellExtent: cellPitch,
    headerExtent: headerExtent,
  );

  /// The page's connection to the shell.
  final PanelPageHost host;

  /// The catalogue's answer for a key.
  final EmojiEntryOf entryOf;

  /// Where the chosen variants are kept.
  final PreferenceStore preferences;

  /// Whether the strip may mount; null for always.
  final listen.ValueListenable<bool>? stripReady;

  @override
  PageCapabilities get capabilities => pageCapabilities;

  // --- Sections -------------------------------------------------------------

  @override
  List<Collection> visibleCollections(
    List<Collection> all, {
    required bool searchOpen,
  }) {
    final recents = [
      for (final collection in all)
        if (collection.id == CollectionId.recent && _hasItems(collection))
          collection,
    ];
    if (searchOpen && recents.isNotEmpty) return recents;
    return [
      for (final collection in all)
        if (collection.id != CollectionId.recent || recents.isNotEmpty)
          collection,
    ];
  }

  static bool _hasItems(Collection collection) => switch (collection.contents) {
    CollectionContents$Loaded(:final items) => items.isNotEmpty,
    _ => false,
  };

  @override
  String titleOf(Collection collection, PanelStrings strings) =>
      switch (collection.id) {
        CollectionId$Category(:final id) => strings.categoryTitle(id),
        _ => super.titleOf(collection, strings),
      };

  @override
  SectionLayout? layoutOf(Collection collection) => _layout;

  @override
  CatalogSectionAction? actionOf(Collection collection, PanelStrings strings) =>
      collection.id == CollectionId.recent
      ? CatalogSectionAction(
          id: clearRecentsActionId,
          label: strings.clearAction,
          semanticLabel: strings.clearRecentsTitle,
        )
      : null;

  @override
  void onSectionAction(
    Collection collection,
    String actionId,
    PanelPageHost host,
  ) {
    if (actionId == clearRecentsActionId &&
        collection.id == CollectionId.recent) {
      host.requestClearRecents(SemanticKind.unicodeEmoji);
    }
  }

  // --- Variants -------------------------------------------------------------

  @override
  bool hasLongPress(CatalogLeafHit hit, Collection collection) =>
      _variantsOf(hit.leaf.key) != null;

  EmojiEntry? _variantsOf(ContentKey key) => switch (entryOf(key)) {
    final entry? when entry.variants.isNotEmpty => entry,
    _ => null,
  };

  @override
  CatalogLongPressSession? beginLongPress(
    BuildContext context,
    CatalogLeafHit hit,
    Collection collection,
    LongPressStartDetails details,
  ) {
    final key = hit.leaf.key;
    if ((_variantsOf(key), key) case (
      final EmojiEntry entry,
      final ContentKey$Unicode initial,
    )) {
      return EmojiVariantSession.show(
        context: context,
        options: emojiVariantOptions(entry),
        initial: initial,
        anchor: details.globalPosition,
        onChosen: (chosen) => _choose(entry, chosen, collection),
      );
    }
    return null;
  }

  void _choose(
    EmojiEntry entry,
    ContentKey$Unicode chosen,
    Collection collection,
  ) {
    // A pick from the recents is the exact emoji that was used; it says
    // nothing new about what the user prefers.
    if (collection.id != CollectionId.recent) {
      unawaited(_remember(entry.base, chosen == entry.base ? null : chosen));
    }
    host.pick(
      chosen,
      kind: SemanticKind.unicodeEmoji,
      source: switch (collection.id) {
        CollectionId$Query() => PickSource.search,
        _ when collection.id == CollectionId.recent => PickSource.recents,
        _ => PickSource.collection,
      },
    );
  }

  Future<void> _remember(
    ContentKey$Unicode base,
    ContentKey$Unicode? variant,
  ) async {
    try {
      await preferences.setPreferredVariant(base, variant);
    } on Object catch (error, stack) {
      // The choice stays in memory; failing to persist it must not undo the
      // pick the user just made.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'panel_pages',
          context: ErrorDescription('while remembering a chosen variant'),
        ),
      );
    }
  }

  // --- Chrome ---------------------------------------------------------------

  @override
  double get stripExtent => EmojiCategoryStrip.height;

  @override
  Widget? buildStrip(BuildContext context, CatalogStripHandle strip) {
    final gate = stripReady;
    if (gate == null) return _strip(strip);
    return _StripGate(ready: gate, strip: () => _strip(strip));
  }

  Widget _strip(CatalogStripHandle strip) =>
      EmojiTabIconScope(child: EmojiCategoryStrip(handle: strip));
}

// Holds the strip's place until the page lets it mount, so the grid does not
// move when it arrives.
class _StripGate extends StatefulWidget {
  const _StripGate({required this.ready, required this.strip});

  final listen.ValueListenable<bool> ready;
  final Widget Function() strip;

  @override
  State<_StripGate> createState() => _StripGateState();
}

class _StripGateState extends State<_StripGate> {
  @override
  void initState() {
    super.initState();
    widget.ready.addListener(_onReady);
  }

  @override
  void didUpdateWidget(_StripGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.ready, widget.ready)) {
      oldWidget.ready.removeListener(_onReady);
      widget.ready.addListener(_onReady);
    }
  }

  @override
  void dispose() {
    widget.ready.removeListener(_onReady);
    super.dispose();
  }

  void _onReady() => setState(() {});

  @override
  Widget build(BuildContext context) => widget.ready.value
      ? widget.strip()
      : const SizedBox(
          height: EmojiCategoryStrip.height,
          width: double.infinity,
        );
}

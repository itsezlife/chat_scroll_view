import 'dart:async';
import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart'
    show AssetCacheScope, TextGlyphProducer;
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/emoji/emoji_category_strip.dart';
import 'package:panel_pages/src/emoji/emoji_tab_icons.dart';
import 'package:panel_pages/src/emoji/emoji_tone_picker.dart';
import 'package:panel_pages/src/emoji/emoji_variant_picker.dart';
import 'package:panel_pages/src/page/catalog_strip.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_pages/src/theme/chrome_catalog_theme.dart';
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
/// - **Geometry.** Under the touch arrangement eight columns of [cellPitch]
///   rows under a [headerExtent] header, for the categories and the search
///   results alike. Under the pointer arrangement the reference desktop
///   client's grid: as many columns of at least [pointerDesiredCellWidth] as
///   the width holds, whole pixels wide, each row [pointerCellHeightInset]
///   shorter, so a dock that is dragged wider or narrower gains or loses
///   columns at once. Under touch an emoji is drawn in the glyph box of the
///   cell; under the pointer at [pointerGlyphSize], centred, whatever the
///   width gives the cell, as the reference desktop client draws it. The
///   atlas is baked for the larger of the two ([glyphBoxExtent]).
/// - **Sections.** One per category with the title the panel strings give the
///   category; the recents first, only while there are some. Search open with
///   no query changes none of it: the reference clients keep the whole
///   catalogue on screen until there is something to look for.
/// - **Recents.** One list for the page, filed under [recentsKind]: every
///   pick is recorded there, custom emoji (document keys) among the unicode
///   ones, as the reference clients keep one list. The header is a title,
///   with no button. A finger's long press
///   on an emoji of the recents asks the host to clear them
///   (`PanelPageHost.requestClearRecents`), instead of the variant picker.
///   Under a pointer a right click on one opens a menu (copy, remove from
///   recent, clear recent) whose items ask the host the same way. The page
///   never clears, removes, copies or records anything itself, and a right
///   click anywhere else opens nothing.
/// - **Variants.** A long press on an emoji the catalogue holds variants for
///   opens the variant picker; releasing on an option picks it and remembers
///   it for the emoji's base through the `PreferenceStore`, the base itself
///   included (that the user chose is what the next press asks), so the grid
///   shows it from then on. An emoji with no variants has no long press.
///   Under a mouse the picker opens after a [pointerHoldDelay] hold, whether
///   or not a variant was ever chosen, and a release before then picks the
///   emoji as the grid shows it: a click is always a pick. (The reference
///   desktop client opens it on the press for an emoji never chosen; a click
///   that inserts nothing read as a bug.) A finger or stylus keeps the
///   platform's long-press delay.
/// - **Strip.** The category strip above the catalogue, or pinned below it
///   under the pointer arrangement ([stripReady] defers it).
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
    this.assets,
    this.stripLayout = EmojiStripLayout.automatic,
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

  /// The kind every pick of the page is filed under: the page's one recents
  /// list, custom emoji included. It names the list, in a pick's
  /// `recentsKind` and in requests to remove from or clear it; a pick's
  /// `kind` and a request to copy carry the content's own kind.
  static const SemanticKind recentsKind = SemanticKind.unicodeEmoji;

  /// The id of the context menu item that copies the emoji.
  static const String copyItemId = 'copy';

  /// The id of the context menu item that forgets the emoji in the recents.
  static const String removeRecentItemId = 'remove-recent';

  /// The id of the context menu item that clears the recents.
  static const String clearRecentItemId = 'clear-recent';

  /// The id of the Smileys & People header's action, which chooses one tone
  /// for every emoji.
  static const String colorAllActionId = 'color-all';

  /// The category whose header carries [colorAllActionId].
  static const CollectionId colorAllSection = CollectionId.category('people');

  // The emoji the tone-for-all picker offers: the waving hand, as it is and in
  // each tone, as the reference desktop client offers it.
  static final List<(ContentKey$Unicode, EmojiModifiers)> _colorAllOptions = [
    (const ContentKey$Unicode('\u{1F44B}'), EmojiModifiers.none),
    for (final (i, tone) in SkinTone.values.indexed)
      (
        ContentKey$Unicode('\u{1F44B}${String.fromCharCode(0x1F3FB + i)}'),
        EmojiModifiers(tones: [tone]),
      ),
  ];

  /// How long a mouse holds a press on an emoji whose variant the user has
  /// chosen before the picker opens: the reference client's 500 ms.
  static const Duration pointerHoldDelay = Duration(milliseconds: 500);

  /// The side of the box an emoji is drawn in: what a glyph atlas for this
  /// page is baked for.
  static final double glyphBoxExtent = CatalogContentBox.glyphBoxExtent(
    cellPitch,
    cellPitch,
  );

  static const SectionLayout _layout = SectionLayout.grid(
    spanCount: columns,
    cellExtent: cellPitch,
    headerExtent: headerExtent,
  );

  /// The narrowest a column of the pointer grid is: the reference desktop
  /// client's emoji list, whose columns are as many as fit at this width.
  static const double pointerDesiredCellWidth = 37;

  /// How much shorter than it is wide a row of the pointer grid is.
  static const double pointerCellHeightInset = 2;

  /// The size an emoji is drawn at under the pointer, at every width: the
  /// reference desktop client's large emoji (24 logical pixels, the art
  /// filling its square, as a colour emoji font fills its em).
  static const double pointerGlyphSize = 24;

  static const SectionLayout _pointerLayout = SectionLayout.grid(
    desiredCellWidth: pointerDesiredCellWidth,
    cellHeightInset: pointerCellHeightInset,
    glyphExtent: pointerGlyphSize / TextGlyphProducer.defaultFontScale,
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

  /// Where the strip draws the covers of packs from; null draws none.
  final AssetCacheScope? assets;

  /// How the strip lays its icons out under the pointer arrangement.
  final EmojiStripLayout stripLayout;

  @override
  PageCapabilities get capabilities => pageCapabilities;

  // --- Sections -------------------------------------------------------------

  @override
  List<Collection> visibleCollections(List<Collection> all) {
    final hasRecents = all.any(
      (collection) =>
          collection.id == CollectionId.recent && _hasItems(collection),
    );
    return [
      for (final collection in all)
        if (collection.id != CollectionId.recent || hasRecents) collection,
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
  SectionLayout? layoutOf(
    Collection collection, {
    PanelArrangement arrangement = PanelArrangement.touch,
  }) => switch (arrangement) {
    PanelArrangement.touch => _layout,
    PanelArrangement.pointer => _pointerLayout,
  };

  // --- Section header -------------------------------------------------------

  /// Under a pointer, the Smileys & People header ends in a button that opens
  /// a picker of one tone for every emoji, as in the reference desktop
  /// client.
  @override
  CatalogSectionAction? actionOf(
    Collection collection,
    PanelStrings strings, {
    PanelArrangement arrangement = PanelArrangement.touch,
  }) => switch ((arrangement, collection.id)) {
    (PanelArrangement.pointer, final id) when id == colorAllSection =>
      CatalogSectionAction(
        id: colorAllActionId,
        painter: _paintToneIcon,
        semanticLabel: strings.colorAllTitle,
      ),
    _ => null,
  };

  // The reference desktop client's tone button: two sliders, the upper one's
  // knob at its right end, the lower one's at its left, stroked in [color].
  static void _paintToneIcon(Canvas canvas, Rect box, Color color) {
    final unit = box.width / 24;
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 * unit
      ..strokeCap = StrokeCap.round;
    Offset at(double x, double y) => box.topLeft + Offset(x, y) * unit;
    const radius = 2.6;
    // One path, stroked once: a line meeting its knob would otherwise be
    // painted twice where they overlap, brighter in a translucent colour.
    final path = Path()
      // Upper slider: a line, then its knob at the right.
      ..moveTo(at(5, 8.5).dx, at(5, 8.5).dy)
      ..lineTo(at(16.5 - radius, 8.5).dx, at(16.5 - radius, 8.5).dy)
      ..addOval(Rect.fromCircle(center: at(16.5, 8.5), radius: radius * unit))
      // Lower slider: its knob at the left, then a line.
      ..addOval(Rect.fromCircle(center: at(7.5, 15.5), radius: radius * unit))
      ..moveTo(at(7.5 + radius, 15.5).dx, at(7.5 + radius, 15.5).dy)
      ..lineTo(at(19, 15.5).dx, at(19, 15.5).dy);
    canvas.drawPath(path, pen);
  }

  /// Opens the tone-for-all picker over the button: the waving hand as it is
  /// and in each tone, under its title. A choice is the default variant of
  /// every emoji ([PreferenceStore.setDefaultVariant], which forgets the
  /// choices made per emoji); nothing is inserted and the recents keep what
  /// was picked.
  @override
  void onSectionAction(
    Collection collection,
    String actionId,
    PanelPageHost host, {
    BuildContext? context,
    Rect? bounds,
    Rect? viewportBounds,
  }) {
    if (actionId != colorAllActionId ||
        context == null ||
        bounds == null ||
        viewportBounds == null) {
      return;
    }
    final strings = ChromeStringsScope.panelOf(context);
    final hold = host.holdAutoHide();
    final options = [for (final (key, _) in _colorAllOptions) key];
    try {
      EmojiVariantSession.show(
        context: context,
        options: options,
        initial: options.first,
        cellBounds: bounds,
        viewportBounds: viewportBounds,
        mode: EmojiVariantPickerMode.pointerHold,
        hold: hold,
        title: strings.colorAllTitle,
        highlightSize: ChromeCatalogTheme.pointerHoverSize,
        glyphExtent: switch (layoutOf(
          collection,
          arrangement: PanelArrangement.pointer,
        )) {
          SectionLayout$Grid(:final glyphExtent) => glyphExtent,
          null => null,
        },
        onChosen: (chosen) {
          for (final (key, modifiers) in _colorAllOptions) {
            if (key == chosen) {
              unawaited(preferences.setDefaultVariant(modifiers));
            }
          }
        },
      );
    } on Object {
      hold.release();
      rethrow;
    }
  }

  // --- Picks ----------------------------------------------------------------

  /// Files every pick under [recentsKind], whatever the cell's own kind, so a
  /// custom emoji lands in the page's recents with the unicode ones; the pick
  /// still says what it is.
  @override
  CatalogPick? pickOf(
    CatalogLeafHit hit,
    Collection collection, {
    required bool searching,
  }) => switch (super.pickOf(hit, collection, searching: searching)) {
    final pick? => CatalogPick(
      key: pick.key,
      kind: pick.kind,
      recentsKind: recentsKind,
      source: pick.source,
    ),
    null => null,
  };

  // --- Context menu ---------------------------------------------------------

  @override
  List<CatalogMenuEntry> menuOf(
    CatalogLeafHit hit,
    Collection collection,
    PanelStrings strings, {
    required PanelArrangement arrangement,
  }) {
    if (!arrangement.usesContextMenu || collection.id != CollectionId.recent) {
      return const [];
    }
    return [
      CatalogMenuEntry.item(id: copyItemId, label: strings.copyAction),
      CatalogMenuEntry.item(
        id: removeRecentItemId,
        label: strings.removeRecentAction,
      ),
      const CatalogMenuEntry.separator(),
      CatalogMenuEntry.item(
        id: clearRecentItemId,
        label: strings.clearRecentAction,
        attention: true,
      ),
    ];
  }

  @override
  void onMenuAction(
    CatalogLeafHit hit,
    Collection collection,
    String itemId,
    PanelPageHost host,
  ) {
    if (collection.id != CollectionId.recent) return;
    const kind = recentsKind;
    switch (itemId) {
      // A copy is of the content, so under its own kind (a custom emoji is
      // not text); removing and clearing name the one list.
      case copyItemId:
        host.requestCopy(hit.leaf.key, kind: hit.leaf.semanticKind);
      case removeRecentItemId:
        host.requestRemoveRecent(hit.leaf.key, kind: kind);
      case clearRecentItemId:
        host.requestClearRecents(kind);
    }
  }

  // --- Variants -------------------------------------------------------------

  // A recent answers every long press: a finger's asks to clear, and the
  // mouse's hold opens the picker for the ones that have variants.
  @override
  bool hasLongPress(CatalogLeafHit hit, Collection collection) =>
      _isRecentEmoji(hit, collection) || _variantsOf(hit.leaf.key) != null;

  static bool _isRecentEmoji(CatalogLeafHit hit, Collection collection) =>
      collection.id == CollectionId.recent;

  EmojiEntry? _variantsOf(ContentKey key) => switch (entryOf(key)) {
    final entry? when entry.variants.isNotEmpty => entry,
    _ => null,
  };

  @override
  Duration? longPressDelayOf(
    CatalogLeafHit hit,
    Collection collection,
    PointerDeviceKind kind,
  ) {
    if (kind != PointerDeviceKind.mouse) return null;
    return _variantsOf(hit.leaf.key) == null ? null : pointerHoldDelay;
  }

  @override
  CatalogLongPressSession? beginLongPress(
    BuildContext context,
    CatalogLeafHit hit,
    Collection collection,
    LongPressStartDetails details, {
    required PointerDeviceKind kind,
    required Rect cellBounds,
    required Rect viewportBounds,
  }) {
    final key = hit.leaf.key;
    // A finger on a recent asks to clear them. The pointer keeps the picker
    // (its menu has the clear item), and a cell with no variants has none.
    if (kind != PointerDeviceKind.mouse && _isRecentEmoji(hit, collection)) {
      host.requestClearRecents(recentsKind);
      return null;
    }
    if ((_variantsOf(key), key) case (
      final EmojiEntry entry,
      final ContentKey$Unicode initial,
    )) {
      // The hold goes up with the picker: the move onto it is the first thing
      // the panel's hover rule hears of.
      final hold = host.holdAutoHide();
      // Anything but a mouse gets the reference mobile client's picker.
      if (kind != PointerDeviceKind.mouse) {
        try {
          return _showTones(
            context,
            entry,
            initial,
            collection,
            details: details,
            cellBounds: cellBounds,
            hold: hold,
          );
        } on Object {
          hold.release();
          rethrow;
        }
      }
      const mode = EmojiVariantPickerMode.pointerHold;
      try {
        return EmojiVariantSession.show(
          context: context,
          options: EmojiVariantPicker.optionsOf(entry),
          initial: initial,
          // The options are the grid's cells, drawn the grid's size.
          // The grid's hover box under the pointer.
          highlightSize: switch (PanelArrangementScope.of(context)) {
            PanelArrangement.pointer => ChromeCatalogTheme.pointerHoverSize,
            PanelArrangement.touch => null,
          },
          glyphExtent: switch (layoutOf(
            collection,
            arrangement: PanelArrangementScope.of(context),
          )) {
            SectionLayout$Grid(:final glyphExtent) => glyphExtent,
            null => null,
          },
          cellBounds: cellBounds,
          viewportBounds: viewportBounds,
          mode: mode,
          hold: hold,
          onChosen: (chosen) => _choose(entry, chosen, collection),
        );
      } on Object {
        hold.release();
        rethrow;
      }
    }
    return null;
  }

  // The touch picker: a row of the emoji as it is and its tones, or, for two
  // people, a row of tones per person whose changes are kept at once.
  EmojiToneSession _showTones(
    BuildContext context,
    EmojiEntry entry,
    ContentKey$Unicode initial,
    Collection collection, {
    required LongPressStartDetails details,
    required Rect cellBounds,
    required PanelPageHold hold,
  }) {
    final compound = entry.variants.any(
      (variant) => variant.modifiers.tones.length > 1,
    );
    // As the reference client: the saved choice is marked, not whatever the
    // cell shows (the recents show what was picked).
    final saved = preferences.preferredVariant(entry.base) ?? initial;
    if (!compound) {
      final options = EmojiVariantPicker.optionsOf(entry);
      return EmojiToneSession.show(
        context: context,
        options: options,
        initial: math.max(0, options.indexOf(saved)),
        cellBounds: cellBounds,
        pressedAt: details.globalPosition,
        hold: hold,
        onChosen: (chosen) => _choose(entry, chosen, collection),
      );
    }
    // Each person's row shows the emoji with both people in that tone: the
    // variant whose people all have it (for two hands, a one-tone sequence).
    ContentKey$Unicode? both(int tone) {
      for (final variant in entry.variants) {
        final tones = variant.modifiers.tones;
        if (tones.isNotEmpty &&
            tones.every((each) => each == SkinTone.values[tone])) {
          return variant.key;
        }
      }
      return null;
    }

    final tones = entry.modifiersOf(saved)?.tones ?? const [];
    return EmojiToneSession.show(
      context: context,
      options: [entry.base],
      initial: 0,
      cellBounds: cellBounds,
      pressedAt: details.globalPosition,
      hold: hold,
      onChosen: (chosen) {},
      rowOptions: [
        for (var row = 0; row < 2; row++)
          [
            for (var tone = 0; tone < SkinTone.values.length; tone++)
              both(tone),
          ],
      ],
      initialRows: tones.length == 2
          ? [tones[0].index, tones[1].index]
          : const [-1, -1],
      onCompound: (rows) {
        final key = rows.every((tone) => tone < 0)
            ? entry.base
            : rows[0] == rows[1]
            ? both(rows[0])
            : entry.keyFor(
                EmojiModifiers(
                  tones: [
                    for (final tone in rows) SkinTone.values[math.max(0, tone)],
                  ],
                ),
              );
        if (key == null || collection.id == CollectionId.recent) return;
        unawaited(preferences.setPreferredVariant(entry.base, key));
      },
    );
  }

  void _choose(
    EmojiEntry entry,
    ContentKey$Unicode chosen,
    Collection collection,
  ) {
    // A pick from the recents is the exact emoji that was used; it says
    // nothing new about what the user prefers.
    if (collection.id != CollectionId.recent) {
      unawaited(_remember(entry.base, chosen));
    }
    host.pick(
      chosen,
      kind: SemanticKind.unicodeEmoji,
      recentsKind: recentsKind,
      source: switch (collection.id) {
        CollectionId$Query() => PickSource.search,
        _ when collection.id == CollectionId.recent => PickSource.recents,
        _ => PickSource.collection,
      },
    );
  }

  // The base is remembered like any variant: choosing the emoji as it is
  // still says the user chose.
  Future<void> _remember(
    ContentKey$Unicode base,
    ContentKey$Unicode variant,
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
  bool stripAtBottom(PanelArrangement arrangement) =>
      arrangement == PanelArrangement.pointer;

  @override
  double get stripExtent => EmojiCategoryStrip.height;

  @override
  Widget? buildStrip(BuildContext context, CatalogStripHandle strip) {
    final gate = stripReady;
    if (gate == null) return _strip(strip);
    return _StripGate(ready: gate, strip: () => _strip(strip));
  }

  Widget _strip(CatalogStripHandle strip) => EmojiTabIconScope(
    child: EmojiCategoryStrip(
      handle: strip,
      assets: assets,
      layout: stripLayout,
    ),
  );
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

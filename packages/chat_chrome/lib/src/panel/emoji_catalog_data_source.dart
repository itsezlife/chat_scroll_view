import 'package:catalog_assets/legacy_shim.dart';
import 'package:chat_chrome/src/legacy_emoji/legacy_emoji.dart';
import 'package:chat_chrome/src/panel/emoji_tab_assets.dart';
import 'package:chat_chrome/src/util/constants.dart';
import 'package:chat_chrome/src/util/logger.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// Host metadata for one projected [CatalogLeaf] in the emoji grid.
///
/// [CatalogLeaf] carries content identity and paint facts only; pick policy and
/// long-press eligibility live here, carried as the leaf's [CatalogLeaf.tag],
/// so [EmojiPage] can wire viewport callbacks without inferring from glyph
/// strings alone.
@immutable
final class EmojiLeafMeta {
  /// Creates metadata for a catalog or recents cell.
  const EmojiLeafMeta({
    required this.pickGlyph,
    required this.isRecent,
    required this.supportsSkinTone,
    required this.pickSource,
  });

  /// Base glyph passed to pick / long-press handlers (skin tone stripped).
  final String pickGlyph;

  /// Whether the leaf belongs to the synthetic recents section.
  final bool isRecent;

  /// Whether long-press opens the skin-tone picker for this base.
  final bool supportsSkinTone;

  /// Pick source when the leaf is chosen from browse (not search mode).
  final EmojiPickSource pickSource;
}

/// Strip chrome for one catalog section (parallel to [CatalogSection] order).
@immutable
final class EmojiCatalogStripTab {
  /// Creates strip metadata for [id] and [icon].
  const EmojiCatalogStripTab({required this.id, required this.icon});

  /// Stable section id (matches [CatalogSection.id]).
  final String id;

  /// Category strip icon asset.
  final EmojiStripIcon icon;
}

/// Snapshot owner for [EmojiPage]: publishes the [CatalogSnapshot] the viewport
/// projects.
///
/// Owns the viewport-facing section list projected from [EmojiDataSource],
/// optional recents, and keyword-search results. Each projected leaf carries its
/// [EmojiLeafMeta] as its tag, so a hit ([CatalogLeafHit]) names the policy of
/// the very cell that was hit.
///
/// Does **not** own fetch — listens to [EmojiDataSource] and rebuilds on
/// [rebuild]. Call [rebuild] when recents or search projection inputs change;
/// the emoji source listener triggers rebuild automatically. Each [rebuild]
/// publishes one new snapshot on [snapshots].
///
/// Unicode leaves are marked ready on [CatalogAssetCache] during [rebuild] so
/// paint skips circle placeholders for standard emoji cells.
final class EmojiCatalogDataSource {
  /// Creates an adapter over [emojiSource] and [assetCache].
  EmojiCatalogDataSource({
    required EmojiDataSource emojiSource,
    required CatalogAssetCache assetCache,
  }) : _emojiSource = emojiSource,
       _assetCache = assetCache;

  final EmojiDataSource _emojiSource;
  final CatalogAssetCache _assetCache;

  final _snapshots = ObservableValue<CatalogSnapshot>(
    const CatalogSnapshot.empty(),
  );
  List<EmojiCatalogStripTab> _stripTabs = const [];
  var _searchEmpty = false;

  /// The current sections, published for the viewport.
  ValueObservable<CatalogSnapshot> get snapshots => _snapshots;

  /// Current sections in display order.
  List<CatalogSection> get sections => _snapshots.value.sections;

  /// Parallel strip tabs for [sections] (same length and order).
  List<EmojiCatalogStripTab> get stripTabs => _stripTabs;

  /// Whether the last keyword search completed with zero hits.
  ///
  /// True only while [searchQuery] was non-empty and produced no leaves.
  /// Host overlays empty-search copy; the viewport projects no slots.
  bool get isSearchEmpty => _searchEmpty;

  /// Metadata for the cell [hit], or null when it carries none.
  ///
  /// Read from the hit leaf's tag, so recents and catalog cells that share a
  /// glyph string keep their own policy.
  EmojiLeafMeta? metaFor(CatalogLeafHit hit) => switch (hit.leaf.tag) {
    final EmojiLeafMeta meta => meta,
    _ => null,
  };

  /// Rebuilds sections from catalog, [recents], and optional [searchCells].
  ///
  /// Non-empty [searchQuery] replaces browse sections with a single
  /// search-results band (or empty). [searchCells] MUST match [searchQuery]
  /// when non-empty. Calls [notifyDataChanged] once when projection changes.
  void rebuild({
    required List<String> recents,
    required String recentlyUsedLabel,
    EmojiStripIcon? recentsStripIcon,
    required String searchQuery,
    required List<
      ({String pickGlyph, String displayGlyph, bool supportsSkinTone})
    >
    searchCells,
    required String searchResultsLabel,
  }) {
    final sections = <CatalogSection>[];
    final tabs = <EmojiCatalogStripTab>[];
    var searchEmpty = false;

    if (searchQuery.isNotEmpty) {
      if (searchCells.isEmpty) {
        searchEmpty = true;
        _applyProjection(sections, tabs, searchEmpty);
        return;
      }
      final leaves = <CatalogLeaf>[];
      for (final cell in searchCells) {
        leaves.add(
          CatalogLeaf.unicode(
            cell.displayGlyph,
            tag: EmojiLeafMeta(
              pickGlyph: cell.pickGlyph,
              isRecent: false,
              supportsSkinTone: cell.supportsSkinTone,
              pickSource: EmojiPickSource.search,
            ),
          ),
        );
        _markUnicodeReady(cell.displayGlyph);
      }
      sections.add(
        CatalogSection(id: 'search', title: searchResultsLabel, leaves: leaves),
      );
      tabs.add(
        EmojiCatalogStripTab(
          id: 'search',
          icon: EmojiTabAssets.recentsStripIcon,
        ),
      );
      _applyProjection(sections, tabs, searchEmpty);
      return;
    }

    if (recents.isNotEmpty) {
      final leaves = <CatalogLeaf>[];
      for (final glyph in recents) {
        leaves.add(
          CatalogLeaf.unicode(
            glyph,
            tag: EmojiLeafMeta(
              pickGlyph: glyph,
              isRecent: true,
              supportsSkinTone: false,
              pickSource: EmojiPickSource.recent,
            ),
          ),
        );
        _markUnicodeReady(glyph);
      }
      sections.add(
        CatalogSection(
          id: emojiRecentsSectionId,
          title: recentlyUsedLabel,
          leaves: leaves,
        ),
      );
      tabs.add(
        EmojiCatalogStripTab(
          id: emojiRecentsSectionId,
          icon: recentsStripIcon ?? EmojiTabAssets.recentsStripIcon,
        ),
      );
    }

    for (final cat in _emojiSource.categories) {
      final leaves = <CatalogLeaf>[];
      for (final item in cat.items) {
        if (item case final UnicodeEmojiItem unicode) {
          final cell = _cellForCatalogItem(unicode);
          leaves.add(
            CatalogLeaf.unicode(
              cell.displayGlyph,
              tag: EmojiLeafMeta(
                pickGlyph: cell.pickGlyph,
                isRecent: false,
                supportsSkinTone: cell.supportsSkinTone,
                pickSource: EmojiPickSource.grid,
              ),
            ),
          );
          _markUnicodeReady(cell.displayGlyph);
        }
      }
      if (leaves.isEmpty) continue;
      sections.add(
        CatalogSection(id: cat.id, title: cat.title, leaves: leaves),
      );
      tabs.add(
        EmojiCatalogStripTab(
          id: cat.id,
          icon: cat.stripIcon ?? EmojiTabAssets.stripIconForId(cat.id),
        ),
      );
    }

    _applyProjection(sections, tabs, searchEmpty);
  }

  void _applyProjection(
    List<CatalogSection> sections,
    List<EmojiCatalogStripTab> tabs,
    bool searchEmpty,
  ) {
    _stripTabs = List<EmojiCatalogStripTab>.unmodifiable(tabs);
    _searchEmpty = searchEmpty;
    if (LogCategory.emoji.enabled) {
      final leafCount = sections.fold<int>(0, (n, s) => n + s.leaves.length);
      fine(.emoji, 'catalog.rebuild', {
        'sections': sections.length,
        'leaves': leafCount,
        'searchEmpty': searchEmpty,
      });
    }
    _snapshots.value = CatalogSnapshot(sections);
  }

  ({String pickGlyph, String displayGlyph, bool supportsSkinTone})
  _cellForCatalogItem(UnicodeEmojiItem item) {
    final supports = item.supportsSkinTone;
    final display = supports
        ? EmojiSkinTone.apply(item.glyph, _emojiSource.skinToneFor(item.glyph))
        : item.glyph;
    return (
      pickGlyph: item.glyph,
      displayGlyph: display,
      supportsSkinTone: supports,
    );
  }

  void _markUnicodeReady(String glyph) {
    if (_assetCache case final MemoryCatalogAssetCache memory) {
      memory.markReady(
        CatalogAssetKey.unicode(glyph),
        CatalogAssetCacheType.keyboard,
      );
    }
  }

  /// Drops the snapshot listeners. Idempotent.
  void dispose() => _snapshots.dispose();
}

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_chrome/src/panel/emoji_tab_assets.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/foundation.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// Host metadata for one projected [CatalogLeaf] in the emoji grid.
///
/// [CatalogLeaf] carries paint identity only; pick policy and long-press
/// eligibility live here so [EmojiPage] can wire viewport callbacks without
/// inferring from glyph strings alone.
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

/// [CatalogDataSource] adapter for [EmojiPage].
///
/// Owns the viewport-facing section list projected from [EmojiDataSource],
/// optional recents, and keyword-search results. Maintains a side map from each
/// projected [CatalogLeaf] instance to [EmojiLeafMeta] for tap and long-press
/// policy.
///
/// Does **not** own fetch — listens to [EmojiDataSource] and rebuilds on
/// [rebuild]. Call [rebuild] when recents or search projection inputs change;
/// the emoji source listener triggers rebuild automatically.
///
/// Unicode leaves are marked ready on [CatalogAssetCache] during [rebuild] so
/// paint skips circle placeholders for standard emoji cells.
final class EmojiCatalogDataSource extends CatalogDataSource {
  static final PanelCatalogDevLog _log = PanelCatalogDevLog(
    'KeyboardPanel',
  );

  /// Creates an adapter over [emojiSource] and [assetCache].
  EmojiCatalogDataSource({
    required EmojiDataSource emojiSource,
    required CatalogAssetCache assetCache,
  }) : _emojiSource = emojiSource,
       _assetCache = assetCache;

  final EmojiDataSource _emojiSource;
  final CatalogAssetCache _assetCache;

  List<CatalogSection> _sections = const [];
  List<EmojiCatalogStripTab> _stripTabs = const [];
  Map<CatalogLeaf, EmojiLeafMeta> _leafMeta =
      const <CatalogLeaf, EmojiLeafMeta>{};
  var _searchEmpty = false;

  /// Parallel strip tabs for [_sections] (same length and order).
  List<EmojiCatalogStripTab> get stripTabs => _stripTabs;

  /// Whether the last keyword search completed with zero hits.
  ///
  /// True only while [searchQuery] was non-empty and produced no leaves.
  /// Host overlays empty-search copy; the viewport projects no slots.
  bool get isSearchEmpty => _searchEmpty;

  /// Metadata for [leaf], or null when the leaf is unknown.
  ///
  /// Lookup is by leaf **instance** (projection identity), not [CatalogAssetKey]
  /// alone — recents and catalog can share the same glyph string.
  EmojiLeafMeta? metaFor(CatalogLeaf leaf) => _leafMeta[leaf];

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
    final meta = <CatalogLeaf, EmojiLeafMeta>{};
    final sections = <CatalogSection>[];
    final tabs = <EmojiCatalogStripTab>[];
    var searchEmpty = false;

    if (searchQuery.isNotEmpty) {
      if (searchCells.isEmpty) {
        searchEmpty = true;
        _applyProjection(sections, tabs, meta, searchEmpty);
        return;
      }
      final leaves = <CatalogLeaf>[];
      for (final cell in searchCells) {
        final leaf = CatalogLeaf.unicode(cell.displayGlyph);
        leaves.add(leaf);
        meta[leaf] = EmojiLeafMeta(
          pickGlyph: cell.pickGlyph,
          isRecent: false,
          supportsSkinTone: cell.supportsSkinTone,
          pickSource: EmojiPickSource.search,
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
      _applyProjection(sections, tabs, meta, searchEmpty);
      return;
    }

    if (recents.isNotEmpty) {
      final leaves = <CatalogLeaf>[];
      for (final glyph in recents) {
        final leaf = CatalogLeaf.unicode(glyph);
        leaves.add(leaf);
        meta[leaf] = EmojiLeafMeta(
          pickGlyph: glyph,
          isRecent: true,
          supportsSkinTone: false,
          pickSource: EmojiPickSource.recent,
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
          final leaf = CatalogLeaf.unicode(cell.displayGlyph);
          leaves.add(leaf);
          meta[leaf] = EmojiLeafMeta(
            pickGlyph: cell.pickGlyph,
            isRecent: false,
            supportsSkinTone: cell.supportsSkinTone,
            pickSource: EmojiPickSource.grid,
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

    _applyProjection(sections, tabs, meta, searchEmpty);
  }

  void _applyProjection(
    List<CatalogSection> sections,
    List<EmojiCatalogStripTab> tabs,
    Map<CatalogLeaf, EmojiLeafMeta> meta,
    bool searchEmpty,
  ) {
    _sections = List<CatalogSection>.unmodifiable(sections);
    _stripTabs = List<EmojiCatalogStripTab>.unmodifiable(tabs);
    _leafMeta = Map<CatalogLeaf, EmojiLeafMeta>.unmodifiable(meta);
    _searchEmpty = searchEmpty;
    if (_log.enabled) {
      final leafCount = sections.fold<int>(0, (n, s) => n + s.leaves.length);
      _log.event('catalog.rebuild', {
        'sections': sections.length,
        'leaves': leafCount,
        'searchEmpty': searchEmpty,
        'meta': meta.length,
      });
    }
    notifyDataChanged();
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

  @override
  List<CatalogSection> get sections => _sections;
}

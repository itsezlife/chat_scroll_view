import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/emoji/emoji_categories.dart';
import 'package:panel_pages/src/emoji/emoji_strip_footer.dart';
import 'package:panel_pages/src/page/catalog_strip.dart';
import 'package:panel_shell/panel_shell.dart';

/// The category strip of the emoji page: one tab per category, the active one
/// following the catalogue, a tap landing on the category.
///
/// ## Landing rules
///
/// - A tab shows when the page holds a section of its category (the recents
///   tab only while the recents show). A strip with fewer than two tabs
///   navigates nothing and is not drawn.
/// - Tapping a tab scrolls to the **first** section of its category the page
///   shows. The tab is active at once, and stays active until the jump ends:
///   the catalogue's own scroll is ignored while the strip drives it, and a
///   tap while a jump runs is ignored, so the highlight and the motion cannot
///   disagree.
/// - After the jump the tapped tab stays active until the user scrolls into
///   another section, even where the catalogue could not bring the header to
///   the top because the content ends first (a category within the last
///   screenful is reached, and the end of the content is in the last
///   category): the tap is the user's own word.
/// - Otherwise the active tab is the one of the section the user is in
///   (`PanelCatalogCurrentSectionChanged`).
///
/// ## Arrangements
///
/// Under the touch arrangement the strip is a row of round tabs above the
/// catalogue, scrolling sideways when they do not fit; packs have no tab
/// there. Under the pointer arrangement it is pinned below the catalogue as
/// the reference desktop client's footer ([EmojiStripFooter]): the recents,
/// the categories folded into one icon that opens into theirs while one of
/// them is active, then a slot per pack (a section of a `CollectionId.set`,
/// drawn by its cover, or its first item, from [assets]), 30 px each,
/// scrolling under the wheel and a drag when they overflow.
///
/// The strip is the page's own widget: its whole connection is the
/// [CatalogStripHandle]. It requires the chrome theme and strings scopes, and
/// reads the arrangement from `PanelArrangementScope`.
class EmojiCategoryStrip extends StatefulWidget {
  /// A strip over the sections of [handle].
  const EmojiCategoryStrip({
    required this.handle,
    this.assets,
    this.layout = EmojiStripLayout.automatic,
    super.key,
  });

  /// What the page gives its strip.
  final CatalogStripHandle handle;

  /// Where the covers of packs are drawn from, or null to draw none.
  final AssetCacheScope? assets;

  /// How the strip lays its icons out under the pointer arrangement.
  final EmojiStripLayout layout;

  /// Height of the strip.
  static const double height = 36;

  /// Side of a tab's touch area.
  static const double cell = 30;

  /// Side of a tab's picture.
  static const double iconSize = 24;

  /// Gap between tabs.
  static const double gap = 3;

  /// Horizontal inset of the first tab.
  static const double padH = 11;

  /// Identifies the marker of the active icon under the pointer arrangement.
  @visibleForTesting
  static const Key highlightKey = EmojiStripFooter.markerKey;

  @override
  State<EmojiCategoryStrip> createState() => _EmojiCategoryStripState();
}

class _EmojiCategoryStripState extends State<EmojiCategoryStrip> {
  final _scroll = ScrollController();
  var _tabs = const <_StripTab>[];
  String? _active;
  var _jumping = false;
  late StreamSubscription<PanelCatalogScrollEvent> _scrollEvents;

  CatalogStripHandle get _handle => widget.handle;

  @override
  void initState() {
    super.initState();
    _tabs = _tabsOf(_handle.entries.value);
    _active = _tabOfSection(_handle.currentSectionId) ?? _tabs.firstOrNull?.id;
    _handle.entries.addListener(_onEntries);
    _scrollEvents = _handle.scrollEvents.listen(_onScroll);
  }

  @override
  void didUpdateWidget(EmojiCategoryStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.handle, widget.handle)) return;
    oldWidget.handle.entries.removeListener(_onEntries);
    unawaited(_scrollEvents.cancel());
    _handle.entries.addListener(_onEntries);
    _scrollEvents = _handle.scrollEvents.listen(_onScroll);
    _onEntries();
  }

  @override
  void dispose() {
    _handle.entries.removeListener(_onEntries);
    unawaited(_scrollEvents.cancel());
    _scroll.dispose();
    super.dispose();
  }

  // --- Following the catalogue ----------------------------------------------

  void _onEntries() {
    setState(() {
      _tabs = _tabsOf(_handle.entries.value);
      if (!_jumping) {
        _active =
            _tabOfSection(_handle.currentSectionId) ?? _tabs.firstOrNull?.id;
      }
    });
  }

  void _onScroll(PanelCatalogScrollEvent event) {
    if (_jumping) return;
    if (event case PanelCatalogCurrentSectionChanged(:final sectionId)) {
      _select(_tabOfSection(sectionId));
    }
  }

  void _select(String? tab) {
    if (tab == null || tab == _active) return;
    setState(() => _active = tab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
  }

  String? _tabOfSection(String? sectionId) {
    if (sectionId == null) return null;
    for (final tab in _tabs) {
      if (tab.sectionIds.contains(sectionId)) return tab.id;
    }
    return null;
  }

  // The categories' tabs, then a tab per pack.
  static List<_StripTab> _tabsOf(List<CatalogStripEntry> entries) => [
    for (final tab in EmojiCategories.tabs) ?_StripTab.of(tab, entries),
    for (final entry in entries)
      if (entry.collection.id case CollectionId$Set()) _StripTab.pack(entry),
  ];

  List<_StripTab> get _categoryTabs => [
    for (final tab in _tabs)
      if (tab.tab != null) tab,
  ];

  // --- Landing --------------------------------------------------------------

  Future<void> _onTap(_StripTab tab) async {
    if (_jumping) return;
    setState(() {
      _active = tab.id;
      _jumping = true;
    });
    try {
      await _handle.jumpToSection(tab.sectionIds.first);
    } finally {
      if (mounted) {
        setState(() => _jumping = false);
      }
    }
  }

  // Under touch: scrolls just enough to show the active tab. The footer of
  // the pointer arrangement centres it itself.
  void _revealActive() {
    if (!mounted || !_scroll.hasClients) return;
    final index = _categoryTabs.indexWhere((tab) => tab.id == _active);
    if (index < 0) return;
    final start =
        EmojiCategoryStrip.padH +
        index * (EmojiCategoryStrip.cell + EmojiCategoryStrip.gap);
    final end = start + EmojiCategoryStrip.cell;
    const margin = EmojiCategoryStrip.padH;
    final view = _scroll.position.viewportDimension;
    final offset = _scroll.offset;
    // The strip slides on the fade role: under an instant speed (a zero duration, which
    // `moveTo` turns into a jump) the tab lands at once.
    final spec = ChromeMotionScope.of(context).specOf(MotionRole.fade);
    if (start < offset) {
      unawaited(
        _scroll.position.moveTo(
          start - margin,
          duration: spec.duration,
          curve: spec.curve,
        ),
      );
    } else if (end > offset + view) {
      unawaited(
        _scroll.position.moveTo(
          end - view + margin,
          duration: spec.duration,
          curve: spec.curve,
        ),
      );
    }
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final strings = ChromeStringsScope.of(context);
    if (PanelArrangementScope.of(context) == PanelArrangement.pointer) {
      if (_tabs.length < 2) return const SizedBox.shrink();
      return _buildPinned(strings);
    }
    final tabs = _categoryTabs;
    if (tabs.length < 2) return const SizedBox.shrink();
    final panel = ChromeThemeScope.panelOf(context);
    final motion = ChromeMotionScope.of(context);
    return Semantics(
      container: true,
      label: strings.semantics.categoryStripLabel,
      // The shell's background: see-through on glass.
      child: ColoredBox(
        color: PanelBackgroundScope.of(context),
        child: SizedBox(
          height: EmojiCategoryStrip.height,
          width: double.infinity,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: EmojiCategoryStrip.padH,
              vertical: 3,
            ),
            itemCount: tabs.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: EmojiCategoryStrip.gap),
            itemBuilder: (context, index) {
              final tab = tabs[index];
              final category = tab.tab!;
              return _TabButton(
                tab: category,
                label: _labelOf(category, strings),
                selected: tab.id == _active,
                tokens: panel,
                duration: motion.durationOf(MotionRole.fade),
                onTap: () => unawaited(_onTap(tab)),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _labelOf(EmojiCategoryTab tab, ChromeStrings strings) =>
      switch (tab.titleGroup) {
        final group? => strings.panel.categoryTitle(group),
        null => strings.panel.recentlyUsedTitle,
      };

  // The strip under the pointer arrangement: the reference desktop client's
  // footer.
  Widget _buildPinned(ChromeStrings strings) {
    EmojiFooterIcon iconOf(_StripTab tab) => switch (tab) {
      _StripTab(tab: final category?) => EmojiFooterIcon(
        id: tab.id,
        label: _labelOf(category, strings),
        icon: category.icon,
      ),
      _StripTab(:final pack?) => EmojiFooterIcon(
        id: tab.id,
        label: pack.metadata.title ?? '',
        cover: pack.metadata.cover ?? _firstItemOf(pack),
      ),
      _ => EmojiFooterIcon(id: tab.id, label: ''),
    };
    return Semantics(
      container: true,
      label: strings.semantics.categoryStripLabel,
      child: EmojiStripFooter(
        recents: switch (_tabs.where((tab) => tab.tab?.recents ?? false)) {
          final recents when recents.isNotEmpty => iconOf(recents.first),
          _ => null,
        },
        categories: [
          for (final tab in _tabs)
            if (tab.tab case final category? when !category.recents)
              iconOf(tab),
        ],
        packs: [
          for (final tab in _tabs)
            if (tab.pack != null) iconOf(tab),
        ],
        active: _active,
        assets: widget.assets,
        layout: widget.layout,
        onChoose: (id) {
          for (final tab in _tabs) {
            if (tab.id == id) unawaited(_onTap(tab));
          }
        },
      ),
    );
  }

  static ContentKey? _firstItemOf(Collection pack) => switch (pack.contents) {
    CollectionContents$Loaded(:final items) => items.firstOrNull?.key,
    _ => null,
  };
}

/// How the emoji strip lays its icons out under the pointer arrangement.
///
/// Grouped as soon as there is a pack of custom emoji, as the reference
/// desktop client groups; plain otherwise. [automatic] does that; a host can
/// fix either.
enum EmojiStripLayout {
  /// Plain with no pack, grouped with any: the reference client's rule.
  automatic,

  /// Every icon in a 30 px slot of its own, as the grouped layout lays them,
  /// with nothing folded (scrolling when they overflow).
  plain,

  /// 30 px slots: the recents, the categories folded into one icon that opens
  /// while one of them is active, then the packs.
  grouped,
}

// A tab with the sections of the page it covers, in display order: a
// category's (or the recents') tab, or a pack's.
class _StripTab {
  const _StripTab(this.id, this.sectionIds, {this.tab, this.pack});

  _StripTab.pack(CatalogStripEntry entry)
    : this('pack:${entry.sectionId}', [
        entry.sectionId,
      ], pack: entry.collection);

  final String id;
  final List<String> sectionIds;
  final EmojiCategoryTab? tab;
  final Collection? pack;

  static _StripTab? of(EmojiCategoryTab tab, List<CatalogStripEntry> entries) {
    final ids = [
      for (final entry in entries)
        if (tab.covers(entry.collection.id)) entry.sectionId,
    ];
    return ids.isEmpty ? null : _StripTab(tab.id, ids, tab: tab);
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.label,
    required this.selected,
    required this.tokens,
    required this.duration,
    required this.onTap,
  });

  final EmojiCategoryTab tab;
  final String label;
  final bool selected;
  final PanelTokens tokens;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    child: ExcludeSemantics(
      child: FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: EmojiCategoryStrip.cell,
            height: EmojiCategoryStrip.cell,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: selected ? 1 : 0),
              duration: duration,
              curve: Curves.decelerate,
              builder: (context, t, _) => DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // The idle icon colour at a low alpha, on the fill: the
                  // wash is a tint of the icon, and no saveLayer.
                  color: tokens.categoryIcon.withValues(
                    alpha: tokens.categoryIcon.a * 0.18 * t,
                  ),
                ),
                child: Center(
                  child: ChromeIcon(
                    tab.icon,
                    size: EmojiCategoryStrip.iconSize,
                    color: Color.lerp(
                      tokens.categoryIcon,
                      tokens.categoryIconSelected,
                      t,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

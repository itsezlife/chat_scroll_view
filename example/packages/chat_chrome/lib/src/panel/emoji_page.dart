import 'dart:async';
import 'dart:math' as math;

import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// Embeddable unicode emoji grid with overlay category strip.
///
/// Owns catalog presentation (section headers + glyph rows), category
/// navigation, search results layout, and skin-tone long-press chrome.
/// Does **not** own the panel shell, bottom type tabs, or recents persistence
/// policy — inject those via [dataSource], [recents], and host callbacks.
///
/// **Layout**: one flat list of section headers + glyph rows (not N separate
/// grids). Category jumps use flat-list indices via [ListController]
/// (near = animate, far = jump — see [farJumpRowThreshold]).
///
/// **Rebuild isolation**: strip slide and selected category index live on
/// [ValueNotifier]s so scroll does not rebuild the glyph list. Prefer
/// [searchController] / [searchModeListenable] when the host MUST avoid
/// rebuilding this page on every keystroke.
///
/// **Embedding**: use the [EmojiGridView] typedef when mounting outside
/// [EmojiPanel]. Keep-alive is enabled so a pager may retain this page.
class EmojiPage extends StatefulWidget {
  /// Creates the emoji grid (also exported as [EmojiGridView]).
  const EmojiPage({
    required this.dataSource,
    required this.recents,
    required this.recentlyUsedLabel,
    required this.onEmojiSelected,
    this.recentsStripIcon,
    this.searchQuery = '',
    this.searchController,
    this.searchMode = false,
    this.searchModeListenable,
    this.showCategoryStrip = true,
    this.searchFieldTranslationY,
    this.searchFieldShadow,
    this.searchFocusNode,
    this.searchHintText,
    this.searchResultsLabel,
    this.searchEmptyLabel,
    this.onOpenSearch,
    this.onClearRecents,
    this.onCategoryTap,
    this.onCategoryJumpEnd,
    super.key,
  });

  /// Catalog, search, and skin-tone prefs.
  ///
  /// The page listens via [EmojiDataSource.addDataListener] and rebuilds
  /// sections when the source notifies.
  final EmojiDataSource dataSource;

  /// Frequently-used glyphs (most-used first).
  ///
  /// Empty → no synthetic recents section. The panel shell typically defers
  /// applying pending recents until dismiss.
  final List<String> recents;

  /// Host-localized title for the synthetic recents section header.
  final String recentlyUsedLabel;

  /// Strip icon for the synthetic recents section.
  ///
  /// Defaults to [EmojiTabAssets.recentsStripIcon] when null.
  final EmojiStripIcon? recentsStripIcon;

  /// Insert into the composer.
  ///
  /// [source] MUST reflect how the glyph was chosen so the data source can
  /// apply recents policy (`grid` / `recent` / `search`).
  final void Function(String glyph, {required EmojiPickSource source})
  onEmojiSelected;

  /// Long-press on a recent cell — host SHOULD confirm before clearing.
  final VoidCallback? onClearRecents;

  /// Keyword query when [searchController] is null.
  ///
  /// Non-empty → keyword hits. Empty + [searchMode] → frequently-used only.
  /// Ignored while [searchController] is non-null (controller text wins).
  final String searchQuery;

  /// Optional live query source — page listens without a parent rebuild.
  ///
  /// When non-null, [searchQuery] is ignored.
  final TextEditingController? searchController;

  /// Whether search chrome is open when [searchModeListenable] is null.
  ///
  /// Picks report [EmojiPickSource.search] while search mode is active.
  /// Ignored while [searchModeListenable] is non-null.
  final bool searchMode;

  /// Optional live search-mode flag (panel shell).
  ///
  /// When set, category strip visibility is `!value` and overrides
  /// [showCategoryStrip].
  final ValueListenable<bool>? searchModeListenable;

  /// Whether to paint the overlay category strip.
  ///
  /// Hosts typically pass `false` while searching. Overridden by
  /// [searchModeListenable] when that listenable is non-null.
  final bool showCategoryStrip;

  /// Written by this page: sticky search-field Y (idle browse).
  ///
  /// While search mode is open the page writes `0` (field pinned). When
  /// [searchFocusNode] / [onOpenSearch] are set, this page paints
  /// [EmojiSearchField] with `Positioned` + `Transform.translate` under the
  /// category strip (Telegram `setTranslationY`).
  final ValueNotifier<double>? searchFieldTranslationY;

  /// Written by this page: search-field bottom shadow while search is open.
  final ValueNotifier<bool>? searchFieldShadow;

  /// Focus node for the sticky [EmojiSearchField] (owned by the panel shell).
  final FocusNode? searchFocusNode;

  /// Search hint (host l10n).
  final String? searchHintText;

  /// Section header for keyword hits (`StickerOrEmojiSearchResult`).
  final String? searchResultsLabel;

  /// Empty keyword-search placeholder (`NoEmojiFound`).
  final String? searchEmptyLabel;

  /// Fired when the user taps the sticky field while search is closed.
  final VoidCallback? onOpenSearch;

  /// Fired when the user taps a category strip tab (before scroll starts).
  final VoidCallback? onCategoryTap;

  /// Fired when a category [EmojiPageState.jumpToSection] finishes
  /// (animate or jump), including early returns when scroll is unattached.
  final VoidCallback? onCategoryJumpEnd;

  /// Horizontal inset of the glyph grid.
  static const double gridPadH = 5;

  /// Top inset that clears the overlay category strip.
  static const double gridPadTop = 36;

  /// Bottom inset that clears the panel bottom chrome (with slack).
  static const double gridPadBottom = 44;

  /// Drawn emoji glyph size (phone).
  static const double glyphSize = 34;

  /// Section header row height.
  static const double headerHeight = 27;

  /// Section header type size.
  static const double headerFontSize = 15;

  /// Empty keyword-search label size (`NoEmojiFound`).
  static const double searchEmptyFontSize = 16;

  /// Top inset for empty keyword-search text (Telegram HELP cell).
  static const double searchEmptyPadTop = 10;

  /// Minimum empty-search body height when the panel is short.
  static const double searchEmptyMinHeight = 120;

  /// Cell pitch used to derive column count from width.
  static const double cellPitch = 45;

  /// Far category jump threshold in rows (`columns ×` this many).
  ///
  /// Near jumps animate; farther jumps jump without scrubbing the path.
  static const int farJumpRowThreshold = 9;

  @override
  State<EmojiPage> createState() => EmojiPageState();
}

/// State for [EmojiPage].
///
/// Exposed for widget tests and hosts that need [jumpToSection],
/// [categoryIndex], or [stripOffset]. Prefer driving navigation from the
/// category strip; do not mutate scroll controllers from outside.
class EmojiPageState extends State<EmojiPage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  // --- Scroll ---------------------------------------------------------------

  final ScrollController _scroll = ScrollController();
  final ListController _listController = ListController();

  /// Suppresses strip / category sync while [jumpToSection] owns the scroll.
  var _programmaticScroll = false;

  // --- Category strip (notifier-scoped; scroll MUST NOT rebuild the grid) ---

  final ValueNotifier<int> _categoryIndex = ValueNotifier<int>(0);
  final ValueNotifier<double> _stripOffset = ValueNotifier<double>(0);
  final ValueNotifier<bool> _stripShadowVisible = ValueNotifier<bool>(false);

  AnimationController? _stripReveal;

  // --- Skin-tone picker session ---------------------------------------------

  EmojiColorPickerSession? _picker;
  String? _pickerBase;
  var _pickerIsRecent = false;

  // --- Search cache ---------------------------------------------------------

  /// Cells for the last completed keyword search ([_loadedSearchQuery]).
  List<_Cell> _searchCells = const <_Cell>[];

  /// Query that produced [_searchCells]; empty when not in keyword results.
  String _loadedSearchQuery = '';

  /// Restartable debounce for keyword search.
  Timer? _searchDebounce;

  /// Delayed leading-icon progress (Telegram 65ms).
  Timer? _searchProgressDelay;

  /// Monotonic generation to ignore stale [EmojiDataSource.search] replies.
  var _searchGen = 0;

  /// Leading search icon busy flag.
  final ValueNotifier<bool> _searchBusy = ValueNotifier<bool>(false);

  // --- Section / flat-list model --------------------------------------------

  List<_Section> _sections = const <_Section>[];
  List<_FlatItem> _flat = const <_FlatItem>[];

  /// Flat-list index of each section header (parallel to [_sections]).
  List<int> _sectionListIndex = const <int>[];

  /// Column count used to build [_flat]; `0` forces rebuild on next layout.
  var _columns = 0;

  /// Row height (= cell pitch) used for [_flat] extent estimation.
  var _rowExtent = EmojiPage.cellPitch;

  /// Last laid-out viewport height (empty-search fill).
  var _viewportHeight = 0.0;

  // --- Test / host observables ----------------------------------------------

  /// Selected category strip index (`0` = first section, often recents).
  int get categoryIndex => _categoryIndex.value;

  /// Category strip vertical translation (`0` = fully visible, negative = hidden).
  double get stripOffset => _stripOffset.value;

  /// Whether the strip bottom shadow is shown.
  bool get stripShadowVisible => _stripShadowVisible.value;

  @override
  bool get wantKeepAlive => true;

  // --- Derived projections (widget / listenables) ---------------------------

  /// Live search text: [EmojiPage.searchController] wins over [EmojiPage.searchQuery].
  String get _activeSearchQuery =>
      widget.searchController?.text ?? widget.searchQuery;

  /// Whether picks report [EmojiPickSource.search].
  bool get _searchMode =>
      widget.searchModeListenable?.value ?? widget.searchMode;

  /// Whether the overlay category strip is painted.
  bool get _showCategoryStrip => widget.searchModeListenable != null
      ? !widget.searchModeListenable!.value
      : widget.showCategoryStrip;

  // --- Lifecycle ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _stripOffset.addListener(_onStripOffsetChanged);
    widget.dataSource.addDataListener(_onDataChanged);
    widget.searchController?.addListener(_onSearchController);
    widget.searchModeListenable?.addListener(_onSearchModeListenable);
    _rebuildSections();
    _scheduleSearch(_activeSearchQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateSearchGeometry();
    });
  }

  @override
  void didUpdateWidget(EmojiPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataSource != widget.dataSource) {
      oldWidget.dataSource.removeDataListener(_onDataChanged);
      widget.dataSource.addDataListener(_onDataChanged);
      _rebuildSections();
      _columns = 0;
    } else if (!identical(oldWidget.recents, widget.recents) ||
        oldWidget.recentlyUsedLabel != widget.recentlyUsedLabel ||
        oldWidget.recentsStripIcon != widget.recentsStripIcon) {
      _rebuildSections();
      _columns = 0;
    }
    if (!identical(oldWidget.searchController, widget.searchController)) {
      oldWidget.searchController?.removeListener(_onSearchController);
      widget.searchController?.addListener(_onSearchController);
      _scheduleSearch(_activeSearchQuery);
    } else if (widget.searchController == null &&
        oldWidget.searchQuery != widget.searchQuery) {
      _scheduleSearch(widget.searchQuery);
    }
    if (!identical(
      oldWidget.searchModeListenable,
      widget.searchModeListenable,
    )) {
      oldWidget.searchModeListenable?.removeListener(_onSearchModeListenable);
      widget.searchModeListenable?.addListener(_onSearchModeListenable);
      if (mounted) setState(() {});
    } else if (widget.searchModeListenable == null &&
        (oldWidget.searchMode != widget.searchMode ||
            oldWidget.showCategoryStrip != widget.showCategoryStrip)) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    widget.dataSource.removeDataListener(_onDataChanged);
    widget.searchController?.removeListener(_onSearchController);
    widget.searchModeListenable?.removeListener(_onSearchModeListenable);
    _searchDebounce?.cancel();
    _searchProgressDelay?.cancel();
    _searchBusy.dispose();
    _picker?.cancel();
    _stripReveal?.dispose();
    _stripOffset.removeListener(_onStripOffsetChanged);
    _categoryIndex.dispose();
    _stripOffset.dispose();
    _stripShadowVisible.dispose();
    _listController.dispose();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  // --- Data / search listeners ----------------------------------------------

  /// Catalog or prefs changed — rebuild sections; refresh active keyword search.
  void _onDataChanged() {
    _rebuildSections();
    _columns = 0;
    if (_loadedSearchQuery.isNotEmpty) {
      unawaited(_loadSearch(_loadedSearchQuery));
    }
    if (mounted) setState(() {});
  }

  void _onSearchController() => _scheduleSearch(_activeSearchQuery);

  void _onSearchModeListenable() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateSearchGeometry();
    });
  }

  void _onStripOffsetChanged() => _updateSearchGeometry();

  // --- Section rebuild ------------------------------------------------------

  /// Resolves catalog / skin-tone presentation once — not per item builder.
  void _rebuildSections() {
    final sections = <_Section>[];
    if (widget.recents.isNotEmpty) {
      sections.add(
        _Section(
          id: emojiRecentsSectionId,
          label: widget.recentlyUsedLabel,
          cells: <_Cell>[
            for (final glyph in widget.recents)
              _Cell(
                pickGlyph: glyph,
                displayGlyph: glyph,
                supportsSkinTone: false,
              ),
          ],
          isRecent: true,
          stripIcon: widget.recentsStripIcon ?? EmojiTabAssets.recentsStripIcon,
        ),
      );
    }
    for (final cat in widget.dataSource.categories) {
      final cells = <_Cell>[
        for (final item in cat.items)
          if (item case final UnicodeEmojiItem unicode)
            _cellForCatalogItem(unicode),
      ];
      if (cells.isEmpty) continue;
      sections.add(
        _Section(
          id: cat.id,
          label: cat.title,
          cells: cells,
          isRecent: false,
          stripIcon: cat.stripIcon ?? EmojiTabAssets.stripIconForId(cat.id),
        ),
      );
    }
    _sections = sections;
  }

  /// Rebuilds the flat header+row list for [columns] / [rowExtent].
  ///
  /// MUST be called when column count or cell pitch changes; extents feed
  /// [SuperSliverList.extentEstimation] and [jumpToSection].
  ///
  /// Leading [\_SearchSpacerItem] reserves sticky search-field space.
  ///
  /// Non-empty [_loadedSearchQuery] swaps catalog sections for keyword hits
  /// (same list — Telegram `emojiAdapter` ↔ `emojiSearchAdapter`). Empty
  /// hits → spacer + [\_EmptySearchItem] (no “Search result” header).
  void _rebuildFlat({required int columns, required double rowExtent}) {
    final flat = <_FlatItem>[const _FlatItem.searchSpacer()];
    final sectionStarts = <int>[];

    if (_loadedSearchQuery.isNotEmpty) {
      if (_searchCells.isEmpty) {
        flat.add(const _FlatItem.emptySearch());
        _flat = flat;
        _sectionListIndex = sectionStarts;
        _columns = columns;
        _rowExtent = rowExtent;
        return;
      }
      sectionStarts.add(flat.length);
      flat.add(
        _FlatItem.header(
          sectionIndex: 0,
          label: widget.searchResultsLabel ?? 'Search result',
          isFirst: true,
        ),
      );
      for (var i = 0; i < _searchCells.length; i += columns) {
        final end = math.min(i + columns, _searchCells.length);
        flat.add(
          _FlatItem.row(
            sectionIndex: 0,
            rowIndex: i ~/ columns,
            cells: _searchCells.sublist(i, end),
            isRecent: false,
            isLastSection: true,
            isLastRow: end >= _searchCells.length,
          ),
        );
      }
      _flat = flat;
      _sectionListIndex = sectionStarts;
      _columns = columns;
      _rowExtent = rowExtent;
      return;
    }

    for (var s = 0; s < _sections.length; s++) {
      final section = _sections[s];
      sectionStarts.add(flat.length);
      flat.add(
        _FlatItem.header(
          sectionIndex: s,
          label: section.label,
          isFirst: s == 0,
        ),
      );
      for (var i = 0; i < section.cells.length; i += columns) {
        final end = math.min(i + columns, section.cells.length);
        flat.add(
          _FlatItem.row(
            sectionIndex: s,
            rowIndex: i ~/ columns,
            cells: section.cells.sublist(i, end),
            isRecent: section.isRecent,
            isLastSection: s == _sections.length - 1,
            isLastRow: end >= section.cells.length,
          ),
        );
      }
    }
    _flat = flat;
    _sectionListIndex = sectionStarts;
    _columns = columns;
    _rowExtent = rowExtent;
  }

  _Cell _cellForCatalogItem(UnicodeEmojiItem item) {
    final supports = item.supportsSkinTone;
    final display = supports
        ? EmojiSkinTone.apply(
            item.glyph,
            widget.dataSource.skinToneFor(item.glyph),
          )
        : item.glyph;
    return _Cell(
      pickGlyph: item.glyph,
      displayGlyph: display,
      supportsSkinTone: supports,
    );
  }

  // --- Search load ----------------------------------------------------------

  void _setSearchBusy(bool busy) {
    if (_searchBusy.value == busy) return;
    _searchBusy.value = busy;
  }

  void _scheduleSearch(String query) {
    final q = query.trim();
    _searchDebounce?.cancel();
    _searchProgressDelay?.cancel();

    if (q.isEmpty) {
      _searchGen++;
      _setSearchBusy(false);
      if (_loadedSearchQuery.isNotEmpty || _searchCells.isNotEmpty) {
        setState(() {
          _loadedSearchQuery = '';
          _searchCells = const <_Cell>[];
          _columns = 0;
        });
      }
      return;
    }

    _searchProgressDelay = Timer(KeyboardPanelMotion.searchProgressDelay, () {
      if (!mounted) return;
      if (_activeSearchQuery.trim() != q) return;
      _setSearchBusy(true);
    });
    _searchDebounce = Timer(KeyboardPanelMotion.searchDebounce, () {
      unawaited(_loadSearch(q));
    });
  }

  Future<void> _loadSearch(String query) async {
    final gen = ++_searchGen;
    final items = await widget.dataSource.search(query);
    if (!mounted || gen != _searchGen) return;
    if (_activeSearchQuery.trim() != query) return;
    final cells = <_Cell>[
      for (final item in items)
        if (item case final UnicodeEmojiItem unicode)
          _cellForCatalogItem(unicode),
    ];
    _setSearchBusy(false);
    setState(() {
      _loadedSearchQuery = query;
      _searchCells = cells;
      _columns = 0;
    });
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateSearchGeometry();
    });
  }

  // --- Layout helpers -------------------------------------------------------

  List<EmojiCategoryStripTab> _stripTabs(List<_Section> sections) => sections
      .map((s) => EmojiCategoryStripTab(id: s.id, icon: s.stripIcon))
      .toList(growable: false);

  int _columnCount(double width) {
    final inner = math.max(0.0, width - EmojiPage.gridPadH * 2);
    return math.max(1, inner ~/ EmojiPage.cellPitch);
  }

  double _cellExtent(double width, int columns) {
    final inner = math.max(0.0, width - EmojiPage.gridPadH * 2);
    return inner / columns;
  }

  /// Remaining panel height under the sticky search field (`VIEW_TYPE_HELP`).
  double _emptySearchExtent([double? viewportHeight]) {
    final h = viewportHeight ?? _viewportHeight;
    return math.max(
      EmojiPage.searchEmptyMinHeight,
      h - EmojiSearchField.height,
    );
  }

  double _extentOf(int listIndex) {
    return switch (_flat[listIndex]) {
      _SearchSpacerItem() => EmojiSearchField.height,
      _EmptySearchItem() => _emptySearchExtent(),
      _HeaderItem() => EmojiPage.headerHeight,
      _RowItem(:final isLastSection, :final isLastRow) =>
        _rowExtent + (isLastSection && isLastRow ? EmojiPage.gridPadBottom : 0),
    };
  }

  // --- Scroll / category strip ----------------------------------------------

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // Always track sticky search TY — including programmatic
    // [scrollPastSearchSpacer] / [jumpToSection]. Skipping here left the
    // overlay parked until settle (content scrolled under a frozen field).
    _updateSearchGeometry();
    if (_programmaticScroll || _sectionListIndex.isEmpty) return;

    final top = _scroll.offset;
    final padTop = _showCategoryStrip ? EmojiPage.gridPadTop : 0.0;
    // Header is "current" while its top is at/above the strip baseline.
    final probe = top + padTop + 1;
    var index = 0;
    var y = 0.0;
    var cursor = 0;
    for (var s = 0; s < _sectionListIndex.length; s++) {
      final start = _sectionListIndex[s];
      while (cursor < start) {
        y += _extentOf(cursor);
        cursor++;
      }
      if (y <= probe) {
        index = s;
      } else {
        break;
      }
    }
    if (index != _categoryIndex.value) {
      _categoryIndex.value = index;
    }
  }

  /// Sticky search-field TY + strip / field shadows (`checkEmojiSearchFieldScroll`).
  void _updateSearchGeometry() {
    final tyNotifier = widget.searchFieldTranslationY;
    final shadowNotifier = widget.searchFieldShadow;

    if (_searchMode) {
      tyNotifier?.value = 0;
      final scrolledUnder = _scroll.hasClients && _scroll.offset > 0.5;
      if (shadowNotifier != null && shadowNotifier.value != scrolledUnder) {
        shadowNotifier.value = scrolledUnder;
      }
      if (_stripShadowVisible.value) {
        _stripShadowVisible.value = false;
      }
      return;
    }

    if (!_scroll.hasClients) {
      tyNotifier?.value = EmojiPage.gridPadTop;
      shadowNotifier?.value = false;
      return;
    }

    final padTop = EmojiPage.gridPadTop;
    final offset = _scroll.offset;
    // Spacer is content y=0; with scroll padding [padTop], viewport top =
    // padTop − offset (Telegram: holder.top, else −searchFieldHeight).
    var ty = padTop - offset;
    if (ty < -EmojiSearchField.height) {
      ty = -EmojiSearchField.height;
    }
    if (tyNotifier != null && (tyNotifier.value - ty).abs() > 0.1) {
      tyNotifier.value = ty;
    }
    if (shadowNotifier != null && shadowNotifier.value) {
      shadowNotifier.value = false;
    }

    // checkEmojiShadow: translatedBottom = 38 + tabsY.
    final stripY = _stripOffset.value;
    final translatedBottom = EmojiCategoryStripOverlay.shadowProbe + stripY;
    final spacerBottom = ty + EmojiSearchField.height;
    final spacerGone = offset >= padTop + EmojiSearchField.height - 0.5;
    final showShadow =
        translatedBottom > 0 && (spacerGone || spacerBottom < translatedBottom);
    if (_stripShadowVisible.value != showShadow) {
      _stripShadowVisible.value = showShadow;
    }
  }

  /// Drop search-field focus on finger drag.
  ///
  /// Must **not** use [ScrollViewKeyboardDismissBehavior.onDrag]: that calls
  /// [FocusScopeNode.unfocus] and clears every focused descendant (composer
  /// included). Only [EmojiPage.searchFocusNode] is cleared here.
  void _dismissSearchFocusOnUserDrag(ScrollNotification notification) {
    if (_programmaticScroll) return;
    if (notification is! ScrollStartNotification) return;
    if (notification.dragDetails == null) return;
    final focus = widget.searchFocusNode;
    if (focus == null || !focus.hasFocus) return;
    focus.unfocus();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    _dismissSearchFocusOnUserDrag(notification);
    if (_programmaticScroll || !_showCategoryStrip) return false;
    if (notification is! ScrollUpdateNotification) return false;
    final dy = notification.scrollDelta ?? 0;
    if (dy == 0) return false;

    // Refuse strip hide while the search spacer is still under padTop.
    if (dy > 0 && _scroll.hasClients) {
      final padTop = EmojiPage.gridPadTop;
      final spacerTop = padTop - _scroll.offset;
      if (spacerTop + EmojiSearchField.height >= padTop) {
        return false;
      }
    }

    final atTop = _scroll.offset <= 0;
    if (dy > 0 && atTop) {
      if (_stripOffset.value != 0) {
        _stripOffset.value = 0;
      }
      return false;
    }

    // Clamp display to −36; accumulate beyond for snap feel (tabsMinusDy −108).
    final next = (_stripOffset.value - dy).clamp(
      -EmojiCategoryStrip.height * 3,
      0.0,
    );
    final painted = next.clamp(-EmojiCategoryStrip.height, 0.0);
    if (painted != _stripOffset.value) {
      _stripOffset.value = painted;
    }
    return false;
  }

  /// Scroll past the search spacer (reselect type tab) — hides sticky search.
  ///
  /// Animates the category strip to fully visible. Does **not** exit search mode.
  Future<void> scrollPastSearchSpacer() async {
    await revealStrip();
    if (!_scroll.hasClients) return;
    final target = EmojiSearchField.height.clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    if ((_scroll.offset - target).abs() < 0.5) {
      _updateSearchGeometry();
      return;
    }
    _programmaticScroll = true;
    try {
      await _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.decelerate,
      );
    } finally {
      _programmaticScroll = false;
      _updateSearchGeometry();
    }
  }

  /// Animates category strip `translationY` to `0` (150ms EASE_OUT_QUINT).
  Future<void> revealStrip() async {
    final from = _stripOffset.value;
    if (from >= -0.5) {
      _stripOffset.value = 0;
      return;
    }
    _stripReveal?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _stripReveal = controller;
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutQuint,
    );
    void tick() {
      _stripOffset.value = from * (1 - animation.value);
    }

    animation.addListener(tick);
    try {
      await controller.forward();
      _stripOffset.value = 0;
    } finally {
      animation.removeListener(tick);
      controller.dispose();
      if (identical(_stripReveal, controller)) {
        _stripReveal = null;
      }
    }
  }

  /// Scroll so section [index]'s header sits just under the category strip.
  ///
  /// [index] is a section index (`0..sectionCount-1`), not a flat-list index.
  /// Out-of-range values are no-ops. Near targets animate; far targets
  /// ([farJumpRowThreshold]) jump. Always invokes [EmojiPage.onCategoryJumpEnd]
  /// when finished (including when scroll is not yet attached).
  ///
  /// Side effects: [EmojiPage.onCategoryTap], resets strip offset to visible,
  /// updates [categoryIndex].
  Future<void> jumpToSection(int index) async {
    if (index < 0 || index >= _sectionListIndex.length) return;
    widget.onCategoryTap?.call();
    _categoryIndex.value = index;
    _stripOffset.value = 0;
    if (!_scroll.hasClients || !_listController.isAttached) {
      widget.onCategoryJumpEnd?.call();
      return;
    }

    final listIndex = _sectionListIndex[index];
    final padTop = _showCategoryStrip ? EmojiPage.gridPadTop : 0.0;
    // alignment 0 parks the header under the strip; pull back by [padTop].
    // ignore: invalid_use_of_visible_for_testing_member
    final leading = _listController.getOffsetToReveal(listIndex, 0);
    final target = (leading - padTop).clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );

    final visible = _listController.visibleRange;
    final firstVisible = visible?.$1 ?? 0;
    final rowDelta = (listIndex - firstVisible).abs();
    final far =
        rowDelta > math.max(1, _columns) * EmojiPage.farJumpRowThreshold;

    _programmaticScroll = true;
    try {
      if (far) {
        _scroll.jumpTo(target);
        await WidgetsBinding.instance.endOfFrame;
        await WidgetsBinding.instance.endOfFrame;
      } else {
        await _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.decelerate,
        );
        await WidgetsBinding.instance.endOfFrame;
      }
    } finally {
      _programmaticScroll = false;
      _updateSearchGeometry();
      widget.onCategoryJumpEnd?.call();
    }
  }

  // --- Pick / skin-tone -----------------------------------------------------

  void _onTap(
    String glyph, {
    required EmojiPickSource source,
    required bool isRecent,
  }) {
    HapticFeedback.selectionClick();
    final base = EmojiSkinTone.strip(glyph);
    final out = isRecent
        ? glyph
        : EmojiSkinTone.apply(base, widget.dataSource.skinToneFor(base));
    final resolved = _searchMode ? EmojiPickSource.search : source;
    widget.onEmojiSelected(out, source: resolved);
  }

  void _onLongPressStart(
    String glyph, {
    required bool isRecent,
    required LongPressStartDetails details,
  }) {
    if (isRecent) {
      HapticFeedback.mediumImpact();
      widget.onClearRecents?.call();
      return;
    }

    final base = EmojiSkinTone.strip(glyph);
    if (!EmojiSkinTone.supports(base)) return;

    _picker?.cancel();
    final initial = isRecent
        ? EmojiSkinTone.indexOf(glyph)
        : widget.dataSource.skinToneFor(base);

    _pickerIsRecent = isRecent;
    _pickerBase = base;
    _picker = EmojiColorPickerSession.show(
      context: context,
      base: base,
      anchorGlobal: details.globalPosition,
      initialSelection: initial,
    );
  }

  void _onLongPressMove(LongPressMoveUpdateDetails details) {
    _picker?.updateFromGlobalX(details.globalPosition.dx);
  }

  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    final session = _picker;
    final base = _pickerBase;
    final isRecent = _pickerIsRecent;
    _picker = null;
    _pickerBase = null;
    if (session == null || base == null) return;

    session.complete();
    final chosen = await session.future;
    if (chosen == null || !mounted) return;

    if (!isRecent) {
      await widget.dataSource.setSkinTone(base, EmojiSkinTone.indexOf(chosen));
    }
    HapticFeedback.selectionClick();
    widget.onEmojiSelected(
      chosen,
      source: _searchMode ? EmojiPickSource.search : EmojiPickSource.grid,
    );
  }

  Widget _buildGlyphCell(
    _Cell entry, {
    required double cellSize,
    required bool isRecent,
    required EmojiPickSource source,
  }) {
    // Wire long-press only when there is an action. Passing move/end alone
    // still registers a LongPressGestureRecognizer — it wins the arena after
    // ~500ms, cancels tap, and no-ops (plain glyphs without skin tone).
    final longPress = isRecent || entry.supportsSkinTone;
    return EmojiGlyphCell(
      key: ValueKey<String>(entry.pickGlyph),
      glyph: entry.displayGlyph,
      cellSize: cellSize,
      onTap: () => _onTap(entry.pickGlyph, source: source, isRecent: isRecent),
      onLongPressStart: longPress
          ? (d) => _onLongPressStart(
              entry.pickGlyph,
              isRecent: isRecent,
              details: d,
            )
          : null,
      onLongPressMove: longPress ? _onLongPressMove : null,
      onLongPressEnd: longPress ? _onLongPressEnd : null,
    );
  }

  // --- Build ----------------------------------------------------------------

  /// Sticky search host under the strip (panel supplies focus / open callback).
  ///
  /// Returns a **direct** [Positioned] for [Stack] — [ListenableBuilder] must
  /// wrap the child, not the [Positioned], or `top` parent-data is ignored.
  ///
  /// Opaque [panelBackground] under the glass pill so catalog headers cannot
  /// show through `emojiSearchFill` (α≈0x0F). Grid is also clipped below the
  /// field (`emojiContainer.drawChild`).
  Widget? _stickySearchOverlay() {
    final focus = widget.searchFocusNode;
    final controller = widget.searchController;
    final onOpen = widget.onOpenSearch;
    final tyListenable = widget.searchFieldTranslationY;
    if (focus == null ||
        controller == null ||
        onOpen == null ||
        tyListenable == null) {
      return null;
    }
    final shadowListenable = widget.searchFieldShadow;
    final modeListenable = widget.searchModeListenable;
    final colors = ChatChromeTheme.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          tyListenable,
          _stripOffset,
          _searchBusy,
          ?shadowListenable,
          ?modeListenable,
        ]),
        builder: (context, child) {
          final searchOpen = modeListenable?.value ?? widget.searchMode;
          final ty = searchOpen ? 0.0 : tyListenable.value;
          // Clip search painting to below the strip (Telegram search-field clip).
          final stripBottom = searchOpen || !_showCategoryStrip
              ? 0.0
              : EmojiCategoryStrip.height + _stripOffset.value + 1;
          return ClipRect(
            clipper: _TopEdgeClipper(stripBottom.clamp(0.0, double.infinity)),
            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: Offset(0, ty),
                child: ColoredBox(
                  color: colors.panelBackground,
                  child: EmojiSearchField(
                    controller: controller,
                    focusNode: focus,
                    searchOpen: searchOpen,
                    showShadow: shadowListenable?.value ?? false,
                    searchBusy: _searchBusy.value,
                    searchSettled: _loadedSearchQuery.isNotEmpty,
                    hintText: widget.searchHintText ?? 'Search',
                    onOpenSearch: onOpen,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Clips the emoji grid below tabs/search (`emojiContainer.drawChild`).
  Widget _clipGridBelowChrome({required Widget child}) {
    final tyListenable = widget.searchFieldTranslationY;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        _stripOffset,
        ?tyListenable,
        ?widget.searchModeListenable,
      ]),
      builder: (context, _) {
        final searchOpen =
            widget.searchModeListenable?.value ?? widget.searchMode;
        final stripBottom = _showCategoryStrip
            ? EmojiCategoryStrip.height + _stripOffset.value + 1
            : 0.0;
        final ty = searchOpen
            ? 0.0
            : (tyListenable?.value ?? EmojiPage.gridPadTop);
        final searchBottom = ty + EmojiSearchField.height + 1;
        final clipTop = math
            .max(stripBottom, searchBottom)
            .clamp(0.0, double.infinity);
        return ClipRect(clipper: _TopEdgeClipper(clipTop), child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final colors = ChatChromeTheme.of(context);
    final sections = _sections;
    final stripTabs = _stripTabs(sections);
    final showStrip =
        _showCategoryStrip && sections.isNotEmpty && _loadedSearchQuery.isEmpty;
    final bottomPad = EmojiPage.gridPadBottom + viewPadding.bottom;
    final scrollPadTop = showStrip ? EmojiPage.gridPadTop : 0.0;
    final pickSource = _searchMode || _loadedSearchQuery.isNotEmpty
        ? EmojiPickSource.search
        : null;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _clipGridBelowChrome(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewportHeight = constraints.maxHeight;
              final columns = _columnCount(constraints.maxWidth);
              final cell = _cellExtent(constraints.maxWidth, columns);
              if (columns != _columns ||
                  (cell - _rowExtent).abs() > 0.5 ||
                  _flat.isEmpty) {
                _rebuildFlat(columns: columns, rowExtent: cell);
              }
              final flat = _flat;
              final emptyExtent = _emptySearchExtent(constraints.maxHeight);
              return NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: <Widget>[
                    SliverPadding(
                      padding: EdgeInsets.only(top: scrollPadTop),
                      sliver: SuperSliverList.builder(
                        listController: _listController,
                        extentEstimation: (index, _) {
                          if (index == null) return 0;
                          if (index < 0 || index >= flat.length) {
                            return _rowExtent;
                          }
                          return switch (flat[index]) {
                            _SearchSpacerItem() => EmojiSearchField.height,
                            _EmptySearchItem() => emptyExtent,
                            _HeaderItem() => EmojiPage.headerHeight,
                            _RowItem(:final isLastSection, :final isLastRow) =>
                              _rowExtent +
                                  (isLastSection && isLastRow ? bottomPad : 0),
                          };
                        },
                        itemBuilder: (context, index) {
                          final item = flat[index];
                          return switch (item) {
                            _SearchSpacerItem() => SizedBox(
                              height: EmojiSearchField.height,
                              width: double.infinity,
                            ),
                            _EmptySearchItem() => SizedBox(
                              height: emptyExtent,
                              width: double.infinity,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    top: EmojiPage.searchEmptyPadTop,
                                  ),
                                  child: Text(
                                    widget.searchEmptyLabel ?? 'No emoji found',
                                    style: TextStyle(
                                      color: colors.panelEmptyText,
                                      fontSize: EmojiPage.searchEmptyFontSize,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _HeaderItem(:final label) => Padding(
                              padding: const EdgeInsets.fromLTRB(
                                EmojiPage.gridPadH,
                                0,
                                EmojiPage.gridPadH,
                                0,
                              ),
                              child: SizedBox(
                                height: EmojiPage.headerHeight,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      start: 8,
                                    ),
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: colors.panelStickerSetName,
                                        fontSize: EmojiPage.headerFontSize,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _RowItem(
                              :final cells,
                              :final isRecent,
                              :final isLastSection,
                              :final isLastRow,
                              :final sectionIndex,
                              :final rowIndex,
                            ) =>
                              Padding(
                                key: ValueKey<String>(
                                  'r-$sectionIndex-$rowIndex',
                                ),
                                padding: EdgeInsets.fromLTRB(
                                  EmojiPage.gridPadH,
                                  0,
                                  EmojiPage.gridPadH,
                                  isLastSection && isLastRow ? bottomPad : 0,
                                ),
                                child: SizedBox(
                                  height: cell,
                                  child: Row(
                                    children: <Widget>[
                                      for (final entry in cells)
                                        SizedBox(
                                          width: cell,
                                          height: cell,
                                          child: _buildGlyphCell(
                                            entry,
                                            cellSize: cell,
                                            isRecent: isRecent,
                                            source:
                                                pickSource ??
                                                (isRecent
                                                    ? EmojiPickSource.recent
                                                    : EmojiPickSource.grid),
                                          ),
                                        ),
                                      if (cells.length < columns)
                                        Spacer(flex: columns - cells.length),
                                    ],
                                  ),
                                ),
                              ),
                          };
                        },
                        itemCount: flat.length,
                        addAutomaticKeepAlives: false,
                        findChildIndexCallback: (key) {
                          if (key case ValueKey<String>(
                            :final value,
                          ) when value.startsWith('r-')) {
                            for (var i = 0; i < flat.length; i++) {
                              if (flat[i] case _RowItem(
                                :final sectionIndex,
                                :final rowIndex,
                              )) {
                                if (value == 'r-$sectionIndex-$rowIndex') {
                                  return i;
                                }
                              }
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        ?_stickySearchOverlay(),
        if (showStrip)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[
                _stripOffset,
                _stripShadowVisible,
                _categoryIndex,
              ]),
              builder: (context, _) => Transform.translate(
                offset: Offset(0, _stripOffset.value),
                child: EmojiCategoryStripOverlay(
                  tabs: stripTabs,
                  selectedIndex: _categoryIndex.value.clamp(
                    0,
                    stripTabs.length - 1,
                  ),
                  onSelect: jumpToSection,
                  shadowVisible: _stripShadowVisible.value,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// --- Private models ---------------------------------------------------------

/// Pre-resolved grid cell — skin-tone / display work happens when sections
/// rebuild (data / prefs), not inside item builders.
@immutable
class _Cell {
  const _Cell({
    required this.pickGlyph,
    required this.displayGlyph,
    required this.supportsSkinTone,
  });

  /// Catalog / recent glyph passed to pick / long-press handlers.
  final String pickGlyph;

  /// Glyph painted in the cell (skin tone already applied when applicable).
  final String displayGlyph;

  /// Whether long-press opens the skin-tone picker.
  final bool supportsSkinTone;
}

/// One catalog (or recents) section in the flat list.
class _Section {
  const _Section({
    required this.id,
    required this.label,
    required this.cells,
    required this.isRecent,
    required this.stripIcon,
  });

  final String id;
  final String label;
  final List<_Cell> cells;
  final bool isRecent;
  final EmojiStripIcon stripIcon;
}

/// Flat-list item: search spacer, empty search, section header, or glyph row.
sealed class _FlatItem {
  const _FlatItem();

  const factory _FlatItem.searchSpacer() = _SearchSpacerItem;

  const factory _FlatItem.emptySearch() = _EmptySearchItem;

  const factory _FlatItem.header({
    required int sectionIndex,
    required String label,
    required bool isFirst,
  }) = _HeaderItem;

  const factory _FlatItem.row({
    required int sectionIndex,
    required int rowIndex,
    required List<_Cell> cells,
    required bool isRecent,
    required bool isLastSection,
    required bool isLastRow,
  }) = _RowItem;
}

final class _SearchSpacerItem extends _FlatItem {
  const _SearchSpacerItem();
}

/// Keyword search with zero hits.
final class _EmptySearchItem extends _FlatItem {
  const _EmptySearchItem();
}

final class _HeaderItem extends _FlatItem {
  const _HeaderItem({
    required this.sectionIndex,
    required this.label,
    required this.isFirst,
  });

  final int sectionIndex;
  final String label;
  final bool isFirst;
}

final class _RowItem extends _FlatItem {
  const _RowItem({
    required this.sectionIndex,
    required this.rowIndex,
    required this.cells,
    required this.isRecent,
    required this.isLastSection,
    required this.isLastRow,
  });

  final int sectionIndex;
  final int rowIndex;
  final List<_Cell> cells;
  final bool isRecent;
  final bool isLastSection;
  final bool isLastRow;
}

/// Clips painting below [top] (Telegram `emojiContainer.drawChild` top edge).
final class _TopEdgeClipper extends CustomClipper<Rect> {
  _TopEdgeClipper(this.top);

  final double top;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, size.height);

  @override
  bool shouldReclip(covariant _TopEdgeClipper oldClipper) =>
      oldClipper.top != top;
}

/// Alias for embedding the grid outside [EmojiPanel].
///
/// Same widget as [EmojiPage]; prefer this name at call sites that are not
/// a page inside the panel pager.
typedef EmojiGridView = EmojiPage;
